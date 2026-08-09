const std = @import("std");

const keycode = @import("keycode.zig");
const modifier = @import("modifier.zig");
const platform = @import("platform.zig");

const assert = std.debug.assert;
const Keycode = keycode.Keycode;

pub const flag_count: u32 = 2;
pub const bits_per_flag: u8 = 128;
pub const key_count_max: u32 = 256;
pub const active_count_max: u8 = 32;

pub const Keyboard = struct {
    flags: [flag_count]u128 = .{ 0, 0 },
    keys_active: [active_count_max]Keycode = @splat(.silent),
    active_count: u8 = 0,

    pub fn init() Keyboard {
        const result = Keyboard{};

        assert(result.active_count == 0);
        assert(result.flags[0] == 0);
        assert(result.flags[1] == 0);

        return result;
    }

    pub fn is_valid(keyboard: *const Keyboard) bool {
        return keyboard.active_count <= active_count_max;
    }

    pub fn clear(keyboard: *Keyboard) void {
        assert(keyboard.is_valid());

        keyboard.flags = .{ 0, 0 };
        keyboard.active_count = 0;

        assert(keyboard.active_count == 0);
        assert(keyboard.flags[0] == 0);
        assert(keyboard.flags[1] == 0);
    }

    pub fn count(keyboard: *const Keyboard) u32 {
        assert(keyboard.is_valid());
        assert(keyboard.active_count <= active_count_max);

        return keyboard.active_count;
    }

    pub fn get_modifiers(keyboard: *const Keyboard) modifier.Set {
        assert(keyboard.is_valid());

        const result = modifier.Set.from(.{
            .ctrl = keyboard.is_ctrl_down(),
            .alt = keyboard.is_alt_down(),
            .shift = keyboard.is_shift_down(),
            .win = keyboard.is_win_down(),
        });

        assert(result.flags <= modifier.flag_all);

        return result;
    }

    pub fn is_alt_down(keyboard: *const Keyboard) bool {
        assert(keyboard.is_valid());

        return keyboard.is_down(Keycode.alt);
    }

    pub fn is_ctrl_down(keyboard: *const Keyboard) bool {
        assert(keyboard.is_valid());

        return keyboard.is_down(Keycode.control);
    }

    pub fn is_down(keyboard: *const Keyboard, value: Keycode) bool {
        assert(keyboard.is_valid());

        const index: u32 = @intFromEnum(value) / bits_per_flag;
        const position: u7 = @truncate(@intFromEnum(value) % bits_per_flag);

        assert(index < flag_count);

        return (keyboard.flags[index] & (@as(u128, 1) << position)) != 0;
    }

    pub fn is_shift_down(keyboard: *const Keyboard) bool {
        assert(keyboard.is_valid());

        return keyboard.is_down(Keycode.shift);
    }

    pub fn is_win_down(keyboard: *const Keyboard) bool {
        assert(keyboard.is_valid());

        return keyboard.is_down(Keycode.super);
    }

    pub fn keydown(keyboard: *Keyboard, value: Keycode) void {
        assert(keyboard.is_valid());

        if (!keyboard.is_down(value)) {
            const tracked = keyboard.add_active_key(value);

            if (!tracked) {
                assert(keyboard.active_count == active_count_max);
                assert(!keyboard.is_down(value));

                return;
            }
        }

        keyboard.set_bit(value);
        keyboard.update_generic_modifier_down(value);

        assert(keyboard.is_down(value));
        assert(keyboard.is_valid());
    }

    pub fn keyup(keyboard: *Keyboard, value: Keycode) void {
        assert(keyboard.is_valid());

        keyboard.clear_bit(value);
        keyboard.remove_active_key(value);
        keyboard.update_generic_modifier_up(value);

        assert(!keyboard.is_down(value));
        assert(keyboard.is_valid());
    }

    pub fn sync(keyboard: *Keyboard) void {
        assert(keyboard.is_valid());

        if (keyboard.active_count == 0) {
            return;
        }

        const snapshot = platform.backend.state.capture();

        var index: u8 = 0;
        var iteration: u8 = 0;

        while (iteration < active_count_max) : (iteration += 1) {
            if (index >= keyboard.active_count) {
                break;
            }

            assert(index < active_count_max);

            const key = keyboard.keys_active[index];

            const down = platform.backend.state.is_key_down_at(&snapshot, key);

            if (!down) {
                keyboard.keyup(key);
            } else {
                index += 1;
            }
        }

        assert(keyboard.is_valid());
    }

    fn add_active_key(keyboard: *Keyboard, value: Keycode) bool {
        assert(keyboard.is_valid());

        if (keyboard.active_count >= active_count_max) {
            return false;
        }

        assert(keyboard.active_count < active_count_max);

        keyboard.keys_active[keyboard.active_count] = value;
        keyboard.active_count += 1;

        assert(keyboard.active_count <= active_count_max);
        assert(keyboard.keys_active[keyboard.active_count - 1] == value);

        return true;
    }

    fn clear_bit(keyboard: *Keyboard, value: Keycode) void {
        assert(keyboard.is_valid());

        const index: u32 = @intFromEnum(value) / bits_per_flag;
        const position: u7 = @truncate(@intFromEnum(value) % bits_per_flag);

        assert(index < flag_count);

        keyboard.flags[index] &= ~(@as(u128, 1) << position);
    }

    fn remove_active_key(keyboard: *Keyboard, value: Keycode) void {
        assert(keyboard.is_valid());

        const found_index = keyboard.find_active_key_index(value);

        if (found_index == null) {
            return;
        }

        const index = found_index.?;

        assert(index < keyboard.active_count);
        assert(keyboard.active_count >= 1);

        keyboard.active_count -= 1;

        if (index < keyboard.active_count) {
            keyboard.keys_active[index] = keyboard.keys_active[keyboard.active_count];
        }

        assert(keyboard.active_count <= active_count_max);
    }

    fn find_active_key_index(keyboard: *const Keyboard, value: Keycode) ?u8 {
        var i: u8 = 0;

        while (i < keyboard.active_count) : (i += 1) {
            assert(i < active_count_max);

            if (keyboard.keys_active[i] == value) {
                return i;
            }
        }

        return null;
    }

    fn set_bit(keyboard: *Keyboard, value: Keycode) void {
        assert(keyboard.is_valid());

        const index: u32 = @intFromEnum(value) / bits_per_flag;
        const position: u7 = @truncate(@intFromEnum(value) % bits_per_flag);

        assert(index < flag_count);

        keyboard.flags[index] |= @as(u128, 1) << position;
    }

    fn update_generic_modifier_down(keyboard: *Keyboard, value: Keycode) void {
        assert(keyboard.is_valid());

        switch (value) {
            .shift_left, .shift_right => keyboard.set_bit(Keycode.shift),
            .control_left, .control_right => keyboard.set_bit(.control),
            .alt_left, .alt_right => keyboard.set_bit(.alt),
            .super_left, .super_right => keyboard.set_bit(.super),
            else => {},
        }
    }

    fn update_generic_modifier_up(keyboard: *Keyboard, value: Keycode) void {
        assert(keyboard.is_valid());

        switch (value) {
            .shift_left, .shift_right => keyboard.clear_shift_if_both_up(),
            .control_left, .control_right => keyboard.clear_ctrl_if_both_up(),
            .alt_left, .alt_right => keyboard.clear_alt_if_both_up(),
            .super_left, .super_right => keyboard.clear_super_if_both_up(),
            else => {},
        }
    }

    fn clear_shift_if_both_up(keyboard: *Keyboard) void {
        const left_down = keyboard.is_down(Keycode.shift_left);
        const right_down = keyboard.is_down(Keycode.shift_right);

        if (!left_down and !right_down) {
            keyboard.clear_bit(Keycode.shift);
        }
    }

    fn clear_ctrl_if_both_up(keyboard: *Keyboard) void {
        const left_down = keyboard.is_down(Keycode.control_left);
        const right_down = keyboard.is_down(Keycode.control_right);

        if (!left_down and !right_down) {
            keyboard.clear_bit(Keycode.control);
        }
    }

    fn clear_alt_if_both_up(keyboard: *Keyboard) void {
        const left_down = keyboard.is_down(Keycode.alt_left);
        const right_down = keyboard.is_down(Keycode.alt_right);

        if (!left_down and !right_down) {
            keyboard.clear_bit(Keycode.alt);
        }
    }

    fn clear_super_if_both_up(keyboard: *Keyboard) void {
        const left_down = keyboard.is_down(Keycode.super_left);
        const right_down = keyboard.is_down(Keycode.super_right);

        if (!left_down and !right_down) {
            keyboard.clear_bit(Keycode.super);
        }
    }
};

