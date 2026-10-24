const std = @import("std");

const evdev = @import("../evdev.zig");
const monitor = @import("../monitor.zig");
const mouse_event = @import("../../../event/mouse.zig");
const position_module = @import("../../../position.zig");
const runtime = @import("../runtime.zig");
const uinput = @import("../uinput.zig");

const assert = std.debug.assert;

const Position = position_module.Position;

pub const Button = mouse_event.MouseEvent.Button;

pub const scroll_clicks_max: u32 = 32;

comptime {
    assert(scroll_clicks_max > 0);
}

fn device() *uinput.Device {
    return &runtime.current().mouse_out;
}

fn code_of(button: Button) u16 {
    assert(button.is_valid());

    return switch (button) {
        .left => evdev.BTN_LEFT,
        .right => evdev.BTN_RIGHT,
        .middle => evdev.BTN_MIDDLE,
        .x1 => evdev.BTN_SIDE,
        .x2 => evdev.BTN_EXTRA,
    };
}

pub fn is_open() bool {
    return device().is_open();
}

pub fn button_down(button: Button) bool {
    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.button(code_of(button), true) catch return false;

    return true;
}

pub fn button_up(button: Button) bool {
    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.button(code_of(button), false) catch return false;

    return true;
}

pub fn click(button: Button) bool {
    const down = button_down(button);
    const up = button_up(button);

    return down and up;
}

pub fn move_relative(offset: Position) bool {
    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.move_relative(offset.x, offset.y) catch return false;

    const current = monitor.get_cursor_position();

    monitor.set_cursor_position(.{ .x = current.x + offset.x, .y = current.y + offset.y });

    return true;
}

pub fn move_to(position: Position) bool {
    const current = monitor.get_cursor_position();
    return move_relative(.{ .x = position.x - current.x, .y = position.y - current.y });
}

pub fn scroll_up(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.scroll(@intCast(clicks), 0) catch return false;

    return true;
}

pub fn scroll_down(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.scroll(-@as(i32, @intCast(clicks)), 0) catch return false;

    return true;
}

pub fn scroll_left(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.scroll(0, -@as(i32, @intCast(clicks))) catch return false;

    return true;
}

pub fn scroll_right(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.scroll(0, @intCast(clicks)) catch return false;

    return true;
}

pub fn get_position() Position {
    return monitor.get_cursor_position();
}

const testing = std.testing;

test "buttons map onto their evdev codes" {
    try testing.expectEqual(evdev.BTN_LEFT, code_of(.left));
    try testing.expectEqual(evdev.BTN_RIGHT, code_of(.right));
    try testing.expectEqual(evdev.BTN_MIDDLE, code_of(.middle));
    try testing.expectEqual(evdev.BTN_SIDE, code_of(.x1));
    try testing.expectEqual(evdev.BTN_EXTRA, code_of(.x2));
}

test "synthesis is inert until the runtime opens its device" {
    try testing.expect(!runtime.is_open());
    try testing.expect(!is_open());
    try testing.expect(!click(.left));
    try testing.expect(!move_relative(.{ .x = 5, .y = 5 }));
    try testing.expect(!scroll_up(1));
}
