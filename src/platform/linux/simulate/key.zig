const std = @import("std");

const keycode = @import("../../../keycode.zig");
const modifier = @import("../../../modifier.zig");
const runtime = @import("../runtime.zig");
const uinput = @import("../uinput.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const capacity_input: u8 = 16;

comptime {
    assert(capacity_input >= 4);
}

fn device() *uinput.Device {
    return &runtime.current().keyboard_out;
}

pub fn is_open() bool {
    return device().is_open();
}

pub fn emit(code: Keycode, down: bool) bool {
    const out = device();

    if (!out.is_open()) {
        return false;
    }

    out.key(code, down) catch return false;

    return true;
}

pub fn key_down(code: Keycode) bool {
    return emit(code, true);
}

pub fn key_up(code: Keycode) bool {
    return emit(code, false);
}

pub fn press(code: Keycode) bool {
    const down = emit(code, true);
    const up = emit(code, false);

    return down and up;
}

pub fn suppress(code: Keycode) bool {
    return emit(code, false);
}

pub fn dummy() bool {
    return device().is_open();
}

pub fn combination(modifiers: *const modifier.Set, code: Keycode) bool {
    assert(modifiers.flags <= modifier.flag_all);

    const array = modifiers.to_array();
    var index: u8 = 0;

    while (index < modifier.kind_count) : (index += 1) {
        if (array[index]) |kind| {
            _ = emit(kind.to_keycode(), true);
        }
    }

    const pressed = press(code);

    var back: u8 = modifier.kind_count;

    while (back > 0) : (back -= 1) {
        if (array[back - 1]) |kind| {
            _ = emit(kind.to_keycode(), false);
        }
    }

    assert(back == 0);

    return pressed;
}

pub fn release_modifiers(modifiers: *const modifier.Set) bool {
    assert(modifiers.flags <= modifier.flag_all);

    const array = modifiers.to_array();
    var index: u8 = 0;

    while (index < modifier.kind_count) : (index += 1) {
        if (array[index]) |kind| {
            _ = emit(kind.to_keycode(), false);
        }
    }

    assert(index == modifier.kind_count);

    return true;
}

const testing = std.testing;

test "synthesis is inert until the runtime opens its device" {
    try testing.expect(!runtime.is_open());
    try testing.expect(!is_open());
    try testing.expect(!press(.a));
    try testing.expect(!key_down(.control_left));
    try testing.expect(!dummy());
}
