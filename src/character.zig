const std = @import("std");

const key_event = @import("event/key.zig");
const keycode = @import("keycode.zig");

const assert = std.debug.assert;
const Keycode = keycode.Keycode;
const Key = key_event.Key;

pub fn is_whitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

pub fn from_keycode(code: Keycode) u8 {
    if (code.is_alpha()) {
        return std.ascii.toLower(code.to_char().?);
    }

    if (code.is_digit()) {
        return code.to_char().?;
    }

    return switch (code) {
        .space => ' ',
        .enter => '\r',
        .semicolon => ';',
        .slash => '/',
        .backtick => '`',
        .bracket_left => '[',
        .backslash => '\\',
        .bracket_right => ']',
        .quote => '\'',
        .equal => '=',
        .comma => ',',
        .minus => '-',
        .period => '.',
        else => 0,
    };
}

pub fn from_key(key: *const Key) ?u8 {
    assert(key.is_valid());

    const value = key.value;

    if (value.is_alpha()) {
        const character = value.to_char().?;

        return if (key.is_shift_down()) character else std.ascii.toLower(character);
    }

    if (value.is_digit()) {
        const character = value.to_char().?;

        return if (key.is_shift_down()) shifted_digit(character) else character;
    }

    return switch (value) {
        .semicolon => if (key.is_shift_down()) ':' else ';',
        .slash => if (key.is_shift_down()) '?' else '/',
        .backtick => if (key.is_shift_down()) '~' else '`',
        .bracket_left => if (key.is_shift_down()) '{' else '[',
        .backslash => if (key.is_shift_down()) '|' else '\\',
        .bracket_right => if (key.is_shift_down()) '}' else ']',
        .quote => if (key.is_shift_down()) '"' else '\'',
        .equal => if (key.is_shift_down()) '+' else '=',
        .comma => if (key.is_shift_down()) '<' else ',',
        .minus => if (key.is_shift_down()) '_' else '-',
        .period => if (key.is_shift_down()) '>' else '.',
        else => null,
    };
}

pub fn shifted_digit(value: u8) u8 {
    return switch (value) {
        '1' => '!',
        '2' => '@',
        '3' => '#',
        '4' => '$',
        '5' => '%',
        '6' => '^',
        '7' => '&',
        '8' => '*',
        '9' => '(',
        '0' => ')',
        else => value,
    };
}

const modifier = @import("modifier.zig");

const testing = std.testing;

fn make_key(value: Keycode, shift: bool) Key {
    return Key{
        .value = value,
        .down = true,
        .injected = false,
        .modifiers = modifier.Set.from(.{ .shift = shift }),
    };
}

test "a space counts as whitespace" {
    try testing.expect(is_whitespace(' '));
}

test "a tab counts as whitespace" {
    try testing.expect(is_whitespace('\t'));
}

test "a newline counts as whitespace" {
    try testing.expect(is_whitespace('\n'));
}

test "a carriage return counts as whitespace" {
    try testing.expect(is_whitespace('\r'));
}

test "an ordinary character is not whitespace" {
    try testing.expect(!is_whitespace('a'));
    try testing.expect(!is_whitespace('A'));
    try testing.expect(!is_whitespace('0'));
    try testing.expect(!is_whitespace('!'));
}

test "shifting the digit one gives its symbol" {
    try testing.expectEqual(@as(u8, '!'), shifted_digit('1'));
}

test "shifting the digit two gives its symbol" {
    try testing.expectEqual(@as(u8, '@'), shifted_digit('2'));
}

test "shifting the digit three gives its symbol" {
    try testing.expectEqual(@as(u8, '#'), shifted_digit('3'));
}

test "shifting the digit four gives its symbol" {
    try testing.expectEqual(@as(u8, '$'), shifted_digit('4'));
}

test "shifting the digit five gives its symbol" {
    try testing.expectEqual(@as(u8, '%'), shifted_digit('5'));
}

test "shifting the digit six gives its symbol" {
    try testing.expectEqual(@as(u8, '^'), shifted_digit('6'));
}

test "shifting the digit seven gives its symbol" {
    try testing.expectEqual(@as(u8, '&'), shifted_digit('7'));
}

test "shifting the digit eight gives its symbol" {
    try testing.expectEqual(@as(u8, '*'), shifted_digit('8'));
}

test "shifting the digit nine gives its symbol" {
    try testing.expectEqual(@as(u8, '('), shifted_digit('9'));
}

test "shifting the digit zero gives its symbol" {
    try testing.expectEqual(@as(u8, ')'), shifted_digit('0'));
}

test "shifting a non-digit gives nothing" {
    try testing.expectEqual(@as(u8, 'A'), shifted_digit('A'));
}

test "an unshifted letter key gives its lowercase character" {
    const key = make_key(.a, false);

    try testing.expectEqual(@as(?u8, 'a'), from_key(&key));
}

