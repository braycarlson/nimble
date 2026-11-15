const std = @import("std");

const event = @import("event.zig");
const hook = @import("hook.zig");
const interface = @import("../interface.zig");
const Loop = @import("loop.zig");
const mouse_event = @import("../../event.zig").mouse;
const Rescue = @import("rescue.zig");
const response_module = @import("../../response.zig");
const Runtime = @import("runtime.zig");
const win32 = @import("win32.zig");

const assert = std.debug.assert;

const Hook = hook.Hook;
const HookError = interface.HookError;
const MouseEvent = mouse_event.MouseEvent;
const Response = response_module.Response;

handle: ?Hook = null,
module: ?win32.HINSTANCE = null,
callback: ?hook.Callback = null,
owner: std.atomic.Value(?*anyopaque) = .init(null),
dispatch: std.atomic.Value(?Dispatch) = .init(null),

const Mouse = @This();

const Dispatch = *const fn (owner: *anyopaque, value: *const MouseEvent) Response;

pub fn install(
    mouse: *Mouse,
    comptime Owner: type,
    owner: *Owner,
    callback: hook.Callback,
    loop: *Loop,
) HookError!void {
    const Trampoline = struct {
        fn dispatch(pointer: *anyopaque, value: *const MouseEvent) Response {
            const typed: *Owner = @ptrCast(@alignCast(pointer));
            const result = typed.process(value);

            assert(result.is_valid());

            return result;
        }
    };

    assert(mouse.handle == null);

    mouse.module = hook.module();

    const module = mouse.module orelse return error.HookInstallFailed;

    if (mouse.owner.cmpxchgStrong(null, owner, .seq_cst, .seq_cst) != null) {
        return error.HookDuplicate;
    }

    mouse.dispatch.store(Trampoline.dispatch, .seq_cst);
    mouse.handle = Hook.install(.mouse, callback, module);

    if (mouse.handle == null) {
        mouse.dispatch.store(null, .seq_cst);
        mouse.owner.store(null, .seq_cst);

        return error.HookInstallFailed;
    }

    mouse.callback = callback;

    loop.claim_thread();

    assert(mouse.handle != null);
    assert(mouse.module != null);
}

pub fn reinstall(mouse: *Mouse) void {
    const previous = mouse.handle orelse return;
    const module = mouse.module orelse return;
    const callback = mouse.callback orelse return;
    const handle = Hook.install(.mouse, callback, module) orelse return;

    mouse.handle = handle;

    _ = previous.remove();

    assert(mouse.handle.?.kind == .mouse);
    assert(mouse.handle.?.handle != previous.handle);
}

pub fn remove(mouse: *Mouse, loop: *Loop) void {
    const handle = mouse.handle orelse return;

    mouse.dispatch.store(null, .seq_cst);
    mouse.owner.store(null, .seq_cst);

    _ = handle.remove();

    mouse.handle = null;

    loop.release_thread();

    assert(mouse.handle == null);
    assert(mouse.owner.load(.seq_cst) == null);
}

pub fn is_installed(mouse: *const Mouse) bool {
    return mouse.dispatch.load(.seq_cst) != null;
}

pub fn procedure(
    mouse: *Mouse,
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

    const parsed = event.parse_mouse(wparam, lparam) orelse return hook.next(code, wparam, lparam);
    const dispatch = mouse.dispatch.load(.seq_cst) orelse return hook.next(code, wparam, lparam);
    const owner = mouse.owner.load(.seq_cst) orelse return hook.next(code, wparam, lparam);

    assert(parsed.is_valid());

    rescue.regrab_if_due(runtime, parsed.time_ms);

    const response = dispatch(owner, &parsed);

    assert(response.is_valid());

    if (response.should_block()) {
        return 1;
    }

    return hook.next(code, wparam, lparam);
}

const testing = std.testing;

const Watcher = struct {
    pub fn process(_: *Watcher, _: *const MouseEvent) Response {
        return .pass;
    }
};

const Listener = struct {
    pub fn process(_: *Listener, _: *const MouseEvent) Response {
        return .pass;
    }
};

fn ignore(_: c_int, _: win32.WPARAM, _: win32.LPARAM) callconv(.c) win32.LRESULT {
    return 0;
}

test "one mouse hook slot is shared across every owner type" {
    var mouse: Mouse = .{};
    var loop: Loop = .{};
    var watcher = Watcher{};
    var listener = Listener{};

    mouse.owner.store(&watcher, .seq_cst);

    const refused = mouse.install(Listener, &listener, ignore, &loop);

    try testing.expectError(error.HookDuplicate, refused);
    try testing.expect(mouse.handle == null);
}
