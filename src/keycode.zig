const std = @import("std");

const assert = std.debug.assert;

pub const Keycode = enum(u8) {
    silent,

    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,

    digit_0,
    digit_1,
    digit_2,
    digit_3,
    digit_4,
    digit_5,
    digit_6,
    digit_7,
    digit_8,
    digit_9,

    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,

    backspace,
    tab,
    enter,
    escape,
    space,
    caps_lock,
    num_lock,
    scroll_lock,
    print_screen,
    pause,
    insert,
    delete,
    home,
    end,
    page_up,
    page_down,
    arrow_left,
    arrow_up,
    arrow_right,
    arrow_down,
    context_menu,

    shift,
    shift_left,
    shift_right,
    control,
    control_left,
    control_right,
    alt,
    alt_left,
    alt_right,
    super,
    super_left,
    super_right,

    numpad_0,
    numpad_1,
    numpad_2,
    numpad_3,
    numpad_4,
    numpad_5,
    numpad_6,
    numpad_7,
    numpad_8,
    numpad_9,
    numpad_add,
    numpad_decimal,
    numpad_divide,
    numpad_multiply,
    numpad_separator,
    numpad_subtract,

    backslash,
    backtick,
    bracket_left,
    bracket_right,
    comma,
    equal,
    intl_backslash,
    minus,
    period,
    quote,
    semicolon,
    slash,

    browser_back,
    browser_favorites,
    browser_forward,
    browser_home,
    browser_refresh,
    browser_search,
    browser_stop,
    launch_application_1,
    launch_application_2,
    launch_mail,
    launch_media,
    media_next,
    media_play_pause,
    media_previous,
    media_stop,
    volume_down,
    volume_mute,
    volume_up,

    clear,
    execute,
    help,
    print,
    select,
    sleep,

    pub fn from_char(character: u8) ?Keycode {
        const upper = std.ascii.toUpper(character);

        if (upper >= 'A' and upper <= 'Z') {
            return offset(.a, upper - 'A');
        }

        if (upper >= '0' and upper <= '9') {
            return offset(.digit_0, upper - '0');
        }

        return null;
    }

    pub fn from_name(text: []const u8) ?Keycode {
        assert(text.len > 0);
        assert(text.len <= name_bytes_max);

        return name_map.get(text);
    }

    pub fn from_string(text: []const u8) ?Keycode {
        if (text.len == 0) {
            return null;
        }

        assert(text.len > 0);
        assert(text.len <= string_bytes_max);

        if (text.len == 1) {
            return from_char(text[0]);
        }

        assert(text.len > 1);

        if (text.len > name_bytes_max) {
            return null;
        }

        return from_name(text);
    }

    pub fn is_alpha(keycode: Keycode) bool {
        return within(keycode, .a, .z);
    }

    pub fn is_digit(keycode: Keycode) bool {
        return within(keycode, .digit_0, .digit_9);
    }

    pub fn is_function(keycode: Keycode) bool {
        return within(keycode, .f1, .f24);
    }

    pub fn is_numpad(keycode: Keycode) bool {
        return within(keycode, .numpad_0, .numpad_subtract);
    }

    pub fn is_modifier(keycode: Keycode) bool {
        return within(keycode, .shift, .super_right);
    }

    pub fn to_char(keycode: Keycode) ?u8 {
        if (keycode.is_alpha()) {
            return 'A' + distance(.a, keycode);
        }

        if (keycode.is_digit()) {
            return '0' + distance(.digit_0, keycode);
        }

        return null;
    }

    pub fn to_name(keycode: Keycode) ?[]const u8 {
        const result: ?[]const u8 = switch (keycode) {
            .backspace => "Backspace",
            .tab => "Tab",
            .enter => "Enter",
            .shift, .shift_left, .shift_right => "Shift",
            .control, .control_left, .control_right => "Ctrl",
            .alt, .alt_left, .alt_right => "Alt",
            .super, .super_left, .super_right => "Super",
            .pause => "Pause",
            .caps_lock => "CapsLock",
            .escape => "Escape",
            .space => "Space",
            .page_up => "PageUp",
            .page_down => "PageDown",
            .end => "End",
            .home => "Home",
            .arrow_left => "Left",
            .arrow_up => "Up",
            .arrow_right => "Right",
            .arrow_down => "Down",
            .print_screen => "PrintScreen",
            .insert => "Insert",
            .delete => "Delete",
            .context_menu => "Menu",
            .f1 => "F1",
            .f2 => "F2",
            .f3 => "F3",
            .f4 => "F4",
            .f5 => "F5",
            .f6 => "F6",
            .f7 => "F7",
            .f8 => "F8",
            .f9 => "F9",
            .f10 => "F10",
            .f11 => "F11",
            .f12 => "F12",
            .f13 => "F13",
            .f14 => "F14",
            .f15 => "F15",
            .f16 => "F16",
            .f17 => "F17",
            .f18 => "F18",
            .f19 => "F19",
            .f20 => "F20",
            .f21 => "F21",
            .f22 => "F22",
            .f23 => "F23",
            .f24 => "F24",
            .num_lock => "NumLock",
            .scroll_lock => "ScrollLock",
            else => null,
        };

        return result;
    }

    pub fn to_string(keycode: Keycode) ?[]const u8 {
        if (keycode.is_alpha()) {
            return null;
        }

        if (keycode.is_digit()) {
            return null;
        }

        return keycode.to_name();
    }

    fn offset(base: Keycode, step: u8) Keycode {
        const value: u16 = @as(u16, @intFromEnum(base)) + step;

        assert(value < count);

        return @enumFromInt(@as(u8, @intCast(value)));
    }

    fn distance(base: Keycode, self: Keycode) u8 {
        assert(@intFromEnum(self) >= @intFromEnum(base));

        return @intFromEnum(self) - @intFromEnum(base);
    }

    fn within(keycode: Keycode, low: Keycode, high: Keycode) bool {
        const value = @intFromEnum(keycode);

        assert(@intFromEnum(low) <= @intFromEnum(high));

        return value >= @intFromEnum(low) and value <= @intFromEnum(high);
    }
};