const testing = std.testing;

test "a fresh keyboard state holds no keys" {
    const keyboard = Keyboard.init();

    try testing.expect(keyboard.is_valid());
    try testing.expectEqual(@as(u32, 0), keyboard.count());
}

test "a pressed key is held until it is released" {
    var keyboard = Keyboard.init();

    keyboard.keydown(.a);
    try testing.expect(keyboard.is_down(.a));
    try testing.expectEqual(@as(u32, 1), keyboard.count());

    keyboard.keyup(.a);
    try testing.expect(!keyboard.is_down(.a));
    try testing.expectEqual(@as(u32, 0), keyboard.count());
}

test "a keyboard state tracks the modifiers held" {
    var keyboard = Keyboard.init();

    keyboard.keydown(Keycode.control_left);
    try testing.expect(keyboard.is_ctrl_down());
    try testing.expect(keyboard.is_down(Keycode.control));

    keyboard.keydown(Keycode.shift_left);
    try testing.expect(keyboard.is_shift_down());

    keyboard.keyup(Keycode.control_left);
    try testing.expect(!keyboard.is_ctrl_down());
    try testing.expect(!keyboard.is_down(Keycode.control));
}

test "a keyboard state tracks left and right modifiers apart" {
    var keyboard = Keyboard.init();

    keyboard.keydown(Keycode.control_left);
    keyboard.keydown(Keycode.control_right);
    try testing.expect(keyboard.is_ctrl_down());

    keyboard.keyup(Keycode.control_left);
    try testing.expect(keyboard.is_ctrl_down());

    keyboard.keyup(Keycode.control_right);
    try testing.expect(!keyboard.is_ctrl_down());
}

