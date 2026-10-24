const std = @import("std");

const keycode = @import("../../../keycode.zig");
const modifier = @import("../../../modifier.zig");
const simulate_key = @import("key.zig");
const time = @import("../time.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const text_max: u16 = 256;
const delay_ms_default: u32 = 1;

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

    if (!simulate_key.release_modifiers()) {
        return Error.SendFailed;
    }

    var sent: u32 = 0;
    var previous: u8 = 0;

    for (text) |character| {
        defer previous = character;

        const stroke = resolve_after(previous, character) orelse continue;

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

fn resolve_after(previous: u8, character: u8) ?Stroke {
    if (character == '\n') {
        if (previous == '\r') return null;
    }

    return resolve(character);
}

pub fn resolve(character: u8) ?Stroke {
    return switch (character) {
        'a'...'z' => .{ .code = Keycode.from_char(character).?, .shift = false },
        'A'...'Z' => .{ .code = Keycode.from_char(character).?, .shift = true },
        '0'...'9' => .{ .code = Keycode.from_char(character).?, .shift = false },
        ' ' => .{ .code = .space, .shift = false },
        '\n', '\r' => .{ .code = .enter, .shift = false },
        '\t' => .{ .code = .tab, .shift = false },
        '!' => .{ .code = .digit_1, .shift = true },
        '@' => .{ .code = .digit_2, .shift = true },
        '#' => .{ .code = .digit_3, .shift = true },
        '$' => .{ .code = .digit_4, .shift = true },
        '%' => .{ .code = .digit_5, .shift = true },
        '^' => .{ .code = .digit_6, .shift = true },
        '&' => .{ .code = .digit_7, .shift = true },
        '*' => .{ .code = .digit_8, .shift = true },
        '(' => .{ .code = .digit_9, .shift = true },
        ')' => .{ .code = .digit_0, .shift = true },
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

const testing = std.testing;

const character_mod = @import("../../../character.zig");
const key_event = @import("../../../event/key.zig");

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

test "each printable ascii character resolves to a stroke that types it back" {
    var character: u8 = '!';

    while (character <= '~') : (character += 1) {
        const stroke = resolve(character) orelse return error.MissingStroke;

        const key = key_event.Key{
            .value = stroke.code,
            .down = true,
            .modifiers = modifier.Set.from(.{ .shift = stroke.shift }),
        };

        try testing.expectEqual(@as(?u8, character), character_mod.from_key(&key));
    }
}

test "each line ending resolves to one enter" {
    const lone_feed = resolve_after('a', '\n') orelse return error.MissingStroke;
    const lone_return = resolve_after('a', '\r') orelse return error.MissingStroke;

    try testing.expectEqual(Keycode.enter, lone_feed.code);
    try testing.expectEqual(Keycode.enter, lone_return.code);
    try testing.expect(resolve_after('\r', '\n') == null);
    try testing.expect(resolve_after('\n', '\n') != null);
}

test "sending without an open device fails cleanly" {
    try testing.expect(!simulate_key.is_open());
    try testing.expectError(Error.SendFailed, send("hello"));
}

test "over-long text is rejected before any synthesis" {
    const long: [text_max + 1]u8 = @splat('x');

    try testing.expectError(Error.TextTooLong, send(&long));
}
