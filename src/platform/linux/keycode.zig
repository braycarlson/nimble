const std = @import("std");

const core = @import("../../keycode.zig");

const assert = std.debug.assert;

const Keycode = core.Keycode;

pub const value_min: u8 = 1;
pub const value_max: u8 = 247;
pub const table_size: u16 = 256;

const Pair = struct { Keycode, u8 };

const pairs = [_]Pair{
    .{ .digit_0, 11 },
    .{ .digit_1, 2 },
    .{ .digit_2, 3 },
    .{ .digit_3, 4 },
    .{ .digit_4, 5 },
    .{ .digit_5, 6 },
    .{ .digit_6, 7 },
    .{ .digit_7, 8 },
    .{ .digit_8, 9 },
    .{ .digit_9, 10 },
    .{ .a, 30 },
    .{ .b, 48 },
    .{ .c, 46 },
    .{ .d, 32 },
    .{ .e, 18 },
    .{ .f, 33 },
    .{ .g, 34 },
    .{ .h, 35 },
    .{ .i, 23 },
    .{ .j, 36 },
    .{ .k, 37 },
    .{ .l, 38 },
    .{ .m, 50 },
    .{ .n, 49 },
    .{ .o, 24 },
    .{ .p, 25 },
    .{ .q, 16 },
    .{ .r, 19 },
    .{ .s, 31 },
    .{ .t, 20 },
    .{ .u, 22 },
    .{ .v, 47 },
    .{ .w, 17 },
    .{ .x, 45 },
    .{ .y, 21 },
    .{ .z, 44 },
    .{ .backspace, 14 },
    .{ .tab, 15 },
    .{ .enter, 28 },
    .{ .pause, 119 },
    .{ .caps_lock, 58 },
    .{ .escape, 1 },
    .{ .space, 57 },
    .{ .page_up, 104 },
    .{ .page_down, 109 },
    .{ .end, 107 },
    .{ .home, 102 },
    .{ .arrow_left, 105 },
    .{ .arrow_up, 103 },
    .{ .arrow_right, 106 },
    .{ .arrow_down, 108 },
    .{ .print_screen, 99 },
    .{ .insert, 110 },
    .{ .delete, 111 },
    .{ .sleep, 142 },
    .{ .super_left, 125 },
    .{ .super_right, 126 },
    .{ .context_menu, 127 },
    .{ .numpad_0, 82 },
    .{ .numpad_1, 79 },
    .{ .numpad_2, 80 },
    .{ .numpad_3, 81 },
    .{ .numpad_4, 75 },
    .{ .numpad_5, 76 },
    .{ .numpad_6, 77 },
    .{ .numpad_7, 71 },
    .{ .numpad_8, 72 },
    .{ .numpad_9, 73 },
    .{ .numpad_multiply, 55 },
    .{ .numpad_add, 78 },
    .{ .numpad_subtract, 74 },
    .{ .numpad_decimal, 83 },
    .{ .numpad_divide, 98 },
    .{ .f1, 59 },
    .{ .f2, 60 },
    .{ .f3, 61 },
    .{ .f4, 62 },
    .{ .f5, 63 },
    .{ .f6, 64 },
    .{ .f7, 65 },
    .{ .f8, 66 },
    .{ .f9, 67 },
    .{ .f10, 68 },
    .{ .f11, 87 },
    .{ .f12, 88 },
    .{ .f13, 183 },
    .{ .f14, 184 },
    .{ .f15, 185 },
    .{ .f16, 186 },
    .{ .f17, 187 },
    .{ .f18, 188 },
    .{ .f19, 189 },
    .{ .f20, 190 },
    .{ .f21, 191 },
    .{ .f22, 192 },
    .{ .f23, 193 },
    .{ .f24, 194 },
    .{ .num_lock, 69 },
    .{ .scroll_lock, 70 },
    .{ .shift_left, 42 },
    .{ .shift_right, 54 },
    .{ .control_left, 29 },
    .{ .control_right, 97 },
    .{ .alt_left, 56 },
    .{ .alt_right, 100 },
    .{ .browser_back, 158 },
    .{ .browser_forward, 159 },
    .{ .browser_refresh, 173 },
    .{ .browser_stop, 128 },
    .{ .browser_search, 217 },
    .{ .browser_favorites, 156 },
    .{ .browser_home, 172 },
    .{ .volume_mute, 113 },
    .{ .volume_down, 114 },
    .{ .volume_up, 115 },
    .{ .media_next, 163 },
    .{ .media_previous, 165 },
    .{ .media_stop, 166 },
    .{ .media_play_pause, 164 },
    .{ .launch_mail, 155 },
    .{ .launch_media, 226 },
    .{ .launch_application_1, 148 },
    .{ .launch_application_2, 149 },
    .{ .semicolon, 39 },
    .{ .equal, 13 },
    .{ .comma, 51 },
    .{ .minus, 12 },
    .{ .period, 52 },
    .{ .slash, 53 },
    .{ .backtick, 41 },
    .{ .bracket_left, 26 },
    .{ .backslash, 43 },
    .{ .bracket_right, 27 },
    .{ .quote, 40 },
    .{ .intl_backslash, 86 },
};