test "clearing a keyboard state releases every key" {
    var keyboard = Keyboard.init();

    keyboard.keydown(.a);
    keyboard.keydown(.b);
    keyboard.keydown(Keycode.control_left);

    keyboard.clear();

    try testing.expect(keyboard.is_valid());
    try testing.expectEqual(@as(u32, 0), keyboard.count());
    try testing.expect(!keyboard.is_down(.a));
    try testing.expect(!keyboard.is_ctrl_down());
}

test "a keyboard state reports the modifiers held" {
    var keyboard = Keyboard.init();

    keyboard.keydown(Keycode.control_left);
    keyboard.keydown(Keycode.alt_left);

    const modifiers = keyboard.get_modifiers();

    try testing.expect(modifiers.ctrl());
    try testing.expect(modifiers.alt());
    try testing.expect(!modifiers.shift());
    try testing.expect(!modifiers.win());
}

test "a keyboard state reports the left win key" {
    var keyboard = Keyboard.init();

    try testing.expect(!keyboard.is_win_down());

    keyboard.keydown(Keycode.super_left);
    try testing.expect(keyboard.is_win_down());

    keyboard.keyup(Keycode.super_left);
    try testing.expect(!keyboard.is_win_down());
}

test "a keyboard state reports the right win key" {
    var keyboard = Keyboard.init();

    keyboard.keydown(Keycode.super_right);
    try testing.expect(keyboard.is_win_down());

    keyboard.keyup(Keycode.super_right);
    try testing.expect(!keyboard.is_win_down());
}

test "a keyboard state reports both win keys at once" {
    var keyboard = Keyboard.init();

    keyboard.keydown(Keycode.super_left);
    keyboard.keydown(Keycode.super_right);
    try testing.expect(keyboard.is_win_down());

    keyboard.keyup(Keycode.super_left);
    try testing.expect(keyboard.is_win_down());

    keyboard.keyup(Keycode.super_right);
    try testing.expect(!keyboard.is_win_down());
}

test "a keyboard state reports either alt key" {
    var keyboard = Keyboard.init();

    keyboard.keydown(Keycode.alt_left);
    try testing.expect(keyboard.is_alt_down());
    try testing.expect(keyboard.is_down(Keycode.alt));

    keyboard.keyup(Keycode.alt_left);
    try testing.expect(!keyboard.is_alt_down());

    keyboard.keydown(Keycode.alt_right);
    try testing.expect(keyboard.is_alt_down());
}

test "a keyboard state reports either shift key" {
    var keyboard = Keyboard.init();

    keyboard.keydown(Keycode.shift_left);
    try testing.expect(keyboard.is_shift_down());
    try testing.expect(keyboard.is_down(Keycode.shift));

    keyboard.keyup(Keycode.shift_left);
    try testing.expect(!keyboard.is_shift_down());

    keyboard.keydown(Keycode.shift_right);
    try testing.expect(keyboard.is_shift_down());
}

