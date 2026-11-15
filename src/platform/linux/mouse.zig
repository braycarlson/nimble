const std = @import("std");

const interface = @import("../interface.zig");
const mouse_event = @import("../../event.zig").mouse;
const response_module = @import("../../response.zig");

const assert = std.debug.assert;

const HookError = interface.HookError;
const MouseEvent = mouse_event.MouseEvent;
const Response = response_module.Response;

owner: std.atomic.Value(?*anyopaque) = .init(null),
dispatch: std.atomic.Value(?Dispatch) = .init(null),

const Mouse = @This();

const Dispatch = *const fn (owner: *anyopaque, event: *const MouseEvent) Response;

pub fn install(mouse: *Mouse, comptime Owner: type, owner: *Owner) HookError!void {
    const Trampoline = struct {
        fn dispatch(pointer: *anyopaque, event: *const MouseEvent) Response {
            const typed: *Owner = @ptrCast(@alignCast(pointer));
            const result = typed.process(event);

            assert(result.is_valid());

            return result;
        }
    };

    if (mouse.owner.cmpxchgStrong(null, owner, .seq_cst, .seq_cst) != null) {
        return error.HookDuplicate;
    }

    mouse.dispatch.store(Trampoline.dispatch, .seq_cst);

    assert(mouse.is_installed());
    assert(mouse.owner.load(.seq_cst) == @as(*anyopaque, owner));
}

pub fn remove(mouse: *Mouse) void {
    mouse.dispatch.store(null, .seq_cst);
    mouse.owner.store(null, .seq_cst);

    assert(!mouse.is_installed());
    assert(mouse.owner.load(.seq_cst) == null);
}

pub fn feed(mouse: *Mouse, event: *const MouseEvent) Response {
    assert(event.is_valid());

    const dispatch = mouse.dispatch.load(.seq_cst) orelse return .pass;
    const owner = mouse.owner.load(.seq_cst) orelse return .pass;
    const result = dispatch(owner, event);

    assert(result.is_valid());

    return result;
}

pub fn is_installed(mouse: *const Mouse) bool {
    return mouse.dispatch.load(.seq_cst) != null;
}

const testing = std.testing;

const Counter = struct {
    hits: u32 = 0,

    pub fn process(counter: *Counter, _: *const MouseEvent) Response {
        counter.hits += 1;

        return .consume;
    }
};

test "a mouse hook slot holds one owner and routes each event to it" {
    var mouse: Mouse = .{};
    var counter = Counter{};
    var second = Counter{};

    const event = MouseEvent.from_button(.{ .button = .left, .down = true }, .{});

    try testing.expectEqual(Response.pass, mouse.feed(&event));

    try mouse.install(Counter, &counter);

    try testing.expectError(error.HookDuplicate, mouse.install(Counter, &second));
    try testing.expectEqual(Response.consume, mouse.feed(&event));
    try testing.expectEqual(@as(u32, 1), counter.hits);

    mouse.remove();

    try testing.expectEqual(Response.pass, mouse.feed(&event));
    try testing.expectEqual(@as(u32, 0), second.hits);
}
