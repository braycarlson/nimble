const std = @import("std");

const win32 = @import("win32").everything;

const simulate_key = @import("simulate/key.zig");
const keycode = @import("keycode.zig");
const modifier = @import("modifier.zig");

const clipboard = @This();

pub const text_max: u32 = 4096;
pub const select_count_max: u32 = 1024;

const settle_ms: u32 = 20;

pub const Error = error{
    AllocFailed,
    ClearFailed,
    EmptyClipboard,
    GetFailed,
    InvalidCount,
    InvalidText,
    LockFailed,
    OpenFailed,
    SendFailed,
    SetFailed,
    TextTooLong,
};

fn utf16_to_utf8(source: []const u16, target: []u8) Error![]const u8 {
    std.debug.assert(source.len <= text_max);
    std.debug.assert(target.len > 0);

    var iterator = std.unicode.Utf16LeIterator.init(source);
    var written: usize = 0;

    while (iterator.nextCodepoint() catch return Error.InvalidText) |codepoint| {
        var encoded: [4]u8 = undefined;

        const size = std.unicode.utf8Encode(codepoint, &encoded) catch return Error.InvalidText;

        if (written + size > target.len) {
            break;
        }

        @memcpy(target[written .. written + size], encoded[0..size]);

        written += size;
    }

    std.debug.assert(written <= target.len);

    return target[0..written];
}

pub fn set(text: []const u8) Error!void {
    std.debug.assert(text.len > 0);

    if (text.len > text_max) {
        return Error.TextTooLong;
    }

    const units = std.unicode.calcUtf16LeLen(text) catch return Error.InvalidText;

    std.debug.assert(units >= 1);
    std.debug.assert(units <= text.len);

    if (win32.OpenClipboard(null) == 0) {
        return Error.OpenFailed;
    }

    defer _ = win32.CloseClipboard();

    if (win32.EmptyClipboard() == 0) {
        return Error.ClearFailed;
    }

    const handle = win32.GlobalAlloc(win32.GMEM_MOVEABLE, (units + 1) * 2);

    if (handle == 0) {
        return Error.AllocFailed;
    }

    errdefer _ = win32.GlobalFree(handle);

    const ptr = win32.GlobalLock(handle) orelse return Error.LockFailed;
    const dest: [*]u16 = @ptrCast(@alignCast(ptr));

    const written = std.unicode.utf8ToUtf16Le(dest[0..units], text) catch {
        _ = win32.GlobalUnlock(handle);

        return Error.InvalidText;
    };

    std.debug.assert(written == units);

    dest[units] = 0;

    _ = win32.GlobalUnlock(handle);

    const result = win32.SetClipboardData(
        @intFromEnum(win32.CF_UNICODETEXT),
        @ptrFromInt(@as(usize, @intCast(handle))),
    );

    if (result == null) {
        return Error.SetFailed;
    }
}

pub fn get(buffer: []u8) Error![]const u8 {
    std.debug.assert(buffer.len > 0);

    if (win32.OpenClipboard(null) == 0) {
        return Error.OpenFailed;
    }

    defer _ = win32.CloseClipboard();

    const handle = win32.GetClipboardData(@intFromEnum(win32.CF_UNICODETEXT));

    if (handle == null) {
        return Error.EmptyClipboard;
    }

    const handle_int: isize = @bitCast(@intFromPtr(handle));

    const ptr = win32.GlobalLock(handle_int) orelse return Error.LockFailed;
    defer _ = win32.GlobalUnlock(handle_int);

    const source: [*]const u16 = @ptrCast(@alignCast(ptr));

    var units: usize = 0;

    while (units < text_max and source[units] != 0) : (units += 1) {}

    std.debug.assert(units <= text_max);

    return utf16_to_utf8(source[0..units], buffer);
}

pub fn clear() Error!void {
    if (win32.OpenClipboard(null) == 0) {
        return Error.OpenFailed;
    }

    defer _ = win32.CloseClipboard();

    if (win32.EmptyClipboard() == 0) {
        return Error.ClearFailed;
    }

    std.debug.assert(win32.CountClipboardFormats() == 0);
}

pub fn paste() bool {
    return simulate_key.combination(&modifier.Set.from(.{ .ctrl = true }), 'V');
}

pub fn copy() bool {
    return simulate_key.combination(&modifier.Set.from(.{ .ctrl = true }), 'C');
}

pub fn cut() bool {
    return simulate_key.combination(&modifier.Set.from(.{ .ctrl = true }), 'X');
}

pub fn select_all() bool {
    return simulate_key.combination(&modifier.Set.from(.{ .ctrl = true }), 'A');
}

pub fn select_left(count: u32) Error!void {
    std.debug.assert(count > 0);

    if (count > select_count_max) {
        return Error.InvalidCount;
    }

    if (!simulate_key.key_down(keycode.lshift)) {
        return Error.SendFailed;
    }

    var i: u32 = 0;

    while (i < count) : (i += 1) {
        if (!simulate_key.press(keycode.left)) {
            _ = simulate_key.key_up(keycode.lshift);

            return Error.SendFailed;
        }
    }

    if (!simulate_key.key_up(keycode.lshift)) {
        return Error.SendFailed;
    }
}

pub fn select_right(count: u32) Error!void {
    std.debug.assert(count > 0);

    if (count > select_count_max) {
        return Error.InvalidCount;
    }

    if (!simulate_key.key_down(keycode.lshift)) {
        return Error.SendFailed;
    }

    var i: u32 = 0;

    while (i < count) : (i += 1) {
        if (!simulate_key.press(keycode.right)) {
            _ = simulate_key.key_up(keycode.lshift);

            return Error.SendFailed;
        }
    }

    if (!simulate_key.key_up(keycode.lshift)) {
        return Error.SendFailed;
    }
}

pub fn replace(select_count: u32, text: []const u8) Error!void {
    std.debug.assert(select_count > 0);
    std.debug.assert(text.len > 0);

    try select_left(select_count);

    win32.Sleep(settle_ms);

    try set(text);

    win32.Sleep(settle_ms);

    if (!paste()) {
        return Error.SendFailed;
    }
}

pub const Clipboard = struct {
    pub fn init() Clipboard {
        return Clipboard{};
    }

    pub fn get(_: Clipboard, buffer: []u8) Error![]const u8 {
        std.debug.assert(buffer.len > 0);

        const result = try clipboard.get(buffer);

        std.debug.assert(result.len <= buffer.len);

        return result;
    }

    pub fn set(_: Clipboard, text: []const u8) Error!void {
        std.debug.assert(text.len > 0);

        return clipboard.set(text);
    }

    pub fn clear(_: Clipboard) Error!void {
        return clipboard.clear();
    }

    pub fn paste(_: Clipboard) bool {
        return clipboard.paste();
    }

    pub fn copy(_: Clipboard) bool {
        return clipboard.copy();
    }

    pub fn cut(_: Clipboard) bool {
        return clipboard.cut();
    }

    pub fn select_all(_: Clipboard) bool {
        return clipboard.select_all();
    }

    pub fn replace(_: Clipboard, select_count: u32, text: []const u8) Error!void {
        std.debug.assert(select_count > 0);
        std.debug.assert(text.len > 0);

        return clipboard.replace(select_count, text);
    }
};
