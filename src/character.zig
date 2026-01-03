const keycode = @import("keycode.zig");
const key_event = @import("event/key.zig");

const Key = key_event.Key;

pub fn is_whitespace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r';
}

pub fn from_key(key: *const Key) ?u8 {
    const value = key.value;

    if (value >= 'A' and value <= 'Z') {
        return if (key.is_shift_down()) value else value + 32;
    }

    if (value >= '0' and value <= '9') {
        return if (key.is_shift_down()) shifted_digit(value) else value;
    }

    return switch (value) {
        keycode.oem_1 => if (key.is_shift_down()) ':' else ';',
        keycode.oem_2 => if (key.is_shift_down()) '?' else '/',
        keycode.oem_3 => if (key.is_shift_down()) '~' else '`',
        keycode.oem_4 => if (key.is_shift_down()) '{' else '[',
        keycode.oem_5 => if (key.is_shift_down()) '|' else '\\',
        keycode.oem_6 => if (key.is_shift_down()) '}' else ']',
        keycode.oem_7 => if (key.is_shift_down()) '"' else '\'',
        keycode.oem_plus => if (key.is_shift_down()) '+' else '=',
        keycode.oem_comma => if (key.is_shift_down()) '<' else ',',
        keycode.oem_minus => if (key.is_shift_down()) '_' else '-',
        keycode.oem_period => if (key.is_shift_down()) '>' else '.',
        else => null,
    };
}

pub fn shifted_digit(value: u8) u8 {
    return switch (value) {
        '1' => '!',
        '2' => '@',
        '3' => '#',
        '4' => '$',
        '5' => '%',
        '6' => '^',
        '7' => '&',
        '8' => '*',
        '9' => '(',
        '0' => ')',
        else => value,
    };
}
