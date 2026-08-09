const std = @import("std");

const key_event = @import("../../event/key.zig");
const mouse_event = @import("../../event/mouse.zig");
const response_mod = @import("../../response.zig");
const keyboard = @import("keyboard.zig");
const mouse = @import("mouse.zig");
const runtime = @import("runtime.zig");
const state = @import("state.zig");
const timer = @import("timer.zig");
const time = @import("time.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Mouse = mouse_event.Mouse;
const Response = response_mod.Response;

pub const capacity: u16 = 4096;
pub const iteration_count_max: u32 = capacity;

pub const Event = union(enum) {
    key: Key,
    mouse: Mouse,
    advance_ms: u32,
};

var tape: [capacity]Event = undefined;
var tape_count: u16 = 0;
var tape_position: u16 = 0;
var responses: [capacity]Response = undefined;
var response_count: u16 = 0;
var stopped: bool = false;

comptime {
    assert(capacity > 0);
    assert(iteration_count_max == capacity);
}

pub fn push_key(key: Key) void {
    assert(tape_count < capacity);

    tape[tape_count] = .{ .key = key };
    tape_count += 1;

    assert(tape_count <= capacity);
}

pub fn push_mouse(event: Mouse) void {
    assert(tape_count < capacity);

    tape[tape_count] = .{ .mouse = event };
    tape_count += 1;

    assert(tape_count <= capacity);
}

pub fn push_advance(duration_ms: u32) void {
    assert(tape_count < capacity);

    tape[tape_count] = .{ .advance_ms = duration_ms };
    tape_count += 1;

    assert(tape_count <= capacity);
}

pub fn run() void {
    assert(runtime.is_open());

    stopped = false;

    var iteration: u32 = 0;

    while (iteration < iteration_count_max) : (iteration += 1) {
        if (!poll(0)) {
            break;
        }
    }

    assert(iteration < iteration_count_max);
}

pub fn poll(timeout_ms: u32) bool {
    if (stopped or !runtime.is_open()) {
        return false;
    }

    if (timeout_ms > 0) {
        time.advance(timeout_ms);
    }

    _ = timer.fire_due();

    return step();
}

pub fn stop() void {
    stopped = true;

    assert(stopped);
}

fn step() bool {
    if (tape_position >= tape_count) {
        return false;
    }

    assert(tape_position < capacity);

    const event = tape[tape_position];

    tape_position += 1;

    switch (event) {
        .key => |value| {
            if (value.down) {
                state.set_down(value.value);
            } else {
                state.set_up(value.value);
            }

            record_response(keyboard.feed(&value));
        },
        .mouse => |value| record_response(mouse.feed(&value)),
        .advance_ms => |duration| {
            time.advance(duration);
            _ = timer.fire_due();
        },
    }

    assert(tape_position <= tape_count);

    return true;
}

fn record_response(response: Response) void {
    assert(response.is_valid());
    assert(response_count <= capacity);

    if (response_count == capacity) {
        return;
    }

    responses[response_count] = response;
    response_count += 1;
}

pub fn response_len() u16 {
    return response_count;
}

pub fn response_at(index: u16) Response {
    assert(index < response_count);

    return responses[index];
}

pub fn pending() u16 {
    assert(tape_position <= tape_count);

    return tape_count - tape_position;
}

pub fn reset() void {
    tape_count = 0;
    tape_position = 0;
    response_count = 0;
    stopped = false;

    assert(pending() == 0);
    assert(response_count == 0);
}
