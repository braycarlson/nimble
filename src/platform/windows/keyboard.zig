const std = @import("std");

const event = @import("event.zig");
const hook = @import("hook.zig");
const interface = @import("../interface.zig");
const key_event = @import("../../event.zig").key;
const Loop = @import("loop.zig");
const Rescue = @import("rescue.zig");
const response_module = @import("../../response.zig");
const Runtime = @import("runtime.zig");
const win32 = @import("win32.zig");

const assert = std.debug.assert;

const Hook = hook.Hook;
const HookError = interface.HookError;
const Key = key_event.Key;
const Response = response_module.Response;

handle: ?Hook = null,
module: ?win32.HINSTANCE = null,
callback: ?hook.Callback = null,
owner: std.atomic.Value(?*anyopaque) = .init(null),
dispatch: std.atomic.Value(?Dispatch) = .init(null),

const Keyboard = @This();

const Dispatch = *const fn (owner: *anyopaque, key: *const Key) Response;

pub fn install(
    keyboard: *Keyboard,
    comptime Owner: type,
    owner: *Owner,
    callback: hook.Callback,
    loop: *Loop,
) HookError!void {
    const Trampoline = struct {
        fn dispatch(pointer: *anyopaque, key: *const Key) Response {
            const typed: *Owner = @ptrCast(@alignCast(pointer));
            const result = typed.process(key);

            assert(result.is_valid());

            return result;
        }
    };

    assert(keyboard.handle == null);

    keyboard.module = hook.module();

    const module = keyboard.module orelse return error.HookInstallFailed;

    if (keyboard.owner.cmpxchgStrong(null, owner, .seq_cst, .seq_cst) != null) {
        return error.HookDuplicate;
    }

    keyboard.dispatch.store(Trampoline.dispatch, .seq_cst);
    keyboard.handle = Hook.install(.keyboard, callback, module);

    if (keyboard.handle == null) {
        keyboard.dispatch.store(null, .seq_cst);
        keyboard.owner.store(null, .seq_cst);

        return error.HookInstallFailed;
    }

    keyboard.callback = callback;

    loop.claim_thread();

    assert(keyboard.handle != null);
    assert(keyboard.module != null);
}

pub fn reinstall(keyboard: *Keyboard) void {
    const previous = keyboard.handle orelse return;
    const module = keyboard.module orelse return;
    const callback = keyboard.callback orelse return;
    const handle = Hook.install(.keyboard, callback, module) orelse return;

    keyboard.handle = handle;

    _ = previous.remove();

    assert(keyboard.handle.?.kind == .keyboard);
    assert(keyboard.handle.?.handle != previous.handle);
}

pub fn remove(keyboard: *Keyboard, loop: *Loop) void {
    const handle = keyboard.handle orelse return;

    keyboard.dispatch.store(null, .seq_cst);
    keyboard.owner.store(null, .seq_cst);

    _ = handle.remove();

    keyboard.handle = null;

    loop.release_thread();

    assert(keyboard.handle == null);
    assert(keyboard.owner.load(.seq_cst) == null);
}

pub fn is_installed(keyboard: *const Keyboard) bool {
    return keyboard.dispatch.load(.seq_cst) != null;
}

pub fn procedure(
    keyboard: *Keyboard,
    rescue: *Rescue,
    runtime: *Runtime,
    code: c_int,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) win32.LRESULT {
    if (code < 0) {
        return hook.next(code, wparam, lparam);
    }

    assert(code >= 0);

    const parsed = event.parse_key(wparam, lparam) orelse return hook.next(code, wparam, lparam);
    const dispatch = keyboard.dispatch.load(.seq_cst) orelse return hook.next(code, wparam, lparam);
    const owner = keyboard.owner.load(.seq_cst) orelse return hook.next(code, wparam, lparam);

    assert(parsed.is_valid());

    rescue.regrab_if_due(runtime, parsed.time_ms);

    if (!parsed.injected) rescue.observe(runtime, parsed.value, parsed.down, parsed.time_ms);

    const response = dispatch(owner, &parsed);

    assert(response.is_valid());

    if (response.should_block()) {
        return 1;
    }

    return hook.next(code, wparam, lparam);
}

const testing = std.testing;

const Watcher = struct {
    pub fn process(_: *Watcher, _: *const Key) Response {
        return .pass;
    }
};

const Listener = struct {
    pub fn process(_: *Listener, _: *const Key) Response {
        return .pass;
    }
};

fn ignore(_: c_int, _: win32.WPARAM, _: win32.LPARAM) callconv(.c) win32.LRESULT {
    return 0;
}

test "one keyboard hook slot is shared across every owner type" {
    var keyboard: Keyboard = .{};
    var loop: Loop = .{};
    var watcher = Watcher{};
    var listener = Listener{};

    keyboard.owner.store(&watcher, .seq_cst);

    const refused = keyboard.install(Listener, &listener, ignore, &loop);

    try testing.expectError(error.HookDuplicate, refused);
    try testing.expect(keyboard.handle == null);
}

test "removing a hook that never installed leaves the slot alone" {
    var keyboard: Keyboard = .{};
    var loop: Loop = .{};
    var watcher = Watcher{};

    keyboard.owner.store(&watcher, .seq_cst);

    keyboard.remove(&loop);

    try testing.expect(keyboard.owner.load(.seq_cst) != null);
}
