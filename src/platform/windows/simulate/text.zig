const std = @import("std");

const keycode = @import("../../../keycode.zig");
const message = @import("message.zig");
const win32 = @import("../win32.zig");
const window = @import("../window.zig");

const assert = std.debug.assert;
const Keycode = keycode.Keycode;

pub const text_max: u32 = 4096;
pub const delay_ms_max: u32 = 1000;

pub const Error = error{
    InvalidDelay,
    InvalidText,
    SendFailed,
    TextTooLong,
};

fn post_codepoint(hwnd: win32.HWND, codepoint: u21) bool {
    assert(codepoint <= 0x10FFFF);

    if (codepoint <= 0xFFFF) {
        assert(codepoint < 0xD800 or codepoint > 0xDFFF);

        return message.post_char(hwnd, @intCast(codepoint));
    }

    const adjusted: u20 = @intCast(codepoint - 0x10000);

    const unit_high: u16 = 0xD800 + @as(u16, @intCast(adjusted >> 10));
    const unit_low: u16 = 0xDC00 + @as(u16, @intCast(adjusted & 0x3FF));

    const ok_high = message.post_char(hwnd, unit_high);
    const ok_low = message.post_char(hwnd, unit_low);

    return ok_high and ok_low;
}

fn send_codepoints(text: []const u8, delay_ms: u32) Error!u32 {
    if (delay_ms > delay_ms_max) {
        return Error.InvalidDelay;
    }

    assert(delay_ms <= delay_ms_max);

    if (text.len == 0) {
        return 0;
    }

    if (text.len > text_max) {
        return Error.TextTooLong;
    }

    const view = std.unicode.Utf8View.init(text) catch return Error.InvalidText;

    const hwnd = window.get_focused() orelse return Error.SendFailed;

    var sent: u32 = 0;
    var iterator = view.iterator();

    while (iterator.nextCodepoint()) |codepoint| {
        assert(sent <= text_max);

        if (codepoint == '\r') {
            continue;
        }

        const ok = if (codepoint == '\n')
            message.post_key_press(hwnd, Keycode.enter)
        else
            post_codepoint(hwnd, codepoint);

        if (!ok) {
            return Error.SendFailed;
        }

        sent += 1;

        assert(sent <= text_max);

        if (delay_ms > 0) {
            win32.Sleep(delay_ms);
        }
    }

    return sent;
}

pub fn send(text: []const u8) Error!u32 {
    return send_codepoints(text, 0);
}

pub fn send_with_delay(text: []const u8, delay_ms: u32) Error!u32 {
    if (delay_ms > delay_ms_max) {
        return Error.InvalidDelay;
    }

    assert(delay_ms <= delay_ms_max);

    return send_codepoints(text, delay_ms);
}

pub const Typer = struct {
    pub fn init() Typer {
        return Typer{};
    }

    pub fn send(_: Typer, text: []const u8) Error!u32 {
        const sent = try send_codepoints(text, 0);

        assert(sent <= text_max);
        assert(sent <= text.len);

        return sent;
    }

    pub fn send_with_delay(_: Typer, text: []const u8, delay_ms: u32) Error!u32 {
        if (delay_ms > delay_ms_max) {
            return Error.InvalidDelay;
        }

        const sent = try send_codepoints(text, delay_ms);

        assert(sent <= text_max);
        assert(sent <= text.len);

        return sent;
    }
};

const testing = std.testing;

test "sending empty text sends nothing" {
    const sent = try send("");

    try testing.expectEqual(@as(u32, 0), sent);
}

test "sending oversized text is rejected" {
    var buffer: [text_max + 1]u8 = undefined;

    @memset(&buffer, 'a');

    try testing.expectError(Error.TextTooLong, send(&buffer));
}

test "sending text that is not valid utf8 is rejected" {
    const bad = [_]u8{ 0xC0, 0x20 };

    try testing.expectError(Error.InvalidText, send(&bad));
}

test "sending with an oversized delay is rejected" {
    const delay_ms = delay_ms_max + 1;

    try testing.expectError(Error.InvalidDelay, send_with_delay("a", delay_ms));
}

test "the typer applies the same validation" {
    const typer = Typer.init();
    const delay_ms = delay_ms_max + 1;

    try testing.expectError(Error.InvalidDelay, typer.send_with_delay("a", delay_ms));

    const sent = try typer.send("");

    try testing.expectEqual(@as(u32, 0), sent);
}

test "text limits" {
    try testing.expect(text_max >= 1);
    try testing.expect(delay_ms_max >= 1);
}

test {
    testing.refAllDecls(@This());
    testing.refAllDecls(Typer);
}
