const std = @import("std");

const evdev = @import("../evdev.zig");
const monitor_mod = @import("../monitor.zig");
const runtime = @import("../runtime.zig");
const uinput = @import("../uinput.zig");

const assert = std.debug.assert;

pub const Monitor = monitor_mod.Monitor;
pub const MonitorList = monitor_mod.List;
pub const Position = monitor_mod.Position;
pub const Screen = monitor_mod.Screen;

pub const scroll_clicks_max: u32 = 32;
pub const button_max: u8 = 4;
pub const monitor_max: u8 = monitor_mod.max;

pub const Button = enum(u8) {
    left = 0,
    right = 1,
    middle = 2,
    x1 = 3,
    x2 = 4,

    pub fn is_valid(button: Button) bool {
        return @intFromEnum(button) <= button_max;
    }

    pub fn to_code(button: Button) u16 {
        assert(button.is_valid());

        return switch (button) {
            .left => evdev.BTN_LEFT,
            .right => evdev.BTN_RIGHT,
            .middle => evdev.BTN_MIDDLE,
            .x1 => evdev.BTN_SIDE,
            .x2 => evdev.BTN_EXTRA,
        };
    }
};

comptime {
    assert(scroll_clicks_max > 0);
}

fn device() *uinput.Device {
    return &runtime.current().mouse_out;
}

pub fn is_open() bool {
    return device().is_open();
}

pub fn button_down(button: Button) bool {
    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.button(button.to_code(), true) catch return false;

    return true;
}

pub fn button_up(button: Button) bool {
    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.button(button.to_code(), false) catch return false;

    return true;
}

pub fn click(button: Button) bool {
    const down = button_down(button);
    const up = button_up(button);

    return down and up;
}

pub fn left_click() bool {
    return click(.left);
}

pub fn right_click() bool {
    return click(.right);
}

pub fn middle_click() bool {
    return click(.middle);
}

pub fn double_click(button: Button) bool {
    const first = click(button);
    const second = click(button);

    return first and second;
}

pub fn left_double_click() bool {
    return double_click(.left);
}

pub fn move_relative(dx: i32, dy: i32) bool {
    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.move_relative(dx, dy) catch return false;

    const current = monitor_mod.get_cursor_position();

    monitor_mod.set_cursor_position(Position.init(current.x + dx, current.y + dy));

    return true;
}

pub fn move_to(x: i32, y: i32) bool {
    const current = monitor_mod.get_cursor_position();

    return move_relative(x - current.x, y - current.y);
}

pub fn move_to_position(position: Position) bool {
    return move_to(position.x, position.y);
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
    assert(clicks <= scroll_clicks_max);

    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.scroll(0, -@as(i32, @intCast(clicks))) catch return false;

    return true;
}

pub fn scroll_right(clicks: u32) bool {
    assert(clicks <= scroll_clicks_max);

    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.scroll(0, @intCast(clicks)) catch return false;

    return true;
}

pub fn drag(button: Button, from: Position, to: Position) bool {
    const start = move_to_position(from);
    const press = button_down(button);
    const finish = move_to_position(to);
    const release = button_up(button);

    return start and press and finish and release;
}

pub fn left_drag(from: Position, to: Position) bool {
    return drag(.left, from, to);
}

pub fn click_at(button: Button, x: i32, y: i32) bool {
    const moved = move_to(x, y);
    const clicked = click(button);

    return moved and clicked;
}

pub fn left_click_at(x: i32, y: i32) bool {
    return click_at(.left, x, y);
}

pub fn right_click_at(x: i32, y: i32) bool {
    return click_at(.right, x, y);
}

pub fn get_position() Position {
    return monitor_mod.get_cursor_position();
}

const testing = std.testing;

test "buttons map onto their evdev codes" {
    try testing.expectEqual(evdev.BTN_LEFT, Button.left.to_code());
    try testing.expectEqual(evdev.BTN_RIGHT, Button.right.to_code());
    try testing.expectEqual(evdev.BTN_MIDDLE, Button.middle.to_code());
    try testing.expectEqual(evdev.BTN_SIDE, Button.x1.to_code());
    try testing.expectEqual(evdev.BTN_EXTRA, Button.x2.to_code());
}

test "synthesis is inert until the runtime opens its device" {
    try testing.expect(!runtime.is_open());
    try testing.expect(!is_open());
    try testing.expect(!left_click());
    try testing.expect(!move_relative(5, 5));
    try testing.expect(!scroll_up(1));
}

pub fn move_to_monitor(index: u8, x: i32, y: i32) bool {
    const monitor = monitor_mod.get(index) orelse return false;

    return move_to(monitor.left + x, monitor.top + y);
}

pub fn move_to_monitor_center(index: u8) bool {
    const monitor = monitor_mod.get(index) orelse return false;
    const center = monitor.center();

    return move_to(center.x, center.y);
}

pub fn move_to_primary_monitor(x: i32, y: i32) bool {
    return move_to_monitor(0, x, y);
}

pub fn move_to_primary_center() bool {
    return move_to_monitor_center(0);
}

pub fn click_on_monitor(button: Button, index: u8, x: i32, y: i32) bool {
    const moved = move_to_monitor(index, x, y);
    const clicked = click(button);

    return moved and clicked;
}

pub fn left_click_on_monitor(index: u8, x: i32, y: i32) bool {
    return click_on_monitor(.left, index, x, y);
}

pub fn right_click_on_monitor(index: u8, x: i32, y: i32) bool {
    return click_on_monitor(.right, index, x, y);
}

pub fn get_monitors() MonitorList {
    return monitor_mod.get_all();
}

pub fn get_monitor(index: u8) ?Monitor {
    return monitor_mod.get(index);
}

pub fn get_primary_monitor() ?Monitor {
    return monitor_mod.get_primary();
}

pub fn get_current_monitor() ?Monitor {
    return monitor_mod.get_current();
}

pub fn get_monitor_at(x: i32, y: i32) ?Monitor {
    return monitor_mod.get_at(x, y);
}

pub fn get_monitor_count() u8 {
    return monitor_mod.get_count();
}

test "monitor targeted motion declines when no compositor is configured" {
    monitor_mod.invalidate();

    try testing.expect(!move_to_monitor(0, 10, 10));
    try testing.expect(!move_to_primary_center());
    try testing.expect(!left_click_on_monitor(0, 5, 5));
}
