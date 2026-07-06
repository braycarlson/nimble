const std = @import("std");

const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");

pub const ParsedPattern = struct {
    key: u8,
    modifiers: modifier.Set,
};

pub fn parse(comptime pattern: []const u8) ParsedPattern {
    comptime {
        std.debug.assert(pattern.len != 0);

        var mods = modifier.Set.Args{};
        var start: u32 = 0;
        var key_value: u8 = 0;

        for (pattern, 0..) |char, index| {
            if (char == '+') {
                const part = pattern[start..index];
                mods = parse_modifier(part, mods);
                start = @intCast(index + 1);
            }
        }

        const part = pattern[start..];
        key_value = parse_key(part);

        std.debug.assert(key_value != 0);
        std.debug.assert(keycode.is_valid(key_value));

        return ParsedPattern{
            .key = key_value,
            .modifiers = modifier.Set.from(mods),
        };
    }
}

fn parse_modifier(comptime part: []const u8, current: modifier.Set.Args) modifier.Set.Args {
    std.debug.assert(part.len > 0);

    if (part.len > 16) {
        @compileError("unknown modifier: " ++ part);
    }

    var lowered: [part.len]u8 = undefined;

    for (part, 0..) |char, index| {
        lowered[index] = std.ascii.toLower(char);
    }

    const kind = modifier.Kind.from_string(&lowered) orelse @compileError("unknown modifier: " ++ part);

    std.debug.assert(kind.is_valid());

    var result = current;

    switch (kind) {
        .ctrl => result.ctrl = true,
        .alt => result.alt = true,
        .shift => result.shift = true,
        .win => result.win = true,
    }

    return result;
}

fn parse_key(comptime part: []const u8) u8 {
    std.debug.assert(part.len > 0);

    if (part.len == 1) {
        return parse_key_char(part[0]);
    }

    std.debug.assert(part.len > 1);

    if (std.mem.eql(u8, part, "Space")) return keycode.space;
    if (std.mem.eql(u8, part, "Enter") or std.mem.eql(u8, part, "Return")) return keycode.@"return";
    if (std.mem.eql(u8, part, "Tab")) return keycode.tab;
    if (std.mem.eql(u8, part, "Escape") or std.mem.eql(u8, part, "Esc")) return keycode.escape;
    if (std.mem.eql(u8, part, "Backspace")) return keycode.back;
    if (std.mem.eql(u8, part, "Delete") or std.mem.eql(u8, part, "Del")) return keycode.delete;
    if (std.mem.eql(u8, part, "Insert")) return keycode.insert;
    if (std.mem.eql(u8, part, "Home")) return keycode.home;
    if (std.mem.eql(u8, part, "End")) return keycode.end;
    if (std.mem.eql(u8, part, "PageUp")) return keycode.prior;
    if (std.mem.eql(u8, part, "PageDown")) return keycode.next;
    if (std.mem.eql(u8, part, "Left")) return keycode.left;
    if (std.mem.eql(u8, part, "Up")) return keycode.up;
    if (std.mem.eql(u8, part, "Right")) return keycode.right;
    if (std.mem.eql(u8, part, "Down")) return keycode.down;

    if (std.mem.eql(u8, part, "F1")) return keycode.f1;
    if (std.mem.eql(u8, part, "F2")) return keycode.f2;
    if (std.mem.eql(u8, part, "F3")) return keycode.f3;
    if (std.mem.eql(u8, part, "F4")) return keycode.f4;
    if (std.mem.eql(u8, part, "F5")) return keycode.f5;
    if (std.mem.eql(u8, part, "F6")) return keycode.f6;
    if (std.mem.eql(u8, part, "F7")) return keycode.f7;
    if (std.mem.eql(u8, part, "F8")) return keycode.f8;
    if (std.mem.eql(u8, part, "F9")) return keycode.f9;
    if (std.mem.eql(u8, part, "F10")) return keycode.f10;
    if (std.mem.eql(u8, part, "F11")) return keycode.f11;
    if (std.mem.eql(u8, part, "F12")) return keycode.f12;

    @compileError("unknown key: " ++ part);
}

fn parse_key_char(comptime char: u8) u8 {
    std.debug.assert(char != 0);
    std.debug.assert(char < 0x80);

    const upper = std.ascii.toUpper(char);
    const alpha = upper >= 'A' and upper <= 'Z';
    const digit = upper >= '0' and upper <= '9';

    if (alpha or digit) {
        std.debug.assert(keycode.is_valid(upper));
        return upper;
    }

    return switch (char) {
        ';' => keycode.oem_1,
        '/' => keycode.oem_2,
        '`' => keycode.oem_3,
        '[' => keycode.oem_4,
        '\\' => keycode.oem_5,
        ']' => keycode.oem_6,
        '\'' => keycode.oem_7,
        '=' => keycode.oem_plus,
        ',' => keycode.oem_comma,
        '-' => keycode.oem_minus,
        '.' => keycode.oem_period,
        else => @compileError(std.fmt.comptimePrint("unknown key character: {c}", .{char})),
    };
}