test "a shifted letter key gives its uppercase character" {
    const key = make_key(.a, true);

    try testing.expectEqual(@as(?u8, 'A'), from_key(&key));
}

test "every letter key gives a character" {
    const key_a = make_key(.a, false);
    const key_z = make_key(.z, false);

    try testing.expectEqual(@as(?u8, 'a'), from_key(&key_a));
    try testing.expectEqual(@as(?u8, 'z'), from_key(&key_z));
}

test "an unshifted digit key gives its digit" {
    const key = make_key(.digit_5, false);

    try testing.expectEqual(@as(?u8, '5'), from_key(&key));
}

test "a shifted digit key gives its symbol" {
    const key = make_key(.digit_5, true);

    try testing.expectEqual(@as(?u8, '%'), from_key(&key));
}

test "an unshifted semicolon key gives a semicolon" {
    const key = make_key(.semicolon, false);

    try testing.expectEqual(@as(?u8, ';'), from_key(&key));
}

test "a shifted semicolon key gives a colon" {
    const key = make_key(.semicolon, true);

    try testing.expectEqual(@as(?u8, ':'), from_key(&key));
}

test "an unshifted slash key gives a slash" {
    const key = make_key(.slash, false);

    try testing.expectEqual(@as(?u8, '/'), from_key(&key));
}

test "a shifted slash key gives a question mark" {
    const key = make_key(.slash, true);

    try testing.expectEqual(@as(?u8, '?'), from_key(&key));
}

test "an unshifted backtick key gives a backtick" {
    const key = make_key(.backtick, false);

    try testing.expectEqual(@as(?u8, '`'), from_key(&key));
}

test "a shifted backtick key gives a tilde" {
    const key = make_key(.backtick, true);

    try testing.expectEqual(@as(?u8, '~'), from_key(&key));
}

test "an unshifted left bracket key gives a bracket" {
    const key = make_key(.bracket_left, false);

    try testing.expectEqual(@as(?u8, '['), from_key(&key));
}

test "a shifted left bracket key gives a brace" {
    const key = make_key(.bracket_left, true);

    try testing.expectEqual(@as(?u8, '{'), from_key(&key));
}

test "an unshifted backslash key gives a backslash" {
    const key = make_key(.backslash, false);

    try testing.expectEqual(@as(?u8, '\\'), from_key(&key));
}

test "a shifted backslash key gives a pipe" {
    const key = make_key(.backslash, true);

    try testing.expectEqual(@as(?u8, '|'), from_key(&key));
}

test "an unshifted right bracket key gives a closing bracket" {
    const key = make_key(.bracket_right, false);

    try testing.expectEqual(@as(?u8, ']'), from_key(&key));
}

test "a shifted right bracket key gives a closing brace" {
    const key = make_key(.bracket_right, true);

    try testing.expectEqual(@as(?u8, '}'), from_key(&key));
}

test "an unshifted quote key gives an apostrophe" {
    const key = make_key(.quote, false);

    try testing.expectEqual(@as(?u8, '\''), from_key(&key));
}

test "a shifted quote key gives a double quote" {
    const key = make_key(.quote, true);

    try testing.expectEqual(@as(?u8, '"'), from_key(&key));
}

test "an unshifted equal key gives an equals sign" {
    const key = make_key(.equal, false);

    try testing.expectEqual(@as(?u8, '='), from_key(&key));
}

test "a shifted equal key gives a plus" {
    const key = make_key(.equal, true);

    try testing.expectEqual(@as(?u8, '+'), from_key(&key));
}

test "an unshifted comma key gives a comma" {
    const key = make_key(.comma, false);

    try testing.expectEqual(@as(?u8, ','), from_key(&key));
}

test "a shifted comma key gives a less than sign" {
    const key = make_key(.comma, true);

    try testing.expectEqual(@as(?u8, '<'), from_key(&key));
}

test "an unshifted minus key gives a minus" {
    const key = make_key(.minus, false);

    try testing.expectEqual(@as(?u8, '-'), from_key(&key));
}

test "a shifted minus key gives an underscore" {
    const key = make_key(.minus, true);

    try testing.expectEqual(@as(?u8, '_'), from_key(&key));
}

test "an unshifted period key gives a period" {
    const key = make_key(.period, false);

    try testing.expectEqual(@as(?u8, '.'), from_key(&key));
}

test "a shifted period key gives a greater than sign" {
    const key = make_key(.period, true);

    try testing.expectEqual(@as(?u8, '>'), from_key(&key));
}

test "a key with no character gives nothing" {
    const key = make_key(.enter, false);

    try testing.expect(from_key(&key) == null);
}

test "a space key gives nothing" {
    const key = make_key(.space, false);

    try testing.expect(from_key(&key) == null);
}

test "a modifier key gives nothing" {
    const key = make_key(.control_left, false);

    try testing.expect(from_key(&key) == null);
}