pub const name_bytes_max: u8 = 16;
pub const string_bytes_max: u8 = 32;
pub const count: u16 = @typeInfo(Keycode).@"enum".fields.len;
pub const value_max: u8 = count - 1;

pub fn is_defined(code: Keycode) bool {
    return @intFromEnum(code) <= value_max;
}

const name_map = std.StaticStringMap(Keycode).initComptime(.{
    .{ "backspace", .backspace },
    .{ "tab", .tab },
    .{ "enter", .enter },
    .{ "return", .enter },
    .{ "pause", .pause },
    .{ "capslock", .caps_lock },
    .{ "caps", .caps_lock },
    .{ "escape", .escape },
    .{ "esc", .escape },
    .{ "space", .space },
    .{ "pageup", .page_up },
    .{ "pagedown", .page_down },
    .{ "end", .end },
    .{ "home", .home },
    .{ "left", .arrow_left },
    .{ "up", .arrow_up },
    .{ "right", .arrow_right },
    .{ "down", .arrow_down },
    .{ "printscreen", .print_screen },
    .{ "insert", .insert },
    .{ "delete", .delete },
    .{ "del", .delete },
    .{ "menu", .context_menu },
    .{ "f1", .f1 },
    .{ "f2", .f2 },
    .{ "f3", .f3 },
    .{ "f4", .f4 },
    .{ "f5", .f5 },
    .{ "f6", .f6 },
    .{ "f7", .f7 },
    .{ "f8", .f8 },
    .{ "f9", .f9 },
    .{ "f10", .f10 },
    .{ "f11", .f11 },
    .{ "f12", .f12 },
    .{ "f13", .f13 },
    .{ "f14", .f14 },
    .{ "f15", .f15 },
    .{ "f16", .f16 },
    .{ "f17", .f17 },
    .{ "f18", .f18 },
    .{ "f19", .f19 },
    .{ "f20", .f20 },
    .{ "f21", .f21 },
    .{ "f22", .f22 },
    .{ "f23", .f23 },
    .{ "f24", .f24 },
    .{ "numlock", .num_lock },
    .{ "scrolllock", .scroll_lock },
});

