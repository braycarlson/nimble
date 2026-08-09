const std = @import("std");

const record = @import("../record.zig");
const time = @import("../time.zig");

const assert = std.debug.assert;

pub const text_max: u16 = 256;
pub const delay_ms_default: u32 = 1;

pub const Error = error{
    SendFailed,
    TextTooLong,
};

comptime {
    assert(text_max > 0);
}

pub fn send(text: []const u8) Error!u32 {
    return send_with_delay(text, delay_ms_default);
}

pub fn send_with_delay(text: []const u8, delay_ms: u32) Error!u32 {
    if (text.len > text_max) {
        return Error.TextTooLong;
    }

    assert(text.len <= text_max);

    record.push_text(.text_send, text);

    time.advance(delay_ms);

    return @intCast(text.len);
}

pub const Typer = struct {
    pub fn init() Typer {
        return Typer{};
    }

    pub fn send(_: Typer, text: []const u8) Error!u32 {
        return @import("text.zig").send(text);
    }

    pub fn send_with_delay(_: Typer, text: []const u8, delay_ms: u32) Error!u32 {
        return @import("text.zig").send_with_delay(text, delay_ms);
    }
};
