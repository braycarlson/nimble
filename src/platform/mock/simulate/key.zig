const std = @import("std");

const keycode = @import("../../../keycode.zig");
const modifier = @import("../../../modifier.zig");
const record = @import("../record.zig");
const state = @import("../state.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const capacity_input: u8 = 16;

comptime {
    assert(capacity_input >= 4);
}

pub fn press(code: Keycode) bool {
    record.push(.{ .kind = .key_press, .code = code });

    return true;
}

pub fn key_down(code: Keycode) bool {
    state.set_down(code);
    record.push(.{ .kind = .key_down, .code = code, .down = true });

    return true;
}

pub fn key_up(code: Keycode) bool {
    state.set_up(code);
    record.push(.{ .kind = .key_up, .code = code, .down = false });

    return true;
}

pub fn combination(modifiers: *const modifier.Set, code: Keycode) bool {
    assert(modifiers.flags <= modifier.flag_all);

    record.push(.{ .kind = .key_combination, .code = code, .modifiers = modifiers.* });

    return true;
}

pub fn dummy() bool {
    record.push(.{ .kind = .key_dummy });

    return true;
}

pub fn suppress(code: Keycode) bool {
    record.push(.{ .kind = .key_up, .code = code, .down = false });

    return true;
}

pub fn release_modifiers(modifiers: *const modifier.Set) bool {
    assert(modifiers.flags <= modifier.flag_all);

    const array = modifiers.to_array();
    var index: u8 = 0;

    while (index < modifier.kind_count) : (index += 1) {
        if (array[index]) |kind| {
            _ = key_up(kind.to_keycode());
        }
    }

    assert(index == modifier.kind_count);

    return true;
}
