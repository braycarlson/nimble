const std = @import("std");

const interface = @import("../interface.zig");
const key_event = @import("../../event.zig").key;
const response_module = @import("../../response.zig");

const assert = std.debug.assert;

const HookError = interface.HookError;
const Key = key_event.Key;
const Response = response_module.Response;

owner: std.atomic.Value(?*anyopaque) = .init(null),
dispatch: std.atomic.Value(?Dispatch) = .init(null),

const Keyboard = @This();

const Dispatch = *const fn (owner: *anyopaque, key: *const Key) Response;

pub fn install(keyboard: *Keyboard, comptime Owner: type, owner: *Owner) HookError!void {
    const Trampoline = struct {
        fn dispatch(pointer: *anyopaque, key: *const Key) Response {
            const typed: *Owner = @ptrCast(@alignCast(pointer));
            const result = typed.process(key);

            assert(result.is_valid());

            return result;
        }
    };

    if (keyboard.owner.cmpxchgStrong(null, owner, .seq_cst, .seq_cst) != null) {
        return error.HookDuplicate;
    }

    keyboard.dispatch.store(Trampoline.dispatch, .seq_cst);

    assert(keyboard.is_installed());
    assert(keyboard.owner.load(.seq_cst) == @as(*anyopaque, owner));
}

pub fn remove(keyboard: *Keyboard) void {
    keyboard.dispatch.store(null, .seq_cst);
    keyboard.owner.store(null, .seq_cst);

    assert(!keyboard.is_installed());
    assert(keyboard.owner.load(.seq_cst) == null);
}

pub fn feed(keyboard: *Keyboard, key: *const Key) Response {
    assert(key.is_valid());

    const dispatch = keyboard.dispatch.load(.seq_cst) orelse return .pass;
    const owner = keyboard.owner.load(.seq_cst) orelse return .pass;
    const result = dispatch(owner, key);

    assert(result.is_valid());

    return result;
}

pub fn is_installed(keyboard: *const Keyboard) bool {
    return keyboard.dispatch.load(.seq_cst) != null;
}

const testing = std.testing;

const Counter = struct {
    hits: u32 = 0,

    pub fn process(counter: *Counter, _: *const Key) Response {
        counter.hits += 1;

        return .consume;
    }
};

test "a keyboard hook slot holds one owner and routes each key to it" {
    var keyboard: Keyboard = .{};
    var counter = Counter{};
    var second = Counter{};

    const key = Key{ .value = .a, .down = true };

    try testing.expectEqual(Response.pass, keyboard.feed(&key));

    try keyboard.install(Counter, &counter);

    try testing.expectError(error.HookDuplicate, keyboard.install(Counter, &second));
    try testing.expectEqual(Response.consume, keyboard.feed(&key));
    try testing.expectEqual(@as(u32, 1), counter.hits);

    keyboard.remove();

    try testing.expectEqual(Response.pass, keyboard.feed(&key));
    try testing.expectEqual(@as(u32, 0), second.hits);
}
