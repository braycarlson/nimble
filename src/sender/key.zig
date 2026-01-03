const std = @import("std");

const w32 = @import("win32").everything;

const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");

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
        std.debug.assert(value >= keycode.value_min or value == keycode.value_dummy);
        std.debug.assert(value <= keycode.value_max or value == keycode.value_dummy);
        std.debug.assert(flag <= (flag_extended | flag_keyup));

        const scan: u16 = @truncate(w32.MapVirtualKeyW(value, 0));

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

        std.debug.assert(result.type == type_keyboard);
        std.debug.assert(result.data.key.extra == marker_injected);

        return result;
    }

    pub fn down(value: u8) Input {
        std.debug.assert(value >= keycode.value_min or value == keycode.value_dummy);
        std.debug.assert(value <= keycode.value_max or value == keycode.value_dummy);

        const result = init(value, 0);

        std.debug.assert(result.data.key.flag == 0);

        return result;
    }

    pub fn up(value: u8) Input {
        std.debug.assert(value >= keycode.value_min or value == keycode.value_dummy);
        std.debug.assert(value <= keycode.value_max or value == keycode.value_dummy);

        const result = init(value, flag_keyup);

        std.debug.assert(result.data.key.flag == flag_keyup);

        return result;
    }
};

fn append_modifiers_down(
    input: *[capacity_input]Input,
    start: u8,
    modifiers: *const modifier.Set,
) u8 {
    std.debug.assert(start < capacity_input);
    std.debug.assert(modifiers.flags <= modifier.flag_all);

    var length = start;
    const array = modifiers.to_array();

    var i: u8 = 0;

    while (i < modifier.kind_count) : (i += 1) {
        std.debug.assert(i < modifier.kind_count);

        if (array[i]) |kind| {
            std.debug.assert(length < capacity_input);

            input[length] = Input.down(kind.to_keycode());
            length += 1;
        }
    }

    std.debug.assert(length >= start);
    std.debug.assert(length <= start + modifier.kind_count);

    return length;
}

fn append_modifiers_up(
    input: *[capacity_input]Input,
    start: u8,
    modifiers: *const modifier.Set,
) u8 {
    std.debug.assert(start <= capacity_input);
    std.debug.assert(modifiers.flags <= modifier.flag_all);

    var length = start;
    const array = modifiers.to_array();

    var i: u8 = modifier.kind_count;

    while (i > 0) : (i -= 1) {
        std.debug.assert(i >= 1);
        std.debug.assert(i <= modifier.kind_count);

        const index = i - 1;

        std.debug.assert(index < modifier.kind_count);

        if (array[index]) |kind| {
            std.debug.assert(length < capacity_input);

            input[length] = Input.up(kind.to_keycode());
            length += 1;
        }
    }

    std.debug.assert(length >= start);
    std.debug.assert(length <= capacity_input);

    return length;
}

fn append_press(input: *[capacity_input]Input, start: u8, value: u8) u8 {
    std.debug.assert(start < capacity_input - 1);
    std.debug.assert(value >= keycode.value_min);
    std.debug.assert(value <= keycode.value_max);

    input[start] = Input.down(value);
    input[start + 1] = Input.up(value);

    const result = start + 2;

    std.debug.assert(result == start + 2);
    std.debug.assert(result <= capacity_input);

    return result;
}

pub fn combination(modifiers: *const modifier.Set, value: u8) bool {
    std.debug.assert(value >= keycode.value_min);
    std.debug.assert(value <= keycode.value_max);
    std.debug.assert(modifiers.flags <= modifier.flag_all);

    var input: [capacity_input]Input = undefined;
    var length: u8 = 0;

    length = append_modifiers_down(&input, length, modifiers);

    std.debug.assert(length <= modifier.kind_count);

    length = append_press(&input, length, value);

    std.debug.assert(length <= modifier.kind_count + 2);

    length = append_modifiers_up(&input, length, modifiers);

    std.debug.assert(length >= 1);
    std.debug.assert(length <= capacity_input);

    const sent = send(input[0..length]);
    const result = sent == length;

    std.debug.assert(sent <= length);

    return result;
}

pub fn dummy() bool {
    var input = [2]Input{
        Input.down(keycode.value_dummy),
        Input.up(keycode.value_dummy),
    };

    const sent = send(&input);
    const result = sent == 2;

    std.debug.assert(sent <= 2);

    return result;
}

pub fn key_down(value: u8) bool {
    std.debug.assert(value >= keycode.value_min);
    std.debug.assert(value <= keycode.value_max);

    var input = [1]Input{Input.down(value)};

    const sent = send(&input);
    const result = sent == 1;

    std.debug.assert(sent <= 1);

    return result;
}

pub fn key_up(value: u8) bool {
    std.debug.assert(value >= keycode.value_min);
    std.debug.assert(value <= keycode.value_max);

    var input = [1]Input{Input.up(value)};

    const sent = send(&input);
    const result = sent == 1;

    std.debug.assert(sent <= 1);

    return result;
}

pub fn press(value: u8) bool {
    std.debug.assert(value >= keycode.value_min);
    std.debug.assert(value <= keycode.value_max);

    var input = [2]Input{
        Input.down(value),
        Input.up(value),
    };

    const sent = send(&input);
    const result = sent == 2;

    std.debug.assert(sent <= 2);

    return result;
}

pub fn release_modifiers(modifiers: *const modifier.Set) bool {
    std.debug.assert(modifiers.flags <= modifier.flag_all);

    var input: [modifier.kind_count]Input = undefined;
    var length: u8 = 0;

    const array = modifiers.to_array();

    var i: u8 = 0;

    while (i < modifier.kind_count) : (i += 1) {
        std.debug.assert(i < modifier.kind_count);
        std.debug.assert(length <= i);

        if (array[i]) |kind| {
            std.debug.assert(length < modifier.kind_count);

            input[length] = Input.up(kind.to_keycode());
            length += 1;
        }
    }

    std.debug.assert(length <= modifier.kind_count);

    if (length == 0) {
        return true;
    }

    std.debug.assert(length >= 1);

    const sent = send(input[0..length]);
    const result = sent == length;

    std.debug.assert(sent <= length);

    return result;
}

pub fn send(input: []Input) u32 {
    std.debug.assert(input.len >= 1);
    std.debug.assert(input.len <= capacity_input);

    const count: u32 = @intCast(input.len);
    const size: i32 = @sizeOf(Input);

    std.debug.assert(count >= 1);
    std.debug.assert(count <= capacity_input);

    const result = w32.SendInput(count, @ptrCast(input.ptr), size);

    std.debug.assert(result <= count);

    return result;
}

pub fn suppress(value: u8) bool {
    std.debug.assert(value >= keycode.value_min);
    std.debug.assert(value <= keycode.value_max);

    var input = [3]Input{
        Input.down(keycode.value_dummy),
        Input.up(keycode.value_dummy),
        Input.init(value, flag_extended | flag_keyup),
    };

    const sent = send(&input);
    const result = sent == 3;

    std.debug.assert(sent <= 3);

    return result;
}
