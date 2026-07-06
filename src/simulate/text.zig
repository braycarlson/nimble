const std = @import("std");

const win32 = @import("win32").everything;

const keycode = @import("../keycode.zig");
const message = @import("message.zig");
const window = @import("../window.zig");

pub const text_max: u32 = 4096;
pub const delay_ms_max: u32 = 1000;

pub const Error = error{
    InvalidDelay,
    InvalidText,
    SendFailed,
    TextTooLong,
};

fn post_codepoint(hwnd: win32.HWND, codepoint: u21) bool {
    std.debug.assert(codepoint <= 0x10FFFF);

    if (codepoint <= 0xFFFF) {
        std.debug.assert(codepoint < 0xD800 or codepoint > 0xDFFF);

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

    std.debug.assert(delay_ms <= delay_ms_max);

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
        std.debug.assert(sent <= text_max);

        if (codepoint == '\r') {
            continue;
        }

        const ok = if (codepoint == '\n')
            message.post_key_press(hwnd, keycode.@"return")
        else
            post_codepoint(hwnd, codepoint);

        if (!ok) {
            return Error.SendFailed;
        }

        sent += 1;

        std.debug.assert(sent <= text_max);

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

    std.debug.assert(delay_ms <= delay_ms_max);

    return send_codepoints(text, delay_ms);
}

pub const Typer = struct {
    pub fn init() Typer {
        return Typer{};
    }

    pub fn send(_: Typer, text: []const u8) Error!u32 {
        const sent = try send_codepoints(text, 0);

        std.debug.assert(sent <= text_max);
        std.debug.assert(sent <= text.len);

        return sent;
    }

    pub fn send_with_delay(_: Typer, text: []const u8, delay_ms: u32) Error!u32 {
        if (delay_ms > delay_ms_max) {
            return Error.InvalidDelay;
        }

        const sent = try send_codepoints(text, delay_ms);

        std.debug.assert(sent <= text_max);
        std.debug.assert(sent <= text.len);

        return sent;
    }
};
