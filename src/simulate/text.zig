const std = @import("std");

const w32 = @import("win32").everything;

const keycode = @import("../keycode.zig");
const message = @import("message.zig");
const window = @import("../window.zig");

pub const text_max: u32 = 4096;
pub const delay_max_ms: u32 = 1000;

pub const Error = error{
    TextTooLong,
    SendFailed,
};

fn _send(text: []const u8, delay_ms: u32) Error!u32 {
    std.debug.assert(delay_ms <= delay_max_ms);

    if (text.len == 0) {
        return 0;
    }

    if (text.len > text_max) {
        return Error.TextTooLong;
    }

    const hwnd = window.get_focused() orelse return Error.SendFailed;

    var sent: u32 = 0;

    for (text) |char| {
        if (char == '\r') {
            continue;
        }

        const ok = if (char == '\n')
            message.post_key_press(hwnd, keycode.@"return")
        else
            message.post_char(hwnd, char);

        if (!ok) {
            return Error.SendFailed;
        }

        sent += 1;

        std.debug.assert(sent <= text_max);

        if (delay_ms > 0) {
            w32.Sleep(delay_ms);
        }
    }

    return sent;
}

pub fn send(text: []const u8) Error!u32 {
    return _send(text, 0);
}

pub fn send_with_delay(text: []const u8, delay_ms: u32) Error!u32 {
    std.debug.assert(delay_ms <= delay_max_ms);
    return _send(text, delay_ms);
}
