const std = @import("std");

const keycode = @import("../../../keycode.zig");
const modifier = @import("../../../modifier.zig");
const simulate_key = @import("key.zig");
const time = @import("../time.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const text_max: u16 = 256;
pub const delay_ms_default: u32 = 1;

pub const Error = error{
    SendFailed,
    TextTooLong,
};

const shift_set = modifier.Set.from(.{ .shift = true });

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

    if (!simulate_key.is_open()) {
        return Error.SendFailed;
    }

    var sent: u32 = 0;

    for (text) |character| {
        const stroke = resolve(character) orelse continue;

        const ok = if (stroke.shift)
            simulate_key.combination(&shift_set, stroke.code)
        else
            simulate_key.press(stroke.code);

        if (!ok) {
            return Error.SendFailed;
        }

        sent += 1;

        time.sleep_ms(delay_ms);
    }

    assert(sent <= text.len);

    return sent;
}

const Stroke = struct {
    code: Keycode,
    shift: bool,
};

pub fn resolve(character: u8) ?Stroke {
    if (character >= 'a' and character <= 'z') {
        return Stroke{ .code = Keycode.from_char(character).?, .shift = false };
    }

    if (character >= 'A' and character <= 'Z') {
        return Stroke{ .code = Keycode.from_char(character).?, .shift = true };
    }

    if (character >= '0' and character <= '9') {
        return Stroke{ .code = Keycode.from_char(character).?, .shift = false };
    }

    return switch (character) {
        ' ' => .{ .code = .space, .shift = false },
        '\n', '\r' => .{ .code = .enter, .shift = false },
        '\t' => .{ .code = .tab, .shift = false },
        ';' => .{ .code = .semicolon, .shift = false },
        ':' => .{ .code = .semicolon, .shift = true },
        '=' => .{ .code = .equal, .shift = false },
        '+' => .{ .code = .equal, .shift = true },
        ',' => .{ .code = .comma, .shift = false },
        '<' => .{ .code = .comma, .shift = true },
        '-' => .{ .code = .minus, .shift = false },
        '_' => .{ .code = .minus, .shift = true },
        '.' => .{ .code = .period, .shift = false },
        '>' => .{ .code = .period, .shift = true },
        '/' => .{ .code = .slash, .shift = false },
        '?' => .{ .code = .slash, .shift = true },
        '`' => .{ .code = .backtick, .shift = false },
        '~' => .{ .code = .backtick, .shift = true },
        '[' => .{ .code = .bracket_left, .shift = false },
        '{' => .{ .code = .bracket_left, .shift = true },
        '\\' => .{ .code = .backslash, .shift = false },
        '|' => .{ .code = .backslash, .shift = true },
        ']' => .{ .code = .bracket_right, .shift = false },
        '}' => .{ .code = .bracket_right, .shift = true },
        '\'' => .{ .code = .quote, .shift = false },
        '"' => .{ .code = .quote, .shift = true },
        else => null,
    };
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

const testing = std.testing;

test "lowercase letters resolve without shift" {
    const stroke = resolve('a') orelse return error.MissingStroke;

    try testing.expectEqual(Keycode.a, stroke.code);
    try testing.expect(!stroke.shift);
}

test "uppercase letters resolve with shift" {
    const stroke = resolve('Z') orelse return error.MissingStroke;

    try testing.expectEqual(Keycode.z, stroke.code);
    try testing.expect(stroke.shift);
}

test "digits resolve without shift" {
    const stroke = resolve('7') orelse return error.MissingStroke;

    try testing.expectEqual(Keycode.digit_7, stroke.code);
    try testing.expect(!stroke.shift);
}

test "shifted punctuation shares a keycode with its unshifted twin" {
    const plain = resolve(';') orelse return error.MissingStroke;
    const shifted = resolve(':') orelse return error.MissingStroke;

    try testing.expectEqual(plain.code, shifted.code);
    try testing.expect(!plain.shift);
    try testing.expect(shifted.shift);
}

test "unmappable characters resolve to nothing" {
    try testing.expect(resolve(0x01) == null);
    try testing.expect(resolve(0x7F) == null);
}

test "sending without an open device fails cleanly" {
    try testing.expect(!simulate_key.is_open());
    try testing.expectError(Error.SendFailed, send("hello"));
}

test "over-long text is rejected before any synthesis" {
    const long = "x" ** (text_max + 1);

    try testing.expectError(Error.TextTooLong, send(long));
}
