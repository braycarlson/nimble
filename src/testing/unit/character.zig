const std = @import("std");
const input = @import("input");

const character = input.character;
const keycode = input.keycode;
const modifier = input.modifier;
const event = input.event;

const Key = event.Key;

const testing = std.testing;

fn make_key(value: u8, shift: bool) Key {
    return Key{
        .value = value,
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = modifier.Set.from(.{ .shift = shift }),
    };
}

test "character.is_whitespace space" {
    try testing.expect(character.is_whitespace(' '));
}

test "character.is_whitespace tab" {
    try testing.expect(character.is_whitespace('\t'));
}

test "character.is_whitespace newline" {
    try testing.expect(character.is_whitespace('\n'));
}

test "character.is_whitespace carriage return" {
    try testing.expect(character.is_whitespace('\r'));
}

test "character.is_whitespace non-whitespace" {
    try testing.expect(!character.is_whitespace('a'));
    try testing.expect(!character.is_whitespace('A'));
    try testing.expect(!character.is_whitespace('0'));
    try testing.expect(!character.is_whitespace('!'));
}

test "character.shifted_digit 1" {
    try testing.expectEqual(@as(u8, '!'), character.shifted_digit('1'));
}

test "character.shifted_digit 2" {
    try testing.expectEqual(@as(u8, '@'), character.shifted_digit('2'));
}

test "character.shifted_digit 3" {
    try testing.expectEqual(@as(u8, '#'), character.shifted_digit('3'));
}

test "character.shifted_digit 4" {
    try testing.expectEqual(@as(u8, '$'), character.shifted_digit('4'));
}

test "character.shifted_digit 5" {
    try testing.expectEqual(@as(u8, '%'), character.shifted_digit('5'));
}

test "character.shifted_digit 6" {
    try testing.expectEqual(@as(u8, '^'), character.shifted_digit('6'));
}

test "character.shifted_digit 7" {
    try testing.expectEqual(@as(u8, '&'), character.shifted_digit('7'));
}

test "character.shifted_digit 8" {
    try testing.expectEqual(@as(u8, '*'), character.shifted_digit('8'));
}

test "character.shifted_digit 9" {
    try testing.expectEqual(@as(u8, '('), character.shifted_digit('9'));
}

test "character.shifted_digit 0" {
    try testing.expectEqual(@as(u8, ')'), character.shifted_digit('0'));
}

test "character.shifted_digit non-digit" {
    try testing.expectEqual(@as(u8, 'A'), character.shifted_digit('A'));
}

test "character.from_key alpha lowercase" {
    const key = make_key('A', false);
    try testing.expectEqual(@as(?u8, 'a'), character.from_key(&key));
}

test "character.from_key alpha uppercase" {
    const key = make_key('A', true);
    try testing.expectEqual(@as(?u8, 'A'), character.from_key(&key));
}

test "character.from_key alpha range" {
    const key_a = make_key('A', false);
    const key_z = make_key('Z', false);
    try testing.expectEqual(@as(?u8, 'a'), character.from_key(&key_a));
    try testing.expectEqual(@as(?u8, 'z'), character.from_key(&key_z));
}

test "character.from_key digit no shift" {
    const key = make_key('5', false);
    try testing.expectEqual(@as(?u8, '5'), character.from_key(&key));
}

test "character.from_key digit with shift" {
    const key = make_key('5', true);
    try testing.expectEqual(@as(?u8, '%'), character.from_key(&key));
}

test "character.from_key oem_1 semicolon" {
    const key = make_key(keycode.oem_1, false);
    try testing.expectEqual(@as(?u8, ';'), character.from_key(&key));
}

test "character.from_key oem_1 colon" {
    const key = make_key(keycode.oem_1, true);
    try testing.expectEqual(@as(?u8, ':'), character.from_key(&key));
}

test "character.from_key oem_2 slash" {
    const key = make_key(keycode.oem_2, false);
    try testing.expectEqual(@as(?u8, '/'), character.from_key(&key));
}

