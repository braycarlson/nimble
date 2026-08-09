const std = @import("std");

const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");

const assert = std.debug.assert;
const Keycode = keycode.Keycode;

pub const ParsedPattern = struct {
    key: Keycode,
    modifiers: modifier.Set,
};

pub fn parse(comptime pattern: []const u8) ParsedPattern {
    comptime {
        assert(pattern.len != 0);

        var mods = modifier.Set.Args{};
        var start: u32 = 0;
        var key_value: Keycode = .silent;

        for (pattern, 0..) |char, index| {
            if (char == '+') {
                const part = pattern[start..index];
                mods = parse_modifier(part, mods);
                start = @intCast(index + 1);
            }
        }

        const part = pattern[start..];
        key_value = parse_key(part);

        return ParsedPattern{
            .key = key_value,
            .modifiers = modifier.Set.from(mods),
        };
    }
}

fn parse_modifier(comptime part: []const u8, current: modifier.Set.Args) modifier.Set.Args {
    assert(part.len > 0);

    if (part.len > 16) {
        @compileError("unknown modifier: " ++ part);
    }

    var lowered: [part.len]u8 = undefined;

    for (part, 0..) |char, index| {
        lowered[index] = std.ascii.toLower(char);
    }

    const kind = modifier.Kind.from_string(&lowered) orelse
        @compileError("unknown modifier: " ++ part);

    assert(kind.is_valid());

    var result = current;

    switch (kind) {
        .ctrl => result.ctrl = true,
        .alt => result.alt = true,
        .shift => result.shift = true,
        .win => result.win = true,
    }

    return result;
}

fn parse_key(comptime part: []const u8) Keycode {
    assert(part.len > 0);

    if (part.len == 1) {
        return parse_key_char(part[0]);
    }

    assert(part.len > 1);

    if (std.mem.eql(u8, part, "Space")) return .space;
    if (std.mem.eql(u8, part, "Enter") or std.mem.eql(u8, part, "Return")) return .enter;
    if (std.mem.eql(u8, part, "Tab")) return .tab;
    if (std.mem.eql(u8, part, "Escape") or std.mem.eql(u8, part, "Esc")) return .escape;
    if (std.mem.eql(u8, part, "Backspace")) return .backspace;
    if (std.mem.eql(u8, part, "Delete") or std.mem.eql(u8, part, "Del")) return .delete;
    if (std.mem.eql(u8, part, "Insert")) return .insert;
    if (std.mem.eql(u8, part, "Home")) return .home;
    if (std.mem.eql(u8, part, "End")) return .end;
    if (std.mem.eql(u8, part, "PageUp")) return .page_up;
    if (std.mem.eql(u8, part, "PageDown")) return .page_down;
    if (std.mem.eql(u8, part, "Left")) return .arrow_left;
    if (std.mem.eql(u8, part, "Up")) return .arrow_up;
    if (std.mem.eql(u8, part, "Right")) return .arrow_right;
    if (std.mem.eql(u8, part, "Down")) return .arrow_down;

    if (std.mem.eql(u8, part, "F1")) return .f1;
    if (std.mem.eql(u8, part, "F2")) return .f2;
    if (std.mem.eql(u8, part, "F3")) return .f3;
    if (std.mem.eql(u8, part, "F4")) return .f4;
    if (std.mem.eql(u8, part, "F5")) return .f5;
    if (std.mem.eql(u8, part, "F6")) return .f6;
    if (std.mem.eql(u8, part, "F7")) return .f7;
    if (std.mem.eql(u8, part, "F8")) return .f8;
    if (std.mem.eql(u8, part, "F9")) return .f9;
    if (std.mem.eql(u8, part, "F10")) return .f10;
    if (std.mem.eql(u8, part, "F11")) return .f11;
    if (std.mem.eql(u8, part, "F12")) return .f12;

    @compileError("unknown key: " ++ part);
}

fn parse_key_char(comptime char: u8) Keycode {
    assert(char != 0);
    assert(char < 0x80);

    if (Keycode.from_char(char)) |code| {
        return code;
    }

    return switch (char) {
        ';' => .semicolon,
        '/' => .slash,
        '`' => .backtick,
        '[' => .bracket_left,
        '\\' => .backslash,
        ']' => .bracket_right,
        '\'' => .quote,
        '=' => .equal,
        ',' => .comma,
        '-' => .minus,
        '.' => .period,
        else => @compileError(std.fmt.comptimePrint("unknown key character: {c}", .{char})),
    };
}

const testing = std.testing;

test "a pattern parses a single letter" {
    const result = comptime parse("A");

    try testing.expectEqual(Keycode.a, result.key);
    try testing.expect(result.modifiers.none());
}

test "a pattern parses a lowercase letter" {
    const result = comptime parse("a");

    try testing.expectEqual(Keycode.a, result.key);
    try testing.expect(result.modifiers.none());
}

