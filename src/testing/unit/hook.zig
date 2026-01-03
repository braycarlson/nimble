const std = @import("std");
const input = @import("input");

const hook_mod = input.hook;

const Kind = hook_mod.Kind;

const testing = std.testing;

test "Kind.is_valid keyboard" {
    try testing.expect(Kind.keyboard.is_valid());
}

test "Kind.is_valid mouse" {
    try testing.expect(Kind.mouse.is_valid());
}

test "Kind enum values" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(Kind.keyboard));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(Kind.mouse));
}

test "hook constants" {
    try testing.expectEqual(@as(u8, 1), hook_mod.kind_max);
    try testing.expectEqual(@as(u8, 2), hook_mod.kind_count);
}