test "character.from_key oem_2 question" {
    const key = make_key(keycode.oem_2, true);
    try testing.expectEqual(@as(?u8, '?'), character.from_key(&key));
}

test "character.from_key oem_3 backtick" {
    const key = make_key(keycode.oem_3, false);
    try testing.expectEqual(@as(?u8, '`'), character.from_key(&key));
}

test "character.from_key oem_3 tilde" {
    const key = make_key(keycode.oem_3, true);
    try testing.expectEqual(@as(?u8, '~'), character.from_key(&key));
}

test "character.from_key oem_4 bracket" {
    const key = make_key(keycode.oem_4, false);
    try testing.expectEqual(@as(?u8, '['), character.from_key(&key));
}

test "character.from_key oem_4 brace" {
    const key = make_key(keycode.oem_4, true);
    try testing.expectEqual(@as(?u8, '{'), character.from_key(&key));
}

test "character.from_key oem_5 backslash" {
    const key = make_key(keycode.oem_5, false);
    try testing.expectEqual(@as(?u8, '\\'), character.from_key(&key));
}

test "character.from_key oem_5 pipe" {
    const key = make_key(keycode.oem_5, true);
    try testing.expectEqual(@as(?u8, '|'), character.from_key(&key));
}

test "character.from_key oem_6 close bracket" {
    const key = make_key(keycode.oem_6, false);
    try testing.expectEqual(@as(?u8, ']'), character.from_key(&key));
}

test "character.from_key oem_6 close brace" {
    const key = make_key(keycode.oem_6, true);
    try testing.expectEqual(@as(?u8, '}'), character.from_key(&key));
}

test "character.from_key oem_7 quote" {
    const key = make_key(keycode.oem_7, false);
    try testing.expectEqual(@as(?u8, '\''), character.from_key(&key));
}

test "character.from_key oem_7 double quote" {
    const key = make_key(keycode.oem_7, true);
    try testing.expectEqual(@as(?u8, '"'), character.from_key(&key));
}

test "character.from_key oem_plus equals" {
    const key = make_key(keycode.oem_plus, false);
    try testing.expectEqual(@as(?u8, '='), character.from_key(&key));
}

test "character.from_key oem_plus plus" {
    const key = make_key(keycode.oem_plus, true);
    try testing.expectEqual(@as(?u8, '+'), character.from_key(&key));
}

test "character.from_key oem_comma" {
    const key = make_key(keycode.oem_comma, false);
    try testing.expectEqual(@as(?u8, ','), character.from_key(&key));
}

test "character.from_key oem_comma less than" {
    const key = make_key(keycode.oem_comma, true);
    try testing.expectEqual(@as(?u8, '<'), character.from_key(&key));
}

test "character.from_key oem_minus" {
    const key = make_key(keycode.oem_minus, false);
    try testing.expectEqual(@as(?u8, '-'), character.from_key(&key));
}

test "character.from_key oem_minus underscore" {
    const key = make_key(keycode.oem_minus, true);
    try testing.expectEqual(@as(?u8, '_'), character.from_key(&key));
}

test "character.from_key oem_period" {
    const key = make_key(keycode.oem_period, false);
    try testing.expectEqual(@as(?u8, '.'), character.from_key(&key));
}

test "character.from_key oem_period greater than" {
    const key = make_key(keycode.oem_period, true);
    try testing.expectEqual(@as(?u8, '>'), character.from_key(&key));
}

test "character.from_key unknown returns null" {
    const key = make_key(keycode.@"return", false);
    try testing.expect(character.from_key(&key) == null);
}

test "character.from_key space returns null" {
    const key = make_key(keycode.space, false);
    try testing.expect(character.from_key(&key) == null);
}

test "character.from_key modifier returns null" {
    const key = make_key(keycode.lctrl, false);
    try testing.expect(character.from_key(&key) == null);
}
