const std = @import("std");
const input = @import("input");

const mouse_event = input.event.mouse;

const Kind = mouse_event.Kind;
const Mouse = mouse_event.Mouse;

const testing = std.testing;

test "Kind.is_valid left_down" {
    try testing.expect(Kind.left_down.is_valid());
}

test "Kind.is_valid left_up" {
    try testing.expect(Kind.left_up.is_valid());
}

test "Kind.is_valid right_down" {
    try testing.expect(Kind.right_down.is_valid());
}

test "Kind.is_valid right_up" {
    try testing.expect(Kind.right_up.is_valid());
}

test "Kind.is_valid middle_down" {
    try testing.expect(Kind.middle_down.is_valid());
}

test "Kind.is_valid middle_up" {
    try testing.expect(Kind.middle_up.is_valid());
}

test "Kind.is_valid x_down" {
    try testing.expect(Kind.x_down.is_valid());
}

test "Kind.is_valid x_up" {
    try testing.expect(Kind.x_up.is_valid());
}

test "Kind.is_valid wheel" {
    try testing.expect(Kind.wheel.is_valid());
}

test "Kind.is_valid move" {
    try testing.expect(Kind.move.is_valid());
}

test "Kind.is_valid other" {
    try testing.expect(Kind.other.is_valid());
}

test "Kind enum values" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(Kind.left_down));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(Kind.left_up));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(Kind.right_down));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(Kind.right_up));
    try testing.expectEqual(@as(u8, 4), @intFromEnum(Kind.middle_down));
    try testing.expectEqual(@as(u8, 5), @intFromEnum(Kind.middle_up));
    try testing.expectEqual(@as(u8, 6), @intFromEnum(Kind.x_down));
    try testing.expectEqual(@as(u8, 7), @intFromEnum(Kind.x_up));
    try testing.expectEqual(@as(u8, 8), @intFromEnum(Kind.wheel));
    try testing.expectEqual(@as(u8, 9), @intFromEnum(Kind.move));
    try testing.expectEqual(@as(u8, 10), @intFromEnum(Kind.other));
}

test "Kind.is_down left_down" {
    try testing.expect(Kind.left_down.is_down());
}

test "Kind.is_down left_up" {
    try testing.expect(!Kind.left_up.is_down());
}

test "Kind.is_down right_down" {
    try testing.expect(Kind.right_down.is_down());
}

test "Kind.is_down right_up" {
    try testing.expect(!Kind.right_up.is_down());
}

test "Kind.is_down middle_down" {
    try testing.expect(Kind.middle_down.is_down());
}

test "Kind.is_down middle_up" {
    try testing.expect(!Kind.middle_up.is_down());
}

test "Kind.is_down x_down" {
    try testing.expect(Kind.x_down.is_down());
}

test "Kind.is_down x_up" {
    try testing.expect(!Kind.x_up.is_down());
}

test "Kind.is_down wheel" {
    try testing.expect(!Kind.wheel.is_down());
}

test "Kind.is_down move" {
    try testing.expect(!Kind.move.is_down());
}

test "Kind.is_up left_up" {
    try testing.expect(Kind.left_up.is_up());
}

test "Kind.is_up left_down" {
    try testing.expect(!Kind.left_down.is_up());
}

test "Kind.is_up right_up" {
    try testing.expect(Kind.right_up.is_up());
}

test "Kind.is_up right_down" {
    try testing.expect(!Kind.right_down.is_up());
}

test "Kind.is_up middle_up" {
    try testing.expect(Kind.middle_up.is_up());
}

test "Kind.is_up middle_down" {
    try testing.expect(!Kind.middle_down.is_up());
}

test "Kind.is_up x_up" {
    try testing.expect(Kind.x_up.is_up());
}

test "Kind.is_up x_down" {
    try testing.expect(!Kind.x_down.is_up());
}

test "Kind.is_button button events" {
    try testing.expect(Kind.left_down.is_button());
    try testing.expect(Kind.left_up.is_button());
    try testing.expect(Kind.right_down.is_button());
    try testing.expect(Kind.right_up.is_button());
    try testing.expect(Kind.middle_down.is_button());
    try testing.expect(Kind.middle_up.is_button());
    try testing.expect(Kind.x_down.is_button());
    try testing.expect(Kind.x_up.is_button());
}

test "Kind.is_button non-button events" {
    try testing.expect(!Kind.wheel.is_button());
    try testing.expect(!Kind.move.is_button());
    try testing.expect(!Kind.other.is_button());
}

test "mouse constants" {
    try testing.expectEqual(@as(u8, 11), mouse_event.kind_count);
    try testing.expectEqual(@as(u8, 10), mouse_event.kind_max);
}
