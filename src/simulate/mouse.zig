const std = @import("std");

const mouse_event = @import("../event/mouse.zig");
const platform = @import("../platform.zig");
const position_module = @import("../position.zig");

const assert = std.debug.assert;

const backend = platform.backend.simulate.mouse;

const Button = mouse_event.MouseEvent.Button;
const Position = position_module.Position;

pub const scroll_clicks_max: u32 = backend.scroll_clicks_max;

pub fn button_down(button: Button) bool {
    return backend.button_down(button);
}

pub fn button_up(button: Button) bool {
    return backend.button_up(button);
}

pub fn click(button: Button) bool {
    return backend.click(button);
}

pub fn move_relative(offset: Position) bool {
    return backend.move_relative(offset);
}

pub fn move_to(target: Position) bool {
    return backend.move_to(target);
}

pub fn position() Position {
    return backend.get_position();
}

pub fn scroll_down(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    return backend.scroll_down(clicks);
}

pub fn scroll_left(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    return backend.scroll_left(clicks);
}

pub fn scroll_right(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    return backend.scroll_right(clicks);
}

pub fn scroll_up(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    return backend.scroll_up(clicks);
}

const testing = std.testing;

const record = platform.mock.record;

test button_down {
    platform.mock.reset();

    try testing.expect(button_down(.left));
    try testing.expectEqual(@as(u16, 1), record.count_of(.mouse_down));
}

test button_up {
    platform.mock.reset();

    try testing.expect(button_up(.right));
    try testing.expectEqual(@as(u16, 1), record.count_of(.mouse_up));
}

test click {
    platform.mock.reset();

    try testing.expect(click(.middle));
    try testing.expectEqual(@as(u16, 1), record.count_of(.mouse_down));
    try testing.expectEqual(@as(u16, 1), record.count_of(.mouse_up));
}

test move_relative {
    platform.mock.reset();

    try testing.expect(move_to(.{ .x = 100, .y = 100 }));
    try testing.expect(move_relative(.{ .x = 20, .y = -10 }));
    try testing.expect(position().eql(.{ .x = 120, .y = 90 }));
}

test move_to {
    platform.mock.reset();

    try testing.expect(move_to(.{ .x = 640, .y = 480 }));
    try testing.expect(position().eql(.{ .x = 640, .y = 480 }));
}

test position {
    platform.mock.reset();

    try testing.expect(position().eql(.zero));
}

test scroll_down {
    platform.mock.reset();

    try testing.expect(scroll_down(3));

    const entry = record.last() orelse return error.EntryMissing;

    try testing.expectEqual(@as(i32, -3), entry.amount);
}

test scroll_left {
    platform.mock.reset();

    try testing.expect(scroll_left(2));

    const entry = record.last() orelse return error.EntryMissing;

    try testing.expectEqual(@as(i32, -2), entry.x);
}

test scroll_right {
    platform.mock.reset();

    try testing.expect(scroll_right(2));

    const entry = record.last() orelse return error.EntryMissing;

    try testing.expectEqual(@as(i32, 2), entry.x);
}

test scroll_up {
    platform.mock.reset();

    try testing.expect(scroll_up(3));

    const entry = record.last() orelse return error.EntryMissing;

    try testing.expectEqual(@as(i32, 3), entry.amount);
}