comptime {
    assert(name_bytes_max < string_bytes_max);
    assert(count > 0);
    assert(count <= 256);
    assert(@intFromEnum(Keycode.silent) == 0);
    assert(@intFromEnum(Keycode.z) - @intFromEnum(Keycode.a) == 25);
    assert(@intFromEnum(Keycode.digit_9) - @intFromEnum(Keycode.digit_0) == 9);
    assert(@intFromEnum(Keycode.f24) - @intFromEnum(Keycode.f1) == 23);
    assert_dense();
}

fn assert_dense() void {
    for (@typeInfo(Keycode).@"enum".fields, 0..) |field, index| {
        assert(field.value == index);
    }
}

const testing = std.testing;

test "keycodes are dense with no holes" {
    inline for (@typeInfo(Keycode).@"enum".fields, 0..) |field, index| {
        try testing.expectEqual(index, field.value);
    }

    try testing.expectEqual(@as(u16, count - 1), @as(u16, value_max));
}

test "is_defined accepts every enumerated keycode" {
    inline for (@typeInfo(Keycode).@"enum".fields) |field| {
        try testing.expect(is_defined(@enumFromInt(field.value)));
    }
}

test "a keycode reports whether it is a letter" {
    try testing.expect(Keycode.a.is_alpha());
    try testing.expect(Keycode.z.is_alpha());
    try testing.expect(Keycode.m.is_alpha());
    try testing.expect(!Keycode.digit_0.is_alpha());
    try testing.expect(!Keycode.digit_9.is_alpha());
    try testing.expect(!Keycode.space.is_alpha());
    try testing.expect(!Keycode.enter.is_alpha());
    try testing.expect(!Keycode.silent.is_alpha());
}

test "a keycode reports whether it is a digit" {
    try testing.expect(Keycode.digit_0.is_digit());
    try testing.expect(Keycode.digit_9.is_digit());
    try testing.expect(Keycode.digit_5.is_digit());
    try testing.expect(!Keycode.a.is_digit());
    try testing.expect(!Keycode.z.is_digit());
    try testing.expect(!Keycode.space.is_digit());
    try testing.expect(!Keycode.numpad_0.is_digit());
}

test "a keycode reports whether it is a function key" {
    try testing.expect(Keycode.f1.is_function());
    try testing.expect(Keycode.f24.is_function());
    try testing.expect(!Keycode.a.is_function());
    try testing.expect(!Keycode.digit_1.is_function());
}

test "a keycode reports whether it is a numpad key" {
    try testing.expect(Keycode.numpad_0.is_numpad());
    try testing.expect(Keycode.numpad_9.is_numpad());
    try testing.expect(Keycode.numpad_subtract.is_numpad());
    try testing.expect(Keycode.numpad_divide.is_numpad());
    try testing.expect(!Keycode.digit_0.is_numpad());
    try testing.expect(!Keycode.minus.is_numpad());
}

test "a sided modifier keycode reports as a modifier" {
    try testing.expect(Keycode.shift_left.is_modifier());
    try testing.expect(Keycode.shift_right.is_modifier());
    try testing.expect(Keycode.control_left.is_modifier());
    try testing.expect(Keycode.control_right.is_modifier());
    try testing.expect(Keycode.alt_left.is_modifier());
    try testing.expect(Keycode.alt_right.is_modifier());
    try testing.expect(Keycode.super_left.is_modifier());
    try testing.expect(Keycode.super_right.is_modifier());
}

test "a generic modifier keycode reports as a modifier" {
    try testing.expect(Keycode.shift.is_modifier());
    try testing.expect(Keycode.control.is_modifier());
    try testing.expect(Keycode.alt.is_modifier());
    try testing.expect(Keycode.super.is_modifier());
}

test "a keycode that is not a modifier reports so" {
    try testing.expect(!Keycode.a.is_modifier());
    try testing.expect(!Keycode.digit_0.is_modifier());
    try testing.expect(!Keycode.space.is_modifier());
    try testing.expect(!Keycode.f1.is_modifier());
    try testing.expect(!Keycode.caps_lock.is_modifier());
    try testing.expect(!Keycode.context_menu.is_modifier());
}

test "a letter maps to its keycode whatever its case" {
    try testing.expectEqual(Keycode.a, Keycode.from_char('a').?);
    try testing.expectEqual(Keycode.a, Keycode.from_char('A').?);
    try testing.expectEqual(Keycode.z, Keycode.from_char('z').?);
    try testing.expectEqual(Keycode.z, Keycode.from_char('Z').?);
}

