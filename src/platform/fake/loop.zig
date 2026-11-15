const std = @import("std");

const key_event = @import("../../event.zig").key;
const mouse_event = @import("../../event.zig").mouse;
const response_module = @import("../../response.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const MouseEvent = mouse_event.MouseEvent;
const Response = response_module.Response;

queue: [capacity]Event = undefined,
queue_count: u16 = 0,
queue_position: u16 = 0,
responses: [capacity]Response = undefined,
response_count: u16 = 0,
stopped: bool = false,

const Loop = @This();

pub const Event = union(enum) {
    key: Key,
    mouse: MouseEvent,
    advance_ms: u32,
};

pub const capacity: u16 = 4096;

comptime {
    assert(capacity > 0);
}

pub fn push_key(loop: *Loop, key: Key) void {
    assert(key.is_valid());

    loop.push(.{ .key = key });
}

pub fn push_mouse(loop: *Loop, event: MouseEvent) void {
    assert(event.is_valid());

    loop.push(.{ .mouse = event });
}

pub fn push_advance(loop: *Loop, duration_ms: u32) void {
    assert(duration_ms <= std.math.maxInt(i32));

    loop.push(.{ .advance_ms = duration_ms });
}

fn push(loop: *Loop, event: Event) void {
    assert(loop.queue_count < capacity);

    loop.queue[loop.queue_count] = event;
    loop.queue_count += 1;

    assert(loop.queue_count <= capacity);
}

pub fn next(loop: *Loop) ?Event {
    assert(loop.queue_position <= loop.queue_count);

    if (loop.queue_position == loop.queue_count) {
        return null;
    }

    const event = loop.queue[loop.queue_position];

    loop.queue_position += 1;

    assert(loop.queue_position <= loop.queue_count);

    return event;
}

pub fn record_response(loop: *Loop, response: Response) void {
    assert(response.is_valid());
    assert(loop.response_count <= capacity);

    if (loop.response_count == capacity) {
        return;
    }

    loop.responses[loop.response_count] = response;
    loop.response_count += 1;
}

pub fn response_len(loop: *const Loop) u16 {
    assert(loop.response_count <= capacity);

    return loop.response_count;
}

pub fn response_at(loop: *const Loop, index: u16) Response {
    assert(index < loop.response_count);

    return loop.responses[index];
}

pub fn pending(loop: *const Loop) u16 {
    assert(loop.queue_position <= loop.queue_count);

    return loop.queue_count - loop.queue_position;
}

pub fn stop(loop: *Loop) void {
    loop.stopped = true;

    assert(loop.stopped);
}

const testing = std.testing;

test "the queue hands back events in the order they were pushed" {
    var loop: Loop = .{};

    loop.push_advance(10);
    loop.push_key(.{ .value = .a, .down = true });

    try testing.expectEqual(@as(u16, 2), loop.pending());

    const first = loop.next() orelse return error.EventMissing;
    const second = loop.next() orelse return error.EventMissing;
    const third = loop.next();

    try testing.expectEqual(@as(u32, 10), first.advance_ms);
    try testing.expect(second.key.value == .a);
    try testing.expect(third == null);

    loop.record_response(.consume);

    try testing.expectEqual(@as(u16, 1), loop.response_len());
    try testing.expectEqual(Response.consume, loop.response_at(0));
}
