const std = @import("std");

const core = @import("../../keycode.zig");

const assert = std.debug.assert;

const Keycode = core.Keycode;

pub const value_min: u8 = 0x01;
pub const value_max: u8 = 0xFE;
pub const value_dummy: u8 = 0xFF;
pub const table_size: u16 = 256;

const Pair = struct { Keycode, u8 };

const pairs = [_]Pair{
    .{ .a, 0x41 },
    .{ .b, 0x42 },
    .{ .c, 0x43 },
    .{ .d, 0x44 },
    .{ .e, 0x45 },
    .{ .f, 0x46 },
    .{ .g, 0x47 },
    .{ .h, 0x48 },
    .{ .i, 0x49 },
    .{ .j, 0x4A },
    .{ .k, 0x4B },
    .{ .l, 0x4C },
    .{ .m, 0x4D },
    .{ .n, 0x4E },
    .{ .o, 0x4F },
    .{ .p, 0x50 },
    .{ .q, 0x51 },
    .{ .r, 0x52 },
    .{ .s, 0x53 },
    .{ .t, 0x54 },
    .{ .u, 0x55 },
    .{ .v, 0x56 },
    .{ .w, 0x57 },
    .{ .x, 0x58 },
    .{ .y, 0x59 },
    .{ .z, 0x5A },
    .{ .digit_0, 0x30 },
    .{ .digit_1, 0x31 },
    .{ .digit_2, 0x32 },
    .{ .digit_3, 0x33 },
    .{ .digit_4, 0x34 },
    .{ .digit_5, 0x35 },
    .{ .digit_6, 0x36 },
    .{ .digit_7, 0x37 },
    .{ .digit_8, 0x38 },
    .{ .digit_9, 0x39 },
    .{ .f1, 0x70 },
    .{ .f2, 0x71 },
    .{ .f3, 0x72 },
    .{ .f4, 0x73 },
    .{ .f5, 0x74 },
    .{ .f6, 0x75 },
    .{ .f7, 0x76 },
    .{ .f8, 0x77 },
    .{ .f9, 0x78 },
    .{ .f10, 0x79 },
    .{ .f11, 0x7A },
    .{ .f12, 0x7B },
    .{ .f13, 0x7C },
    .{ .f14, 0x7D },
    .{ .f15, 0x7E },
    .{ .f16, 0x7F },
    .{ .f17, 0x80 },
    .{ .f18, 0x81 },
    .{ .f19, 0x82 },
    .{ .f20, 0x83 },
    .{ .f21, 0x84 },
    .{ .f22, 0x85 },
    .{ .f23, 0x86 },
    .{ .f24, 0x87 },
    .{ .backspace, 0x08 },
    .{ .tab, 0x09 },
    .{ .enter, 0x0D },
    .{ .escape, 0x1B },
    .{ .space, 0x20 },
    .{ .caps_lock, 0x14 },
    .{ .num_lock, 0x90 },
    .{ .scroll_lock, 0x91 },
    .{ .print_screen, 0x2C },
    .{ .pause, 0x13 },
    .{ .insert, 0x2D },
    .{ .delete, 0x2E },
    .{ .home, 0x24 },
    .{ .end, 0x23 },
    .{ .page_up, 0x21 },
    .{ .page_down, 0x22 },
    .{ .arrow_left, 0x25 },
    .{ .arrow_up, 0x26 },
    .{ .arrow_right, 0x27 },
    .{ .arrow_down, 0x28 },
    .{ .context_menu, 0x5D },
    .{ .shift, 0x10 },
    .{ .shift_left, 0xA0 },
    .{ .shift_right, 0xA1 },
    .{ .control, 0x11 },
    .{ .control_left, 0xA2 },
    .{ .control_right, 0xA3 },
    .{ .alt, 0x12 },
    .{ .alt_left, 0xA4 },
    .{ .alt_right, 0xA5 },
    .{ .super_left, 0x5B },
    .{ .super_right, 0x5C },
    .{ .numpad_0, 0x60 },
    .{ .numpad_1, 0x61 },
    .{ .numpad_2, 0x62 },
    .{ .numpad_3, 0x63 },
    .{ .numpad_4, 0x64 },
    .{ .numpad_5, 0x65 },
    .{ .numpad_6, 0x66 },
    .{ .numpad_7, 0x67 },
    .{ .numpad_8, 0x68 },
    .{ .numpad_9, 0x69 },
    .{ .numpad_add, 0x6B },
    .{ .numpad_decimal, 0x6E },
    .{ .numpad_divide, 0x6F },
    .{ .numpad_multiply, 0x6A },
    .{ .numpad_separator, 0x6C },
    .{ .numpad_subtract, 0x6D },
    .{ .backslash, 0xDC },
    .{ .backtick, 0xC0 },
    .{ .bracket_left, 0xDB },
    .{ .bracket_right, 0xDD },
    .{ .comma, 0xBC },
    .{ .equal, 0xBB },
    .{ .intl_backslash, 0xE2 },
    .{ .minus, 0xBD },
    .{ .period, 0xBE },
    .{ .quote, 0xDE },
    .{ .semicolon, 0xBA },
    .{ .slash, 0xBF },
    .{ .browser_back, 0xA6 },
    .{ .browser_favorites, 0xAB },
    .{ .browser_forward, 0xA7 },
    .{ .browser_home, 0xAC },
    .{ .browser_refresh, 0xA8 },
    .{ .browser_search, 0xAA },
    .{ .browser_stop, 0xA9 },
    .{ .launch_application_1, 0xB6 },
    .{ .launch_application_2, 0xB7 },
    .{ .launch_mail, 0xB4 },
    .{ .launch_media, 0xB5 },
    .{ .media_next, 0xB0 },
    .{ .media_play_pause, 0xB3 },
    .{ .media_previous, 0xB1 },
    .{ .media_stop, 0xB2 },
    .{ .volume_down, 0xAE },
    .{ .volume_mute, 0xAD },
    .{ .volume_up, 0xAF },
    .{ .clear, 0x0C },
    .{ .execute, 0x2B },
    .{ .help, 0x2F },
    .{ .print, 0x2A },
    .{ .select, 0x29 },
    .{ .sleep, 0x5F },
};

