const std = @import("std");
const input = @import("input");

const keycode = input.keycode;

const testing = std.testing;

test "keycode.is_valid" {
    try testing.expect(keycode.is_valid(keycode.value_min));
    try testing.expect(keycode.is_valid(keycode.value_max));
    try testing.expect(keycode.is_valid('A'));
    try testing.expect(keycode.is_valid('Z'));
    try testing.expect(keycode.is_valid('0'));
    try testing.expect(keycode.is_valid('9'));
    try testing.expect(keycode.is_valid(keycode.space));
    try testing.expect(keycode.is_valid(keycode.@"return"));
}

test "keycode.is_valid boundary" {
    try testing.expect(keycode.is_valid(0x01));
    try testing.expect(keycode.is_valid(0xFE));
    try testing.expect(!keycode.is_valid(0x00));
    try testing.expect(!keycode.is_valid(0xFF));
}

test "keycode.is_alpha" {
    try testing.expect(keycode.is_alpha('A'));
    try testing.expect(keycode.is_alpha('Z'));
    try testing.expect(keycode.is_alpha('M'));
    try testing.expect(!keycode.is_alpha('0'));
    try testing.expect(!keycode.is_alpha('9'));
    try testing.expect(!keycode.is_alpha(keycode.space));
    try testing.expect(!keycode.is_alpha(keycode.@"return"));
}

test "keycode.is_digit" {
    try testing.expect(keycode.is_digit('0'));
    try testing.expect(keycode.is_digit('9'));
    try testing.expect(keycode.is_digit('5'));
    try testing.expect(!keycode.is_digit('A'));
    try testing.expect(!keycode.is_digit('Z'));
    try testing.expect(!keycode.is_digit(keycode.space));
}

test "keycode.is_modifier ctrl" {
    try testing.expect(keycode.is_modifier(keycode.control));
    try testing.expect(keycode.is_modifier(keycode.lctrl));
    try testing.expect(keycode.is_modifier(keycode.rctrl));
}

test "keycode.is_modifier alt" {
    try testing.expect(keycode.is_modifier(keycode.menu));
    try testing.expect(keycode.is_modifier(keycode.lmenu));
    try testing.expect(keycode.is_modifier(keycode.rmenu));
}

test "keycode.is_modifier shift" {
    try testing.expect(keycode.is_modifier(keycode.shift));
    try testing.expect(keycode.is_modifier(keycode.lshift));
    try testing.expect(keycode.is_modifier(keycode.rshift));
}

test "keycode.is_modifier win" {
    try testing.expect(keycode.is_modifier(keycode.lwin));
    try testing.expect(keycode.is_modifier(keycode.rwin));
}

test "keycode.is_modifier false" {
    try testing.expect(!keycode.is_modifier('A'));
    try testing.expect(!keycode.is_modifier(keycode.space));
    try testing.expect(!keycode.is_modifier(keycode.@"return"));
    try testing.expect(!keycode.is_modifier(keycode.escape));
}

test "keycode.from_char alpha" {
    try testing.expectEqual(@as(?u8, 'A'), keycode.from_char('A'));
    try testing.expectEqual(@as(?u8, 'A'), keycode.from_char('a'));
    try testing.expectEqual(@as(?u8, 'Z'), keycode.from_char('Z'));
    try testing.expectEqual(@as(?u8, 'Z'), keycode.from_char('z'));
}

test "keycode.from_char digit" {
    try testing.expectEqual(@as(?u8, '0'), keycode.from_char('0'));
    try testing.expectEqual(@as(?u8, '9'), keycode.from_char('9'));
    try testing.expectEqual(@as(?u8, '5'), keycode.from_char('5'));
}

test "keycode.from_char invalid" {
    try testing.expect(keycode.from_char('!') == null);
    try testing.expect(keycode.from_char('@') == null);
    try testing.expect(keycode.from_char(' ') == null);
}

test "keycode.from_name special keys" {
    try testing.expectEqual(@as(?u8, keycode.back), keycode.from_name("backspace"));
    try testing.expectEqual(@as(?u8, keycode.tab), keycode.from_name("tab"));
    try testing.expectEqual(@as(?u8, keycode.@"return"), keycode.from_name("enter"));
    try testing.expectEqual(@as(?u8, keycode.@"return"), keycode.from_name("return"));
    try testing.expectEqual(@as(?u8, keycode.escape), keycode.from_name("escape"));
    try testing.expectEqual(@as(?u8, keycode.escape), keycode.from_name("esc"));
    try testing.expectEqual(@as(?u8, keycode.space), keycode.from_name("space"));
}

test "keycode.from_name navigation keys" {
    try testing.expectEqual(@as(?u8, keycode.left), keycode.from_name("left"));
    try testing.expectEqual(@as(?u8, keycode.right), keycode.from_name("right"));
    try testing.expectEqual(@as(?u8, keycode.up), keycode.from_name("up"));
    try testing.expectEqual(@as(?u8, keycode.down), keycode.from_name("down"));
    try testing.expectEqual(@as(?u8, keycode.home), keycode.from_name("home"));
    try testing.expectEqual(@as(?u8, keycode.end), keycode.from_name("end"));
    try testing.expectEqual(@as(?u8, keycode.prior), keycode.from_name("pageup"));
    try testing.expectEqual(@as(?u8, keycode.next), keycode.from_name("pagedown"));
}

