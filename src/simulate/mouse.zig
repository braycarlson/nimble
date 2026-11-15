const std = @import("std");

const mouse_event = @import("../event.zig").mouse;
const platform = @import("../platform.zig");
const position_module = @import("../position.zig");

const assert = std.debug.assert;

const Button = mouse_event.MouseEvent.Button;
const Position = position_module.Position;

pub fn button_down(comptime Platform: type, backend: *Platform, button: Button) bool {
    assert(button.is_valid());

    return backend.mouse_button_down(button);
}

pub fn button_up(comptime Platform: type, backend: *Platform, button: Button) bool {
    assert(button.is_valid());

    return backend.mouse_button_up(button);
}

pub fn click(comptime Platform: type, backend: *Platform, button: Button) bool {
    assert(button.is_valid());

    return backend.mouse_click(button);
}

pub fn move_relative(comptime Platform: type, backend: *Platform, offset: Position) bool {
    return backend.mouse_move_relative(offset);
}

pub fn move_to(comptime Platform: type, backend: *Platform, target: Position) bool {
    return backend.mouse_move_to(target);
}

pub fn position(comptime Platform: type, backend: *Platform) Position {
    return backend.mouse_get_position();
}

pub fn scroll_down(comptime Platform: type, backend: *Platform, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= Platform.scroll_clicks_max);

    return backend.mouse_scroll_down(clicks);
}

pub fn scroll_left(comptime Platform: type, backend: *Platform, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= Platform.scroll_clicks_max);

    return backend.mouse_scroll_left(clicks);
}

pub fn scroll_right(comptime Platform: type, backend: *Platform, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= Platform.scroll_clicks_max);

    return backend.mouse_scroll_right(clicks);
}

pub fn scroll_up(comptime Platform: type, backend: *Platform, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= Platform.scroll_clicks_max);

    return backend.mouse_scroll_up(clicks);
}

const testing = std.testing;

const Fake = platform.Fake;

fn fake_create() !*Fake {
    const fake = try testing.allocator.create(Fake);
    errdefer testing.allocator.destroy(fake);

    try fake.init(.{});

    return fake;
}

fn fake_destroy(fake: *Fake) void {
    fake.deinit();

    testing.allocator.destroy(fake);
}

test button_down {
    const fake = try fake_create();
    defer fake_destroy(fake);

    try testing.expect(button_down(Fake, fake, .left));
    try testing.expectEqual(@as(u16, 1), fake.record.count_of(.mouse_down));
}

test button_up {
    const fake = try fake_create();
    defer fake_destroy(fake);

    try testing.expect(button_up(Fake, fake, .right));
    try testing.expectEqual(@as(u16, 1), fake.record.count_of(.mouse_up));
}

test click {
    const fake = try fake_create();
    defer fake_destroy(fake);

    try testing.expect(click(Fake, fake, .middle));
    try testing.expectEqual(@as(u16, 1), fake.record.count_of(.mouse_down));
    try testing.expectEqual(@as(u16, 1), fake.record.count_of(.mouse_up));
}

test move_relative {
    const fake = try fake_create();
    defer fake_destroy(fake);

    try testing.expect(move_to(Fake, fake, .{ .x = 100, .y = 100 }));
    try testing.expect(move_relative(Fake, fake, .{ .x = 20, .y = -10 }));
    try testing.expect(position(Fake, fake).eql(.{ .x = 120, .y = 90 }));
}

test move_to {
    const fake = try fake_create();
    defer fake_destroy(fake);

    try testing.expect(move_to(Fake, fake, .{ .x = 640, .y = 480 }));
    try testing.expect(position(Fake, fake).eql(.{ .x = 640, .y = 480 }));
}

test position {
    const fake = try fake_create();
    defer fake_destroy(fake);

    try testing.expect(position(Fake, fake).eql(.zero));
}

test scroll_down {
    const fake = try fake_create();
    defer fake_destroy(fake);

    try testing.expect(scroll_down(Fake, fake, 3));

    const entry = fake.record.last() orelse return error.EntryMissing;

    try testing.expectEqual(@as(i32, -3), entry.amount);
}

test scroll_left {
    const fake = try fake_create();
    defer fake_destroy(fake);

    try testing.expect(scroll_left(Fake, fake, 2));

    const entry = fake.record.last() orelse return error.EntryMissing;

    try testing.expectEqual(@as(i32, -2), entry.x);
}

test scroll_right {
    const fake = try fake_create();
    defer fake_destroy(fake);

    try testing.expect(scroll_right(Fake, fake, 2));

    const entry = fake.record.last() orelse return error.EntryMissing;

    try testing.expectEqual(@as(i32, 2), entry.x);
}

test scroll_up {
    const fake = try fake_create();
    defer fake_destroy(fake);

    try testing.expect(scroll_up(Fake, fake, 3));

    const entry = fake.record.last() orelse return error.EntryMissing;

    try testing.expectEqual(@as(i32, 3), entry.amount);
}
