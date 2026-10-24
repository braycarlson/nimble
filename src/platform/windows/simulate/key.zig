const std = @import("std");

const keycode = @import("../../../keycode.zig");
const mapping = @import("../keycode.zig");
const modifier = @import("../../../modifier.zig");
const win32 = @import("../win32.zig");

const assert = std.debug.assert;
const Keycode = keycode.Keycode;

pub const marker_injected: u64 = 0x101;
const capacity_input: u8 = 16;
const flag_extended: u32 = 0x0001;
const flag_keyup: u32 = 0x0002;
const flag_unicode: u32 = 0x0004;
const type_keyboard: u32 = 1;

const modifier_codes = [_]Keycode{
    .control_left,
    .control_right,
    .alt_left,
    .alt_right,
    .shift_left,
    .shift_right,
    .super_left,
    .super_right,
};

comptime {
    assert(capacity_input >= modifier_codes.len + 2);
}

pub const Input = extern struct {
    type: u32,
    padding: u32 = 0,
    data: extern union {
        key: KeyData,
        padding: [32]u8,
    },

    const KeyData = extern struct {
        keycode: u16,
        scan: u16,
        flag: u32,
        time: u32,
        extra: u64,
    };

    pub fn init(value: u8, flag: u32) Input {
        assert(flag <= (flag_extended | flag_keyup));

        const scan: u16 = @truncate(win32.MapVirtualKeyW(value, 0));

        const result = Input{
            .type = type_keyboard,
            .data = .{
                .key = KeyData{
                    .keycode = value,
                    .scan = scan,
                    .flag = flag,
                    .time = 0,
                    .extra = marker_injected,
                },
            },
        };

        assert(result.type == type_keyboard);
        assert(result.data.key.extra == marker_injected);

        return result;
    }

    pub fn down(value: u8) Input {
        const result = init(value, 0);

        assert(result.data.key.flag == 0);

        return result;
    }

    pub fn up(value: u8) Input {
        const result = init(value, flag_keyup);

        assert(result.data.key.flag == flag_keyup);

        return result;
    }

    pub fn character(unit: u16, released: bool) Input {
        const flag = if (released) flag_unicode | flag_keyup else flag_unicode;

        const result = Input{
            .type = type_keyboard,
            .data = .{
                .key = KeyData{
                    .keycode = 0,
                    .scan = unit,
                    .flag = flag,
                    .time = 0,
                    .extra = marker_injected,
                },
            },
        };

        assert(result.data.key.keycode == 0);
        assert(result.data.key.extra == marker_injected);

        return result;
    }
};

fn append_modifiers_down(
    input: *[capacity_input]Input,
    start: u8,
    modifiers: *const modifier.Set,
) u8 {
    assert(start < capacity_input);

    var length = start;
    const array = modifiers.to_array();

    var i: u8 = 0;

    while (i < modifier.Set.kind_count) : (i += 1) {
        if (array[i]) |kind| {
            const native = mapping.to_native(kind.to_keycode()) orelse continue;

            assert(length < capacity_input);

            input[length] = Input.down(native);
            length += 1;
        }
    }

    assert(length >= start);
    assert(length <= start + modifier.Set.kind_count);

    return length;
}

fn append_modifiers_up(
    input: *[capacity_input]Input,
    start: u8,
    modifiers: *const modifier.Set,
) u8 {
    assert(start <= capacity_input);

    var length = start;
    const array = modifiers.to_array();

    var i: u8 = modifier.Set.kind_count;

    while (i > 0) : (i -= 1) {
        assert(i >= 1);
        assert(i <= modifier.Set.kind_count);

        const index = i - 1;

        assert(index < modifier.Set.kind_count);

        if (array[index]) |kind| {
            const native = mapping.to_native(kind.to_keycode()) orelse continue;

            assert(length < capacity_input);

            input[length] = Input.up(native);
            length += 1;
        }
    }

    assert(length >= start);
    assert(length <= capacity_input);

    return length;
}

fn append_press(input: *[capacity_input]Input, start: u8, value: u8) u8 {
    assert(start < capacity_input - 1);

    input[start] = Input.down(value);

    input[start + 1] = Input.up(value);

    const result = start + 2;

    assert(result == start + 2);
    assert(result <= capacity_input);

    return result;
}

pub fn combination(modifiers: *const modifier.Set, code: Keycode) bool {
    const value = mapping.to_native(code) orelse return false;

    var input: [capacity_input]Input = undefined;
    var length: u8 = 0;

    length = append_modifiers_down(&input, length, modifiers);

    assert(length <= modifier.Set.kind_count);

    length = append_press(&input, length, value);

    assert(length <= modifier.Set.kind_count + 2);

    length = append_modifiers_up(&input, length, modifiers);

    assert(length >= 1);
    assert(length <= capacity_input);

    const sent = send(input[0..length]);
    const result = sent == length;

    assert(sent <= length);

    return result;
}

