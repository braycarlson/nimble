const std = @import("std");

const evdev = @import("../evdev.zig");
const Monitor = @import("../monitor.zig");
const mouse_event = @import("../../../event.zig").mouse;
const position_module = @import("../../../position.zig");
const uinput = @import("../uinput.zig");

const assert = std.debug.assert;

const Device = uinput.Device;
const Position = position_module.Position;

pub const Button = mouse_event.MouseEvent.Button;

pub const scroll_clicks_max: u32 = 32;

comptime {
    assert(scroll_clicks_max > 0);
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

pub fn is_open(out: *const Device) bool {
    return out.is_open();
}

pub fn button_down(out: *Device, button: Button) bool {
    if (!out.is_open()) {
        return false;
    }

    out.button(code_of(button), true) catch return false;

    return true;
}

pub fn button_up(out: *Device, button: Button) bool {
    if (!out.is_open()) {
        return false;
    }

    out.button(code_of(button), false) catch return false;

    return true;
}

pub fn click(out: *Device, button: Button) bool {
    const down = button_down(out, button);
    const up = button_up(out, button);

    return down and up;
}

pub fn move_relative(out: *Device, monitor: *Monitor, offset: Position) bool {
    if (!out.is_open()) {
        return false;
    }

    out.move_relative(offset.x, offset.y) catch return false;

    const current = monitor.get_cursor_position();

    monitor.set_cursor_position(.{ .x = current.x + offset.x, .y = current.y + offset.y });

    return true;
}

pub fn move_to(out: *Device, monitor: *Monitor, position: Position) bool {
    const current = monitor.get_cursor_position();
    const offset = Position{ .x = position.x - current.x, .y = position.y - current.y };

    return move_relative(out, monitor, offset);
}

pub fn scroll_up(out: *Device, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    if (!out.is_open()) {
        return false;
    }

    out.scroll(@intCast(clicks), 0) catch return false;

    return true;
}

pub fn scroll_down(out: *Device, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    if (!out.is_open()) {
        return false;
    }

    out.scroll(-@as(i32, @intCast(clicks)), 0) catch return false;

    return true;
}

pub fn scroll_left(out: *Device, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    if (!out.is_open()) {
        return false;
    }

    out.scroll(0, -@as(i32, @intCast(clicks))) catch return false;

    return true;
}

pub fn scroll_right(out: *Device, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    if (!out.is_open()) {
        return false;
    }

    out.scroll(0, @intCast(clicks)) catch return false;

    return true;
}

pub fn get_position(monitor: *const Monitor) Position {
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
    var out = Device{};
    var monitor = Monitor{};

    try testing.expect(!is_open(&out));
    try testing.expect(!click(&out, .left));
    try testing.expect(!move_relative(&out, &monitor, .{ .x = 5, .y = 5 }));
    try testing.expect(!scroll_up(&out, 1));
}
