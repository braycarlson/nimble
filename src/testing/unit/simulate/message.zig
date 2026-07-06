const std = @import("std");
const input = @import("input");

const message = input.simulate.message;
const keycode = input.keycode;

const testing = std.testing;

test "message.make_lparam basic" {
    const lparam = message.make_lparam(0x1E, false, false);

    try testing.expectEqual(@as(isize, 0x001E0001), lparam);
}

test "message.make_lparam extended" {
    const lparam = message.make_lparam(0, true, false);

    try testing.expectEqual(@as(isize, 0x01000001), lparam);
}

test "message.make_lparam key_up" {
    const lparam = message.make_lparam(0xFF, false, true);

    try testing.expectEqual(@as(isize, 0xC0FF0001), lparam);
}

test "message.is_extended_key" {
    try testing.expect(message.is_extended_key(keycode.left));
    try testing.expect(message.is_extended_key(keycode.rctrl));
    try testing.expect(!message.is_extended_key('A'));
}

test "message.send_timeout_ms bounded" {
    try testing.expect(message.send_timeout_ms >= 1);
    try testing.expect(message.send_timeout_ms <= 10000);
}

test {
    testing.refAllDecls(message);
}