test "a pattern parses the ctrl modifier" {
    const result = comptime parse("Ctrl+A");

    try testing.expectEqual(Keycode.a, result.key);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(!result.modifiers.alt());
    try testing.expect(!result.modifiers.shift());
    try testing.expect(!result.modifiers.win());
}

test "a pattern parses a lowercase ctrl modifier" {
    const result = comptime parse("ctrl+A");

    try testing.expectEqual(Keycode.a, result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "a pattern parses the alt modifier" {
    const result = comptime parse("Alt+B");

    try testing.expectEqual(Keycode.b, result.key);
    try testing.expect(result.modifiers.alt());
    try testing.expect(!result.modifiers.ctrl());
}

test "a pattern parses a lowercase alt modifier" {
    const result = comptime parse("alt+B");

    try testing.expectEqual(Keycode.b, result.key);
    try testing.expect(result.modifiers.alt());
}

test "a pattern parses the shift modifier" {
    const result = comptime parse("Shift+C");

    try testing.expectEqual(Keycode.c, result.key);
    try testing.expect(result.modifiers.shift());
    try testing.expect(!result.modifiers.ctrl());
}

test "a pattern parses a lowercase shift modifier" {
    const result = comptime parse("shift+C");

    try testing.expectEqual(Keycode.c, result.key);
    try testing.expect(result.modifiers.shift());
}

test "a pattern parses the win modifier" {
    const result = comptime parse("Win+D");

    try testing.expectEqual(Keycode.d, result.key);
    try testing.expect(result.modifiers.win());
    try testing.expect(!result.modifiers.ctrl());
}

test "a pattern parses a lowercase win modifier" {
    const result = comptime parse("win+D");

    try testing.expectEqual(Keycode.d, result.key);
    try testing.expect(result.modifiers.win());
}

test "a pattern parses ctrl and alt together" {
    const result = comptime parse("Ctrl+Alt+E");

    try testing.expectEqual(Keycode.e, result.key);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(result.modifiers.alt());
    try testing.expect(!result.modifiers.shift());
    try testing.expect(!result.modifiers.win());
}

test "a pattern parses ctrl and shift together" {
    const result = comptime parse("Ctrl+Shift+F");

    try testing.expectEqual(Keycode.f, result.key);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(result.modifiers.shift());
}

test "a pattern parses alt and shift together" {
    const result = comptime parse("Alt+Shift+G");

    try testing.expectEqual(Keycode.g, result.key);
    try testing.expect(result.modifiers.alt());
    try testing.expect(result.modifiers.shift());
}

test "a pattern parses ctrl, alt and shift together" {
    const result = comptime parse("Ctrl+Alt+Shift+H");

    try testing.expectEqual(Keycode.h, result.key);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(result.modifiers.alt());
    try testing.expect(result.modifiers.shift());
    try testing.expect(!result.modifiers.win());
}

test "a pattern parses every modifier at once" {
    const result = comptime parse("Ctrl+Alt+Shift+Win+I");

    try testing.expectEqual(Keycode.i, result.key);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(result.modifiers.alt());
    try testing.expect(result.modifiers.shift());
    try testing.expect(result.modifiers.win());
}

test "a pattern parses the space key" {
    const result = comptime parse("Ctrl+Space");

    try testing.expectEqual(Keycode.space, result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "a pattern parses the enter key" {
    const result = comptime parse("Ctrl+Enter");

    try testing.expectEqual(Keycode.enter, result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "a pattern parses return as enter" {
    const result = comptime parse("Ctrl+Return");

    try testing.expectEqual(Keycode.enter, result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "a pattern parses the tab key" {
    const result = comptime parse("Alt+Tab");

    try testing.expectEqual(Keycode.tab, result.key);
    try testing.expect(result.modifiers.alt());
}

test "a pattern parses the escape key" {
    const result = comptime parse("Escape");

    try testing.expectEqual(Keycode.escape, result.key);
    try testing.expect(result.modifiers.none());
}

test "a pattern parses esc as escape" {
    const result = comptime parse("Esc");

    try testing.expectEqual(Keycode.escape, result.key);
}

test "a pattern parses the backspace key" {
    const result = comptime parse("Ctrl+Backspace");

    try testing.expectEqual(Keycode.backspace, result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "a pattern parses the delete key" {
    const result = comptime parse("Shift+Delete");

    try testing.expectEqual(Keycode.delete, result.key);
    try testing.expect(result.modifiers.shift());
}

test "a pattern parses del as delete" {
    const result = comptime parse("Shift+Del");

    try testing.expectEqual(Keycode.delete, result.key);
}

test "a pattern parses the insert key" {
    const result = comptime parse("Insert");

    try testing.expectEqual(Keycode.insert, result.key);
}

test "a pattern parses the home key" {
    const result = comptime parse("Ctrl+Home");

    try testing.expectEqual(Keycode.home, result.key);
}

test "a pattern parses the end key" {
    const result = comptime parse("Ctrl+End");

    try testing.expectEqual(Keycode.end, result.key);
}

test "a pattern parses the page up key" {
    const result = comptime parse("PageUp");

    try testing.expectEqual(Keycode.page_up, result.key);
}

test "a pattern parses the page down key" {
    const result = comptime parse("PageDown");

    try testing.expectEqual(Keycode.page_down, result.key);
}

test "a pattern parses every arrow key" {
    const left = comptime parse("Left");
    const right = comptime parse("Right");
    const up = comptime parse("Up");
    const down = comptime parse("Down");

    try testing.expectEqual(Keycode.arrow_left, left.key);
    try testing.expectEqual(Keycode.arrow_right, right.key);
    try testing.expectEqual(Keycode.arrow_up, up.key);
    try testing.expectEqual(Keycode.arrow_down, down.key);
}

test "a pattern parses the function keys" {
    const f1 = comptime parse("F1");
    const f12 = comptime parse("F12");

    try testing.expectEqual(Keycode.f1, f1.key);
    try testing.expectEqual(Keycode.f12, f12.key);
}

test "a pattern parses ctrl with a function key" {
    const result = comptime parse("Ctrl+F1");

    try testing.expectEqual(Keycode.f1, result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "a pattern parses a digit" {
    const result = comptime parse("Ctrl+1");

    try testing.expectEqual(Keycode.digit_1, result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "a pattern parses modifiers in any order" {
    const result1 = comptime parse("Ctrl+Alt+A");
    const result2 = comptime parse("Alt+Ctrl+A");

    try testing.expectEqual(result1.key, result2.key);
    try testing.expect(result1.modifiers.ctrl());
    try testing.expect(result1.modifiers.alt());
    try testing.expect(result2.modifiers.ctrl());
    try testing.expect(result2.modifiers.alt());
}

test "a pattern parses control as ctrl" {
    const result = comptime parse("Control+C");

    try testing.expectEqual(Keycode.c, result.key);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(!result.modifiers.alt());
}

test "a pattern parses lowercase control as ctrl" {
    const result = comptime parse("control+C");

    try testing.expectEqual(Keycode.c, result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "a pattern parses modifiers case insensitively" {
    const result = comptime parse("CTRL+SHIFT+C");

    try testing.expectEqual(Keycode.c, result.key);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(result.modifiers.shift());
}

test "a pattern parses windows as win" {
    const result = comptime parse("Windows+D");

    try testing.expectEqual(Keycode.d, result.key);
    try testing.expect(result.modifiers.win());
    try testing.expect(!result.modifiers.ctrl());
}

test "a pattern parses meta as win" {
    const result = comptime parse("Meta+D");

    try testing.expectEqual(Keycode.d, result.key);
    try testing.expect(result.modifiers.win());
    try testing.expect(!result.modifiers.shift());
}

test "a pattern parses the semicolon key" {
    const result = comptime parse(";");

    try testing.expectEqual(Keycode.semicolon, result.key);
    try testing.expect(result.modifiers.none());
}

test "a pattern parses the slash key" {
    const result = comptime parse("/");

    try testing.expectEqual(Keycode.slash, result.key);
    try testing.expect(result.modifiers.none());
}

test "a pattern parses the backtick key" {
    const result = comptime parse("`");

    try testing.expectEqual(Keycode.backtick, result.key);
    try testing.expect(result.modifiers.none());
}

test "a pattern parses the bracket keys" {
    const open = comptime parse("[");
    const close = comptime parse("]");

    try testing.expectEqual(Keycode.bracket_left, open.key);
    try testing.expectEqual(Keycode.bracket_right, close.key);
}

test "a pattern parses the backslash key" {
    const result = comptime parse("\\");

    try testing.expectEqual(Keycode.backslash, result.key);
    try testing.expect(result.modifiers.none());
}

test "a pattern parses the apostrophe key" {
    const result = comptime parse("'");

    try testing.expectEqual(Keycode.quote, result.key);
    try testing.expect(result.modifiers.none());
}

test "a pattern parses the equals key" {
    const result = comptime parse("=");

    try testing.expectEqual(Keycode.equal, result.key);
    try testing.expect(result.modifiers.none());
}

test "a pattern parses the comma key" {
    const result = comptime parse(",");

    try testing.expectEqual(Keycode.comma, result.key);
    try testing.expect(result.modifiers.none());
}

test "a pattern parses the minus key" {
    const result = comptime parse("-");

    try testing.expectEqual(Keycode.minus, result.key);
    try testing.expect(result.modifiers.none());
}

test "a pattern parses the period key" {
    const result = comptime parse(".");

    try testing.expectEqual(Keycode.period, result.key);
    try testing.expect(result.modifiers.none());
}

test "a pattern parses punctuation with a modifier" {
    const result = comptime parse("Ctrl+;");

    try testing.expectEqual(Keycode.semicolon, result.key);
    try testing.expect(result.modifiers.ctrl());
}

test "a pattern parses a function key on its own" {
    const result = comptime parse("Ctrl+F5");

    try testing.expectEqual(Keycode.f5, result.key);
    try testing.expect(result.modifiers.ctrl());
}
