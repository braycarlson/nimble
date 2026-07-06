const std = @import("std");
const input = @import("input");

const clipboard = input.clipboard;

const testing = std.testing;

test "clipboard.set rejects oversize text" {
    var text: [clipboard.text_max + 1]u8 = undefined;

    @memset(&text, 'a');

    try testing.expectError(clipboard.Error.TextTooLong, clipboard.set(&text));
}

test "clipboard.set rejects invalid utf8" {
    const text = [_]u8{ 0xFF, 0xFE, 0xFD };

    try testing.expectError(clipboard.Error.InvalidText, clipboard.set(&text));
}

test "clipboard.select_left rejects oversize count" {
    const count = clipboard.select_count_max + 1;

    try testing.expectError(clipboard.Error.InvalidCount, clipboard.select_left(count));
}

test "clipboard.select_right rejects oversize count" {
    const count = clipboard.select_count_max + 1;

    try testing.expectError(clipboard.Error.InvalidCount, clipboard.select_right(count));
}

test "clipboard.replace rejects oversize count" {
    const count = clipboard.select_count_max + 1;

    try testing.expectError(clipboard.Error.InvalidCount, clipboard.replace(count, "a"));
}

test "clipboard.Clipboard wraps validation" {
    const wrapper = clipboard.Clipboard.init();
    const count = clipboard.select_count_max + 1;

    var text: [clipboard.text_max + 1]u8 = undefined;

    @memset(&text, 'a');

    try testing.expectError(clipboard.Error.TextTooLong, wrapper.set(&text));
    try testing.expectError(clipboard.Error.InvalidCount, wrapper.replace(count, "a"));
}

test "clipboard limits" {
    try testing.expect(clipboard.text_max >= 1);
    try testing.expect(clipboard.select_count_max >= 1);
}

test {
    testing.refAllDecls(clipboard);
    testing.refAllDecls(clipboard.Clipboard);
}
