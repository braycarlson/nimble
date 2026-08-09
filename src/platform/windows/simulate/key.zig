const std = @import("std");

const keycode = @import("../../../keycode.zig");
const mapping = @import("../keycode.zig");
const modifier = @import("../../../modifier.zig");
const win32 = @import("../win32.zig");

const assert = std.debug.assert;
const Keycode = keycode.Keycode;

pub const marker_injected: u64 = 0x101;
pub const capacity_input: u8 = 16;

const flag_extended: u32 = 0x0001;
const flag_keyup: u32 = 0x0002;
const type_keyboard: u32 = 1;

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
};

fn append_modifiers_down(
    input: *[capacity_input]Input,
    start: u8,
    modifiers: *const modifier.Set,
) u8 {
    assert(start < capacity_input);
    assert(modifiers.flags <= modifier.flag_all);

    var length = start;
    const array = modifiers.to_array();

    var i: u8 = 0;

    while (i < modifier.kind_count) : (i += 1) {
        if (array[i]) |kind| {
            const native = mapping.to_native(kind.to_keycode()) orelse continue;

            assert(length < capacity_input);

            input[length] = Input.down(native);
            length += 1;
        }
    }

    assert(length >= start);
    assert(length <= start + modifier.kind_count);

    return length;
}

fn append_modifiers_up(
    input: *[capacity_input]Input,
    start: u8,
    modifiers: *const modifier.Set,
) u8 {
    assert(start <= capacity_input);
    assert(modifiers.flags <= modifier.flag_all);

    var length = start;
    const array = modifiers.to_array();

    var i: u8 = modifier.kind_count;

    while (i > 0) : (i -= 1) {
        assert(i >= 1);
        assert(i <= modifier.kind_count);

        const index = i - 1;

        assert(index < modifier.kind_count);

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

    assert(modifiers.flags <= modifier.flag_all);

    var input: [capacity_input]Input = undefined;
    var length: u8 = 0;

    length = append_modifiers_down(&input, length, modifiers);

    assert(length <= modifier.kind_count);

    length = append_press(&input, length, value);

    assert(length <= modifier.kind_count + 2);

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

pub fn release_modifiers(modifiers: *const modifier.Set) bool {
    assert(modifiers.flags <= modifier.flag_all);

    var input: [modifier.kind_count]Input = undefined;
    var length: u8 = 0;

    const array = modifiers.to_array();

    var i: u8 = 0;

    while (i < modifier.kind_count) : (i += 1) {
        assert(length <= i);

        if (array[i]) |kind| {
            const native = mapping.to_native(kind.to_keycode()) orelse continue;

            assert(length < modifier.kind_count);

            input[length] = Input.up(native);
            length += 1;
        }
    }

    assert(length <= modifier.kind_count);

    if (length == 0) {
        return true;
    }

    assert(length >= 1);

    const sent = send(input[0..length]);
    const result = sent == length;

    assert(sent <= length);

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
