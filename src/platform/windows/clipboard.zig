const std = @import("std");

const keycode = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");
const simulate_key = @import("simulate/key.zig");
const win32 = @import("win32.zig");

const assert = std.debug.assert;
const Keycode = keycode.Keycode;
const clipboard = @This();
pub const text_bytes_max: u32 = 4096;
const select_count_max: u32 = 1024;
const settle_ms: u32 = 20;

pub const Error = error{
    ClipboardUnavailable,
    CountInvalid,
    SendFailed,
    TextInvalid,
    TextTooLong,
    TransferFailed,
};

const ReadError = Error || error{ClipboardEmpty};

fn utf16_to_utf8(source: []const u16, target: []u8) Error![]const u8 {
    assert(source.len <= text_bytes_max);
    assert(target.len > 0);

    var iterator = std.unicode.Utf16LeIterator.init(source);
    var written: usize = 0;

    while (iterator.nextCodepoint() catch return Error.TextInvalid) |codepoint| {
        var encoded: [4]u8 = undefined;

        const size = std.unicode.utf8Encode(codepoint, &encoded) catch return Error.TextInvalid;

        if (written + size > target.len) {
            break;
        }

        @memcpy(target[written .. written + size], encoded[0..size]);

        written += size;
    }

    assert(written <= target.len);

    return target[0..written];
}

pub fn set(text: []const u8) Error!void {
    assert(text.len > 0);

    if (text.len > text_bytes_max) {
        return Error.TextTooLong;
    }

    const units = std.unicode.calcUtf16LeLen(text) catch return Error.TextInvalid;

    assert(units >= 1);
    assert(units <= text.len);

    if (win32.OpenClipboard(null) == 0) {
        return Error.ClipboardUnavailable;
    }

    defer _ = win32.CloseClipboard();

    if (win32.EmptyClipboard() == 0) {
        return Error.TransferFailed;
    }

    const handle = win32.GlobalAlloc(win32.GMEM_MOVEABLE, (units + 1) * 2);

    if (handle == 0) {
        return Error.TransferFailed;
    }

    errdefer _ = win32.GlobalFree(handle);

    const ptr = win32.GlobalLock(handle) orelse return Error.ClipboardUnavailable;
    const dest: [*]u16 = @ptrCast(@alignCast(ptr));

    const written = std.unicode.utf8ToUtf16Le(dest[0..units], text) catch {
        _ = win32.GlobalUnlock(handle);

        return Error.TextInvalid;
    };

    assert(written == units);

    dest[units] = 0;

    _ = win32.GlobalUnlock(handle);

    const result = win32.SetClipboardData(
        @backingInt(win32.CF_UNICODETEXT),
        @ptrFromInt(@as(usize, @intCast(handle))),
    );

    if (result == null) {
        return Error.TransferFailed;
    }

    errdefer comptime unreachable;

    assert(result != null);
}

fn get(buffer: []u8) ReadError![]const u8 {
    assert(buffer.len > 0);

    if (win32.OpenClipboard(null) == 0) {
        return Error.ClipboardUnavailable;
    }

    defer _ = win32.CloseClipboard();

    const handle = win32.GetClipboardData(@backingInt(win32.CF_UNICODETEXT));

    if (handle == null) {
        return ReadError.ClipboardEmpty;
    }

    const handle_int: isize = @bitCast(@intFromPtr(handle));
    const ptr = win32.GlobalLock(handle_int) orelse return Error.ClipboardUnavailable;
    defer _ = win32.GlobalUnlock(handle_int);

    const source: [*]const u16 = @ptrCast(@alignCast(ptr));

    var units: usize = 0;

    while (units < text_bytes_max) : (units += 1) {
        if (source[units] == 0) break;
    }

    assert(units <= text_bytes_max);

    return utf16_to_utf8(source[0..units], buffer);
}

pub fn paste() bool {
    return simulate_key.combination(&modifier.Set.from(.{ .ctrl = true }), .v);
}

fn select_left(count: u32) Error!void {
    assert(count > 0);

    if (count > select_count_max) {
        return Error.CountInvalid;
    }

    if (!simulate_key.key_down(Keycode.shift_left)) {
        return Error.SendFailed;
    }

    var i: u32 = 0;

    while (i < count) : (i += 1) {
        if (!simulate_key.press(Keycode.arrow_left)) {
            _ = simulate_key.key_up(Keycode.shift_left);

            return Error.SendFailed;
        }
    }

    if (!simulate_key.key_up(Keycode.shift_left)) {
        return Error.SendFailed;
    }
}

pub fn replace(select_count: u32, text: []const u8) Error!void {
    assert(select_count > 0);
    assert(text.len > 0);

    try select_left(select_count);

    win32.Sleep(settle_ms);

    try set(text);

    win32.Sleep(settle_ms);

    if (!paste()) {
        return Error.SendFailed;
    }
}

const testing = std.testing;

test "the clipboard rejects oversized text" {
    var text: [clipboard.text_bytes_max + 1]u8 = undefined;

    @memset(&text, 'a');

    const refused = clipboard.set(&text);

    try testing.expectError(clipboard.Error.TextTooLong, refused);
}

test "the clipboard rejects text that is not valid utf8" {
    const text = [_]u8{ 0xFF, 0xFE, 0xFD };
    const refused = clipboard.set(&text);

    try testing.expectError(clipboard.Error.TextInvalid, refused);
}

test "selecting left rejects an oversized count" {
    const count = clipboard.select_count_max + 1;

    try testing.expectError(clipboard.Error.CountInvalid, clipboard.select_left(count));
}

test "replacing rejects an oversized count" {
    const count = clipboard.select_count_max + 1;

    try testing.expectError(clipboard.Error.CountInvalid, clipboard.replace(count, "a"));
}

test "clipboard limits" {
    try testing.expect(clipboard.text_bytes_max >= 1);
    try testing.expect(clipboard.select_count_max >= 1);
}

test {
    testing.refAllDecls(clipboard);
}

test "setting the clipboard hands the buffer over exactly once" {
    var buffer: [64]u8 = undefined;
    var round: u8 = 0;

    while (round < 16) : (round += 1) {
        set("nimble") catch |err| switch (err) {
            Error.ClipboardUnavailable => return,
            else => return err,
        };

        const text = try get(&buffer);

        try testing.expectEqualStrings("nimble", text);
    }

    try testing.expectEqual(@as(u8, 16), round);
}

test "rejected text frees the clipboard buffer" {
    var round: u8 = 0;

    while (round < 16) : (round += 1) {
        const result = set(&[_]u8{ 0xC3, 0x28 });

        if (result) |_| {
            return error.TextInvalidAccepted;
        } else |err| switch (err) {
            Error.ClipboardUnavailable => return,
            Error.TextInvalid => {},
            else => return err,
        }
    }

    try testing.expectEqual(@as(u8, 16), round);
}