test "a digit maps to its keycode" {
    try testing.expectEqual(Keycode.digit_0, Keycode.from_char('0').?);
    try testing.expectEqual(Keycode.digit_9, Keycode.from_char('9').?);
}

test "punctuation maps to no keycode" {
    try testing.expect(Keycode.from_char('!') == null);
    try testing.expect(Keycode.from_char('+') == null);
    try testing.expect(Keycode.from_char(' ') == null);
}

test "a keycode and its character round trip" {
    var character: u8 = 'A';

    while (character <= 'Z') : (character += 1) {
        const code = Keycode.from_char(character) orelse return error.MissingMapping;

        try testing.expectEqual(character, code.to_char().?);
    }

    var digit: u8 = '0';

    while (digit <= '9') : (digit += 1) {
        const code = Keycode.from_char(digit) orelse return error.MissingMapping;

        try testing.expectEqual(digit, code.to_char().?);
    }
}

test "a non printable keycode has no character" {
    try testing.expect(Keycode.f1.to_char() == null);
    try testing.expect(Keycode.space.to_char() == null);
    try testing.expect(Keycode.control_left.to_char() == null);
    try testing.expect(Keycode.silent.to_char() == null);
    try testing.expect(Keycode.numpad_0.to_char() == null);
}

test "a known key name maps to its keycode" {
    try testing.expectEqual(Keycode.backspace, Keycode.from_name("backspace").?);
    try testing.expectEqual(Keycode.enter, Keycode.from_name("enter").?);
    try testing.expectEqual(Keycode.enter, Keycode.from_name("return").?);
    try testing.expectEqual(Keycode.escape, Keycode.from_name("esc").?);
    try testing.expectEqual(Keycode.caps_lock, Keycode.from_name("caps").?);
    try testing.expectEqual(Keycode.page_up, Keycode.from_name("pageup").?);
    try testing.expectEqual(Keycode.page_down, Keycode.from_name("pagedown").?);
    try testing.expectEqual(Keycode.print_screen, Keycode.from_name("printscreen").?);
    try testing.expectEqual(Keycode.arrow_left, Keycode.from_name("left").?);
    try testing.expectEqual(Keycode.f12, Keycode.from_name("f12").?);
    try testing.expectEqual(Keycode.f24, Keycode.from_name("f24").?);
}

test "an unknown key name maps to no keycode" {
    try testing.expect(Keycode.from_name("nope") == null);
    try testing.expect(Keycode.from_name("f99") == null);
}

test "a key string is read as a character or a name by its length" {
    try testing.expectEqual(Keycode.a, Keycode.from_string("a").?);
    try testing.expectEqual(Keycode.space, Keycode.from_string("space").?);
    try testing.expect(Keycode.from_string("") == null);
    try testing.expect(Keycode.from_string("a name far longer than sixteen") == null);
}

test "sided modifiers share one name" {
    try testing.expectEqualStrings("Shift", Keycode.shift_left.to_name().?);
    try testing.expectEqualStrings("Shift", Keycode.shift_right.to_name().?);
    try testing.expectEqualStrings("Ctrl", Keycode.control_left.to_name().?);
    try testing.expectEqualStrings("Ctrl", Keycode.control_right.to_name().?);
    try testing.expectEqualStrings("Alt", Keycode.alt_left.to_name().?);
    try testing.expectEqualStrings("Alt", Keycode.alt_right.to_name().?);
    try testing.expectEqualStrings("Super", Keycode.super_left.to_name().?);
    try testing.expectEqualStrings("Super", Keycode.super_right.to_name().?);
}

test "a printable keycode has no name" {
    try testing.expect(Keycode.a.to_string() == null);
    try testing.expect(Keycode.digit_0.to_string() == null);
    try testing.expectEqualStrings("Space", Keycode.space.to_string().?);
}

test "every name in the map round trips back to a label" {
    for (name_map.values()) |code| {
        try testing.expect(code.to_name() != null);
    }
}

test "a keycode name round trips through from_name" {
    const names = [_][]const u8{ "backspace", "tab", "enter", "escape", "space", "home", "end" };

    for (names) |name| {
        const code = Keycode.from_name(name) orelse return error.MissingMapping;

        try testing.expect(code.to_name() != null);
    }
}