pub fn dummy() bool {
    var input = [2]Input{
        Input.down(mapping.value_dummy),
        Input.up(mapping.value_dummy),
    };

    const sent = send(&input);
    const result = sent == 2;

    assert(sent <= 2);

    return result;
}

pub fn key_down(code: Keycode) bool {
    const value = mapping.to_native(code) orelse return false;

    var input = [1]Input{Input.down(value)};

    const sent = send(&input);
    const result = sent == 1;

    assert(sent <= 1);

    return result;
}

pub fn key_up(code: Keycode) bool {
    const value = mapping.to_native(code) orelse return false;

    var input = [1]Input{Input.up(value)};

    const sent = send(&input);
    const result = sent == 1;

    assert(sent <= 1);

    return result;
}

pub fn press(code: Keycode) bool {
    const value = mapping.to_native(code) orelse return false;

    var input = [2]Input{
        Input.down(value),
        Input.up(value),
    };

    const sent = send(&input);
    const result = sent == 2;

    assert(sent <= 2);

    return result;
}

pub fn send(input: []Input) u32 {
    assert(input.len >= 1);
    assert(input.len <= capacity_input);

    const count: u32 = @intCast(input.len);
    const size: i32 = @sizeOf(Input);

    assert(count >= 1);
    assert(count <= capacity_input);

    const result = win32.SendInput(count, @ptrCast(input.ptr), size);

    assert(result <= count);

    return result;
}

pub fn suppress(code: Keycode) bool {
    const value = mapping.to_native(code) orelse return false;

    var input = [3]Input{
        Input.down(mapping.value_dummy),
        Input.up(mapping.value_dummy),
        Input.init(value, flag_extended | flag_keyup),
    };

    const sent = send(&input);
    const result = sent == 3;

    assert(sent <= 3);

    return result;
}

pub fn release_modifiers() bool {
    var input: [capacity_input]Input = undefined;
    var length: u8 = 0;

    for (modifier_codes) |code| {
        const value = mapping.to_native(code) orelse continue;
        if (win32.GetAsyncKeyState(@intCast(value)) >= 0) continue;

        if (length == 0) {
            input[0] = Input.down(mapping.value_dummy);
            input[1] = Input.up(mapping.value_dummy);
            length = 2;
        }

        input[length] = Input.up(value);
        length += 1;
    }

    assert(length <= modifier_codes.len + 2);

    if (length == 0) return true;

    const sent = send(input[0..length]);

    assert(sent <= length);

    return sent == length;
}

pub fn unicode(codepoint: u21) bool {
    var units: [2]u16 = undefined;

    const unit_count = utf16_units(codepoint, &units);

    var input: [4]Input = undefined;
    var length: u8 = 0;

    for (units[0..unit_count]) |unit| {
        input[length] = Input.character(unit, false);

        input[length + 1] = Input.character(unit, true);
        length += 2;
    }

    assert(length == unit_count * 2);

    const sent = send(input[0..length]);

    assert(sent <= length);

    return sent == length;
}

fn utf16_units(codepoint: u21, units: *[2]u16) u8 {
    assert(codepoint <= 0x10FFFF);
    assert(codepoint < 0xD800 or codepoint > 0xDFFF);

    if (codepoint <= 0xFFFF) {
        units[0] = @intCast(codepoint);

        return 1;
    }

    const adjusted: u20 = @intCast(codepoint - 0x10000);

    units[0] = 0xD800 + @as(u16, @intCast(adjusted >> 10));
    units[1] = 0xDC00 + @as(u16, @intCast(adjusted & 0x3FF));

    return 2;
}

const testing = std.testing;

test "a character input carries its unit and the unicode flag" {
    const down = Input.character(0x00E9, false);
    const up = Input.character(0x00E9, true);

    try testing.expectEqual(@as(u16, 0), down.data.key.keycode);
    try testing.expectEqual(@as(u16, 0x00E9), down.data.key.scan);
    try testing.expectEqual(flag_unicode, down.data.key.flag);
    try testing.expectEqual(flag_unicode | flag_keyup, up.data.key.flag);
}

test "a codepoint splits into the units utf16 encodes it as" {
    const samples = [_]u21{ 'A', 0x00E9, 0xFFFD, 0x1F600, 0x10FFFF };

    for (samples) |codepoint| {
        var encoded: [4]u8 = undefined;
        var expected: [2]u16 = undefined;
        var actual: [2]u16 = undefined;

        const byte_count = try std.unicode.utf8Encode(codepoint, &encoded);
        const expected_count = try std.unicode.utf8ToUtf16Le(&expected, encoded[0..byte_count]);
        const actual_count = utf16_units(codepoint, &actual);

        try testing.expectEqual(expected_count, @as(usize, actual_count));
        try testing.expectEqualSlices(u16, expected[0..expected_count], actual[0..actual_count]);
    }
}