const forward = build_forward();
const reverse = build_reverse();

comptime {
    assert(value_min == 0x01);
    assert(value_max == 0xFE);
    assert(value_dummy > value_max);
    assert(pairs.len == core.count - 2);
    assert_round_trip();
}

pub fn from_native(native: u8) ?Keycode {
    return forward[native];
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

fn build_reverse() [core.count]?u8 {
    @setEvalBranchQuota(table_size * 64);

    var result: [core.count]?u8 = @splat(null);

    for (pairs) |pair| {
        const index: usize = @intFromEnum(pair[0]);

        assert(result[index] == null);

        result[index] = pair[1];
    }

    return result;
}

fn assert_round_trip() void {
    @setEvalBranchQuota(table_size * 64);

    for (pairs) |pair| {
        const native = to_native(pair[0]) orelse unreachable;

        assert(native == pair[1]);
        assert(from_native(native) == pair[0]);
    }

    for (0..table_size) |index| {
        const native: u8 = @intCast(index);
        const mapped = from_native(native) orelse continue;

        assert(to_native(mapped) == native);
    }
}

const testing = std.testing;

test "keycode round trip for every mapped virtual key" {
    var native: u16 = 0;

    while (native < table_size) : (native += 1) {
        const mapped = from_native(@intCast(native)) orelse continue;

        try testing.expectEqual(@as(u8, @intCast(native)), to_native(mapped).?);
    }
}

test "unmapped virtual keys stay unmapped" {
    try testing.expect(from_native(0x00) == null);
    try testing.expect(from_native(0x07) == null);
    try testing.expect(from_native(value_dummy) == null);
}

test "named keys map to their documented virtual keys" {
    try testing.expectEqual(@as(u8, 0x70), to_native(.f1).?);
    try testing.expectEqual(@as(u8, 0x41), to_native(.a).?);
    try testing.expectEqual(@as(u8, 0x30), to_native(.digit_0).?);
    try testing.expectEqual(@as(u8, 0xA2), to_native(.control_left).?);
    try testing.expectEqual(@as(u8, 0x0D), to_native(.enter).?);
    try testing.expectEqual(@as(u8, 0x21), to_native(.page_up).?);
    try testing.expectEqual(@as(u8, 0x2C), to_native(.print_screen).?);
    try testing.expectEqual(@as(u8, 0x08), to_native(.backspace).?);
}

test "codes without a Windows analogue stay unmapped" {
    try testing.expect(to_native(.silent) == null);
    try testing.expect(to_native(.super) == null);
}

test "every other keycode has a virtual key" {
    inline for (@typeInfo(Keycode).@"enum".fields) |field| {
        const code: Keycode = @enumFromInt(field.value);

        if (code == .silent or code == .super) {
            continue;
        }

        try testing.expect(to_native(code) != null);
    }
}