const generic_pairs = [_]Pair{
    .{ .shift, 42 },
    .{ .control, 29 },
    .{ .alt, 56 },
};

const forward = build_forward();
const reverse = build_reverse();

comptime {
    assert(pairs.len > 0);
    assert(generic_pairs.len == 3);
    assert(value_min < value_max);
    assert_round_trip();
}

pub fn from_native(key_code: u8) ?Keycode {
    return forward[key_code];
}

pub fn to_native(code: Keycode) ?u8 {
    return reverse[@intFromEnum(code)];
}

fn build_forward() [table_size]?Keycode {
    @setEvalBranchQuota(table_size * 64);

    var result: [table_size]?Keycode = @splat(null);

    for (pairs) |pair| {
        assert(pair[1] >= value_min);
        assert(pair[1] <= value_max);
        assert(result[pair[1]] == null);

        result[pair[1]] = pair[0];
    }

    return result;
}

fn build_reverse() [table_size]?u8 {
    @setEvalBranchQuota(table_size * 64);

    var result: [table_size]?u8 = @splat(null);

    for (pairs) |pair| {
        const index: u8 = @intFromEnum(pair[0]);

        assert(result[index] == null);

        result[index] = pair[1];
    }

    for (generic_pairs) |pair| {
        const index: u8 = @intFromEnum(pair[0]);

        assert(result[index] == null);

        result[index] = pair[1];
    }

    return result;
}

fn assert_round_trip() void {
    @setEvalBranchQuota(table_size * 128);

    for (pairs) |pair| {
        const key_code = to_native(pair[0]) orelse unreachable;

        assert(key_code == pair[1]);
        assert(from_native(key_code) == pair[0]);
    }

    for (0..table_size) |index| {
        const key_code: u8 = @intCast(index);
        const mapped = from_native(key_code) orelse continue;
        const back = to_native(mapped) orelse unreachable;

        assert(back == key_code);
    }
}

const testing = std.testing;

test "every mapped Linux key code round trips" {
    var key_code: u16 = 0;

    while (key_code < table_size) : (key_code += 1) {
        const mapped = from_native(@intCast(key_code)) orelse continue;
        const back = to_native(mapped) orelse return error.MissingReverseMapping;

        try testing.expectEqual(@as(u8, @intCast(key_code)), back);
    }
}

test "generic modifiers synthesize onto the left physical key" {
    try testing.expectEqual(to_native(.shift_left), to_native(.shift));
    try testing.expectEqual(to_native(.control_left), to_native(.control));
    try testing.expectEqual(to_native(.alt_left), to_native(.alt));

    try testing.expectEqual(Keycode.shift_left, from_native(42).?);
    try testing.expectEqual(Keycode.control_left, from_native(29).?);
    try testing.expectEqual(Keycode.alt_left, from_native(56).?);
}

test "unmappable codes report absence" {
    try testing.expect(from_native(0) == null);
    try testing.expect(to_native(.silent) == null);
    try testing.expect(to_native(.numpad_separator) == null);
}

test "named keys map to their documented Linux key codes" {
    try testing.expectEqual(@as(u8, 59), to_native(.f1).?);
    try testing.expectEqual(@as(u8, 30), to_native(.a).?);
    try testing.expectEqual(@as(u8, 11), to_native(.digit_0).?);
    try testing.expectEqual(@as(u8, 29), to_native(.control_left).?);
}