test "keycode.from_name function keys" {
    try testing.expectEqual(@as(?u8, keycode.f1), keycode.from_name("f1"));
    try testing.expectEqual(@as(?u8, keycode.f12), keycode.from_name("f12"));
}

test "keycode.from_name editing keys" {
    try testing.expectEqual(@as(?u8, keycode.insert), keycode.from_name("insert"));
    try testing.expectEqual(@as(?u8, keycode.delete), keycode.from_name("delete"));
    try testing.expectEqual(@as(?u8, keycode.delete), keycode.from_name("del"));
}

test "keycode.from_name invalid" {
    try testing.expect(keycode.from_name("invalid") == null);
    try testing.expect(keycode.from_name("SPACE") == null);
}

test "keycode.from_string single char" {
    try testing.expectEqual(@as(?u8, 'A'), keycode.from_string("A"));
    try testing.expectEqual(@as(?u8, 'A'), keycode.from_string("a"));
    try testing.expectEqual(@as(?u8, '5'), keycode.from_string("5"));
}

test "keycode.from_string named" {
    try testing.expectEqual(@as(?u8, keycode.space), keycode.from_string("space"));
    try testing.expectEqual(@as(?u8, keycode.@"return"), keycode.from_string("enter"));
}

test "keycode.from_string empty" {
    try testing.expect(keycode.from_string("") == null);
}

test "keycode.to_name special keys" {
    try testing.expectEqualStrings("Backspace", keycode.to_name(keycode.back).?);
    try testing.expectEqualStrings("Tab", keycode.to_name(keycode.tab).?);
    try testing.expectEqualStrings("Enter", keycode.to_name(keycode.@"return").?);
    try testing.expectEqualStrings("Escape", keycode.to_name(keycode.escape).?);
    try testing.expectEqualStrings("Space", keycode.to_name(keycode.space).?);
}

test "keycode.to_name modifiers" {
    try testing.expectEqualStrings("Shift", keycode.to_name(keycode.shift).?);
    try testing.expectEqualStrings("Shift", keycode.to_name(keycode.lshift).?);
    try testing.expectEqualStrings("Shift", keycode.to_name(keycode.rshift).?);
    try testing.expectEqualStrings("Ctrl", keycode.to_name(keycode.control).?);
    try testing.expectEqualStrings("Alt", keycode.to_name(keycode.menu).?);
    try testing.expectEqualStrings("Win", keycode.to_name(keycode.lwin).?);
}

test "keycode.to_name navigation" {
    try testing.expectEqualStrings("Left", keycode.to_name(keycode.left).?);
    try testing.expectEqualStrings("Right", keycode.to_name(keycode.right).?);
    try testing.expectEqualStrings("Up", keycode.to_name(keycode.up).?);
    try testing.expectEqualStrings("Down", keycode.to_name(keycode.down).?);
}

test "keycode.to_name null for alpha" {
    try testing.expect(keycode.to_name('A') == null);
    try testing.expect(keycode.to_name('Z') == null);
}

test "keycode.to_string excludes alpha and digit" {
    try testing.expect(keycode.to_string('A') == null);
    try testing.expect(keycode.to_string('0') == null);
    try testing.expectEqualStrings("Space", keycode.to_string(keycode.space).?);
}

test "keycode constants" {
    try testing.expectEqual(@as(u8, 0x01), keycode.value_min);
    try testing.expectEqual(@as(u8, 0xFE), keycode.value_max);
    try testing.expectEqual(@as(u8, 0xFF), keycode.value_dummy);
    try testing.expectEqual(@as(u8, 0x08), keycode.back);
    try testing.expectEqual(@as(u8, 0x09), keycode.tab);
    try testing.expectEqual(@as(u8, 0x0D), keycode.@"return");
    try testing.expectEqual(@as(u8, 0x20), keycode.space);
    try testing.expectEqual(@as(u8, 0x1B), keycode.escape);
}

test "keycode modifier pairs" {
    try testing.expectEqual(@as(u8, 0xA0), keycode.lshift);
    try testing.expectEqual(@as(u8, 0xA1), keycode.rshift);
    try testing.expectEqual(@as(u8, 0xA2), keycode.lctrl);
    try testing.expectEqual(@as(u8, 0xA3), keycode.rctrl);
    try testing.expectEqual(@as(u8, 0xA4), keycode.lmenu);
    try testing.expectEqual(@as(u8, 0xA5), keycode.rmenu);
    try testing.expectEqual(@as(u8, 0x5B), keycode.lwin);
    try testing.expectEqual(@as(u8, 0x5C), keycode.rwin);
}

test "keycode function keys" {
    try testing.expectEqual(@as(u8, 0x70), keycode.f1);
    try testing.expectEqual(@as(u8, 0x7B), keycode.f12);
}

test "keycode oem keys" {
    try testing.expectEqual(@as(u8, 0xBA), keycode.oem_1);
    try testing.expectEqual(@as(u8, 0xBB), keycode.oem_plus);
    try testing.expectEqual(@as(u8, 0xBC), keycode.oem_comma);
    try testing.expectEqual(@as(u8, 0xBD), keycode.oem_minus);
    try testing.expectEqual(@as(u8, 0xBE), keycode.oem_period);
}
