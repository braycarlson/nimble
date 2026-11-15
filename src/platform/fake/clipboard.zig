const std = @import("std");

const assert = std.debug.assert;

storage: [text_bytes_max]u8 = @splat(0),
length: u16 = 0,

const Clipboard = @This();

pub const Error = error{
    CountInvalid,
    SendFailed,
    TextTooLong,
};

pub const ReadError = error{ClipboardEmpty};

pub const select_count_max: u32 = 1024;
pub const text_bytes_max: u16 = 4096;

comptime {
    assert(text_bytes_max > 0);
    assert(select_count_max > 0);
}

pub fn set(clipboard: *Clipboard, text: []const u8) Error!void {
    if (text.len > text_bytes_max) {
        return Error.TextTooLong;
    }

    assert(text.len <= text_bytes_max);

    @memcpy(clipboard.storage[0..text.len], text);

    clipboard.length = @intCast(text.len);

    assert(clipboard.length == text.len);
}

pub fn get(clipboard: *const Clipboard, buffer: []u8) ReadError![]const u8 {
    assert(buffer.len > 0);

    if (clipboard.length == 0) {
        return error.ClipboardEmpty;
    }

    const size = @min(buffer.len, clipboard.length);

    @memcpy(buffer[0..size], clipboard.storage[0..size]);

    assert(size <= clipboard.length);

    return buffer[0..size];
}

const testing = std.testing;

test "the fake clipboard holds what was set" {
    var clipboard: Clipboard = .{};
    var buffer: [16]u8 = undefined;

    try testing.expectError(error.ClipboardEmpty, clipboard.get(&buffer));
    try clipboard.set("nimble");
    try testing.expectEqualStrings("nimble", try clipboard.get(&buffer));

    const long: [text_bytes_max + 1]u8 = @splat('n');
    const refused = clipboard.set(&long);

    try testing.expectError(error.TextTooLong, refused);
}