test "a keyboard state holds several keys at once" {
    var keyboard = Keyboard.init();

    keyboard.keydown(.a);
    keyboard.keydown(.b);
    keyboard.keydown(.c);

    try testing.expectEqual(@as(u32, 3), keyboard.count());
    try testing.expect(keyboard.is_down(.a));
    try testing.expect(keyboard.is_down(.b));
    try testing.expect(keyboard.is_down(.c));
    try testing.expect(!keyboard.is_down(.d));

    keyboard.keyup(.b);

    try testing.expectEqual(@as(u32, 2), keyboard.count());
    try testing.expect(keyboard.is_down(.a));
    try testing.expect(!keyboard.is_down(.b));
    try testing.expect(keyboard.is_down(.c));
}

test "pressing a held key again leaves the state alone" {
    var keyboard = Keyboard.init();

    keyboard.keydown(.a);
    keyboard.keydown(.a);

    try testing.expectEqual(@as(u32, 1), keyboard.count());
    try testing.expect(keyboard.is_down(.a));
}

test "releasing a key that is not held leaves the state alone" {
    var keyboard = Keyboard.init();

    keyboard.keyup(.a);

    try testing.expect(keyboard.is_valid());
    try testing.expectEqual(@as(u32, 0), keyboard.count());
}

test "a keyboard state reports every modifier held" {
    var keyboard = Keyboard.init();

    keyboard.keydown(Keycode.control_left);
    keyboard.keydown(Keycode.alt_left);
    keyboard.keydown(Keycode.shift_left);
    keyboard.keydown(Keycode.super_left);

    const modifiers = keyboard.get_modifiers();

    try testing.expect(modifiers.ctrl());
    try testing.expect(modifiers.alt());
    try testing.expect(modifiers.shift());
    try testing.expect(modifiers.win());
    try testing.expectEqual(@as(u8, 4), modifiers.count());
}

test "a keyboard state reports no modifiers when none are held" {
    var keyboard = Keyboard.init();

    keyboard.keydown(.a);

    const modifiers = keyboard.get_modifiers();

    try testing.expect(!modifiers.ctrl());
    try testing.expect(!modifiers.alt());
    try testing.expect(!modifiers.shift());
    try testing.expect(!modifiers.win());
    try testing.expect(modifiers.none());
}

test "a keyboard state holds the function keys" {
    var keyboard = Keyboard.init();

    keyboard.keydown(Keycode.f1);
    try testing.expect(keyboard.is_down(Keycode.f1));

    keyboard.keydown(Keycode.f12);
    try testing.expect(keyboard.is_down(Keycode.f12));

    try testing.expectEqual(@as(u32, 2), keyboard.count());
}

test "a keyboard state holds the special keys" {
    var keyboard = Keyboard.init();

    keyboard.keydown(Keycode.escape);
    try testing.expect(keyboard.is_down(Keycode.escape));

    keyboard.keydown(Keycode.tab);
    try testing.expect(keyboard.is_down(Keycode.tab));

    keyboard.keydown(Keycode.space);
    try testing.expect(keyboard.is_down(Keycode.space));

    keyboard.keydown(Keycode.enter);
    try testing.expect(keyboard.is_down(Keycode.enter));
}

test "a keyboard state holds the navigation keys" {
    var keyboard = Keyboard.init();

    keyboard.keydown(Keycode.arrow_left);
    keyboard.keydown(Keycode.arrow_right);
    keyboard.keydown(Keycode.arrow_up);
    keyboard.keydown(Keycode.arrow_down);

    try testing.expect(keyboard.is_down(Keycode.arrow_left));
    try testing.expect(keyboard.is_down(Keycode.arrow_right));
    try testing.expect(keyboard.is_down(Keycode.arrow_up));
    try testing.expect(keyboard.is_down(Keycode.arrow_down));
    try testing.expectEqual(@as(u32, 4), keyboard.count());
}

test "clearing a keyboard state releases the modifiers too" {
    var keyboard = Keyboard.init();

    keyboard.keydown(Keycode.control_left);
    keyboard.keydown(Keycode.shift_left);
    keyboard.keydown(Keycode.alt_left);
    keyboard.keydown(Keycode.super_left);

    try testing.expect(keyboard.is_ctrl_down());
    try testing.expect(keyboard.is_shift_down());
    try testing.expect(keyboard.is_alt_down());
    try testing.expect(keyboard.is_win_down());

    keyboard.clear();

    try testing.expect(!keyboard.is_ctrl_down());
    try testing.expect(!keyboard.is_shift_down());
    try testing.expect(!keyboard.is_alt_down());
    try testing.expect(!keyboard.is_win_down());
    try testing.expectEqual(@as(u32, 0), keyboard.count());
}
