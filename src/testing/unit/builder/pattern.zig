const std = @import("std");
const input = @import("input");

const builder = input.builder;
const keycode = input.keycode;
const modifier = input.modifier;

const parse = builder.parse;
const ParsedPattern = builder.ParsedPattern;

const testing = std.testing;

test "pattern.parse single letter" {
    const result = comptime parse("A");

    try testing.expectEqual(@as(u8, 'A'), result.key);
    try testing.expect(result.modifiers.none());
}

test "pattern.parse lowercase letter" {
    const result = comptime parse("a");

    try testing.expectEqual(@as(u8, 'A'), result.key);
    try testing.expect(result.modifiers.none());
}

test "pattern.parse ctrl modifier" {
    const result = comptime parse("Ctrl+A");

    try testing.expectEqual(@as(u8, 'A'), result.key);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(!result.modifiers.alt());
    try testing.expect(!result.modifiers.shift());
    try testing.expect(!result.modifiers.win());
}

test "pattern.parse ctrl lowercase" {
    const result = comptime parse("ctrl+A");

    try testing.expectEqual(@as(u8, 'A'), result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "pattern.parse alt modifier" {
    const result = comptime parse("Alt+B");

    try testing.expectEqual(@as(u8, 'B'), result.key);
    try testing.expect(result.modifiers.alt());
    try testing.expect(!result.modifiers.ctrl());
}

test "pattern.parse alt lowercase" {
    const result = comptime parse("alt+B");

    try testing.expectEqual(@as(u8, 'B'), result.key);
    try testing.expect(result.modifiers.alt());
}

test "pattern.parse shift modifier" {
    const result = comptime parse("Shift+C");

    try testing.expectEqual(@as(u8, 'C'), result.key);
    try testing.expect(result.modifiers.shift());
    try testing.expect(!result.modifiers.ctrl());
}

test "pattern.parse shift lowercase" {
    const result = comptime parse("shift+C");

    try testing.expectEqual(@as(u8, 'C'), result.key);
    try testing.expect(result.modifiers.shift());
}

test "pattern.parse win modifier" {
    const result = comptime parse("Win+D");

    try testing.expectEqual(@as(u8, 'D'), result.key);
    try testing.expect(result.modifiers.win());
    try testing.expect(!result.modifiers.ctrl());
}

test "pattern.parse win lowercase" {
    const result = comptime parse("win+D");

    try testing.expectEqual(@as(u8, 'D'), result.key);
    try testing.expect(result.modifiers.win());
}

test "pattern.parse ctrl+alt" {
    const result = comptime parse("Ctrl+Alt+E");

    try testing.expectEqual(@as(u8, 'E'), result.key);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(result.modifiers.alt());
    try testing.expect(!result.modifiers.shift());
    try testing.expect(!result.modifiers.win());
}

test "pattern.parse ctrl+shift" {
    const result = comptime parse("Ctrl+Shift+F");

    try testing.expectEqual(@as(u8, 'F'), result.key);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(result.modifiers.shift());
}

test "pattern.parse alt+shift" {
    const result = comptime parse("Alt+Shift+G");

    try testing.expectEqual(@as(u8, 'G'), result.key);
    try testing.expect(result.modifiers.alt());
    try testing.expect(result.modifiers.shift());
}

test "pattern.parse ctrl+alt+shift" {
    const result = comptime parse("Ctrl+Alt+Shift+H");

    try testing.expectEqual(@as(u8, 'H'), result.key);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(result.modifiers.alt());
    try testing.expect(result.modifiers.shift());
    try testing.expect(!result.modifiers.win());
}

test "pattern.parse all modifiers" {
    const result = comptime parse("Ctrl+Alt+Shift+Win+I");

    try testing.expectEqual(@as(u8, 'I'), result.key);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(result.modifiers.alt());
    try testing.expect(result.modifiers.shift());
    try testing.expect(result.modifiers.win());
}

test "pattern.parse space" {
    const result = comptime parse("Ctrl+Space");

    try testing.expectEqual(keycode.space, result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "pattern.parse enter" {
    const result = comptime parse("Ctrl+Enter");

    try testing.expectEqual(keycode.@"return", result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "pattern.parse return" {
    const result = comptime parse("Ctrl+Return");

    try testing.expectEqual(keycode.@"return", result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "pattern.parse tab" {
    const result = comptime parse("Alt+Tab");

    try testing.expectEqual(keycode.tab, result.key);
    try testing.expect(result.modifiers.alt());
}

test "pattern.parse escape" {
    const result = comptime parse("Escape");

    try testing.expectEqual(keycode.escape, result.key);
    try testing.expect(result.modifiers.none());
}

test "pattern.parse esc" {
    const result = comptime parse("Esc");

    try testing.expectEqual(keycode.escape, result.key);
}

test "pattern.parse backspace" {
    const result = comptime parse("Ctrl+Backspace");

    try testing.expectEqual(keycode.back, result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "pattern.parse delete" {
    const result = comptime parse("Shift+Delete");

    try testing.expectEqual(keycode.delete, result.key);
    try testing.expect(result.modifiers.shift());
}

test "pattern.parse del" {
    const result = comptime parse("Shift+Del");

    try testing.expectEqual(keycode.delete, result.key);
}

test "pattern.parse insert" {
    const result = comptime parse("Insert");

    try testing.expectEqual(keycode.insert, result.key);
}

test "pattern.parse home" {
    const result = comptime parse("Ctrl+Home");

    try testing.expectEqual(keycode.home, result.key);
}

test "pattern.parse end" {
    const result = comptime parse("Ctrl+End");

    try testing.expectEqual(keycode.end, result.key);
}

test "pattern.parse pageup" {
    const result = comptime parse("PageUp");

    try testing.expectEqual(keycode.prior, result.key);
}

test "pattern.parse pagedown" {
    const result = comptime parse("PageDown");

    try testing.expectEqual(keycode.next, result.key);
}

test "pattern.parse arrow keys" {
    const left = comptime parse("Left");
    const right = comptime parse("Right");
    const up = comptime parse("Up");
    const down = comptime parse("Down");

    try testing.expectEqual(keycode.left, left.key);
    try testing.expectEqual(keycode.right, right.key);
    try testing.expectEqual(keycode.up, up.key);
    try testing.expectEqual(keycode.down, down.key);
}

test "pattern.parse function keys" {
    const f1 = comptime parse("F1");
    const f12 = comptime parse("F12");

    try testing.expectEqual(keycode.f1, f1.key);
    try testing.expectEqual(keycode.f12, f12.key);
}

test "pattern.parse ctrl+f1" {
    const result = comptime parse("Ctrl+F1");

    try testing.expectEqual(keycode.f1, result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "pattern.parse digit" {
    const result = comptime parse("Ctrl+1");

    try testing.expectEqual(@as(u8, '1'), result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "pattern.parse modifier order independent" {
    const result1 = comptime parse("Ctrl+Alt+A");
    const result2 = comptime parse("Alt+Ctrl+A");

    try testing.expectEqual(result1.key, result2.key);
    try testing.expect(result1.modifiers.ctrl());
    try testing.expect(result1.modifiers.alt());
    try testing.expect(result2.modifiers.ctrl());
    try testing.expect(result2.modifiers.alt());
}
