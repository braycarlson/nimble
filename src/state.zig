const std = @import("std");

const w32 = @import("win32").everything;

const keycode = @import("keycode.zig");
const modifier = @import("modifier.zig");

pub const flag_count: u32 = 2;
pub const bits_per_flag: u8 = 128;
pub const key_count_max: u32 = 256;
pub const active_count_max: u8 = 32;

pub const Keyboard = struct {
    flags: [flag_count]u128 = .{ 0, 0 },
    keys_active: [active_count_max]u8 = [_]u8{0} ** active_count_max,
    active_count: u8 = 0,

    pub fn init() Keyboard {
        const result = Keyboard{};

        std.debug.assert(result.active_count == 0);
        std.debug.assert(result.flags[0] == 0);
        std.debug.assert(result.flags[1] == 0);

        return result;
    }

    pub fn is_valid(self: *const Keyboard) bool {
        const valid_count = self.active_count <= active_count_max;

        const valid_flags = self.flags[0] <= std.math.maxInt(u128) and
            self.flags[1] <= std.math.maxInt(u128);

        return valid_count and valid_flags;
    }

    pub fn clear(self: *Keyboard) void {
        std.debug.assert(self.is_valid());

        self.flags = .{ 0, 0 };
        self.active_count = 0;

        std.debug.assert(self.active_count == 0);
        std.debug.assert(self.flags[0] == 0);
        std.debug.assert(self.flags[1] == 0);
    }

    pub fn count(self: *const Keyboard) u32 {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.active_count <= active_count_max);

        return self.active_count;
    }

    pub fn get_modifiers(self: *const Keyboard) modifier.Set {
        std.debug.assert(self.is_valid());

        const result = modifier.Set.from(.{
            .ctrl = self.is_ctrl_down(),
            .alt = self.is_alt_down(),
            .shift = self.is_shift_down(),
            .win = self.is_win_down(),
        });

        std.debug.assert(result.flags <= modifier.flag_all);

        return result;
    }

    pub fn is_alt_down(self: *const Keyboard) bool {
        std.debug.assert(self.is_valid());

        return self.is_down(keycode.menu);
    }

    pub fn is_ctrl_down(self: *const Keyboard) bool {
        std.debug.assert(self.is_valid());

        return self.is_down(keycode.control);
    }

    pub fn is_down(self: *const Keyboard, value: u8) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(value >= keycode.value_min);
        std.debug.assert(value <= keycode.value_max);

        const index: u32 = value / bits_per_flag;
        const position: u7 = @truncate(value % bits_per_flag);

        std.debug.assert(index < flag_count);

        return (self.flags[index] & (@as(u128, 1) << position)) != 0;
    }

    pub fn is_shift_down(self: *const Keyboard) bool {
        std.debug.assert(self.is_valid());

        return self.is_down(keycode.shift);
    }

    pub fn is_win_down(self: *const Keyboard) bool {
        std.debug.assert(self.is_valid());

        const left = self.is_down(keycode.lwin);
        const right = self.is_down(keycode.rwin);

        return left or right;
    }

    pub fn keydown(self: *Keyboard, value: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(value >= keycode.value_min);
        std.debug.assert(value <= keycode.value_max);

        if (!self.is_down(value)) {
            self.add_active_key(value);
        }

        self.set_bit(value);
        self.update_generic_modifier_down(value);

        std.debug.assert(self.is_down(value));
        std.debug.assert(self.is_valid());
    }

    pub fn keyup(self: *Keyboard, value: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(value >= keycode.value_min);
        std.debug.assert(value <= keycode.value_max);

        self.clear_bit(value);
        self.remove_active_key(value);
        self.update_generic_modifier_up(value);

        std.debug.assert(!self.is_down(value));
        std.debug.assert(self.is_valid());
    }

    pub fn sync(self: *Keyboard) void {
        std.debug.assert(self.is_valid());

        var index: u8 = 0;
        var iteration: u8 = 0;

        while (iteration < active_count_max) : (iteration += 1) {
            std.debug.assert(iteration < active_count_max);

            if (index >= self.active_count) {
                break;
            }

            std.debug.assert(index < active_count_max);

            const key = self.keys_active[index];

            std.debug.assert(key >= keycode.value_min);
            std.debug.assert(key <= keycode.value_max);

            const state = w32.GetAsyncKeyState(@intCast(key));
            const down = state < 0;

            if (!down) {
                self.keyup(key);
            } else {
                index += 1;
            }
        }

        std.debug.assert(self.is_valid());
    }

    fn add_active_key(self: *Keyboard, value: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(value >= keycode.value_min);
        std.debug.assert(value <= keycode.value_max);

        if (self.active_count >= active_count_max) {
            return;
        }

        std.debug.assert(self.active_count < active_count_max);

        self.keys_active[self.active_count] = value;
        self.active_count += 1;

        std.debug.assert(self.active_count <= active_count_max);
    }

    fn clear_bit(self: *Keyboard, value: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(value >= keycode.value_min);
        std.debug.assert(value <= keycode.value_max);

        const index: u32 = value / bits_per_flag;
        const position: u7 = @truncate(value % bits_per_flag);

        std.debug.assert(index < flag_count);

        self.flags[index] &= ~(@as(u128, 1) << position);
    }

    fn remove_active_key(self: *Keyboard, value: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(value >= keycode.value_min);
        std.debug.assert(value <= keycode.value_max);

        const found_index = self.find_active_key_index(value);

        if (found_index == null) {
            return;
        }

        const index = found_index.?;

        std.debug.assert(index < self.active_count);
        std.debug.assert(self.active_count >= 1);

        self.active_count -= 1;

        if (index < self.active_count) {
            self.keys_active[index] = self.keys_active[self.active_count];
        }

        std.debug.assert(self.active_count <= active_count_max);
    }

    fn find_active_key_index(self: *const Keyboard, value: u8) ?u8 {
        var i: u8 = 0;

        while (i < self.active_count) : (i += 1) {
            std.debug.assert(i < active_count_max);

            if (self.keys_active[i] == value) {
                return i;
            }
        }

        return null;
    }

    fn set_bit(self: *Keyboard, value: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(value >= keycode.value_min);
        std.debug.assert(value <= keycode.value_max);

        const index: u32 = value / bits_per_flag;
        const position: u7 = @truncate(value % bits_per_flag);

        std.debug.assert(index < flag_count);

        self.flags[index] |= @as(u128, 1) << position;
    }

    fn update_generic_modifier_down(self: *Keyboard, value: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(value >= keycode.value_min);
        std.debug.assert(value <= keycode.value_max);

        switch (value) {
            keycode.lshift, keycode.rshift => self.set_bit(keycode.shift),
            keycode.lctrl, keycode.rctrl => self.set_bit(keycode.control),
            keycode.lmenu, keycode.rmenu => self.set_bit(keycode.menu),
            else => {},
        }
    }

    fn update_generic_modifier_up(self: *Keyboard, value: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(value >= keycode.value_min);
        std.debug.assert(value <= keycode.value_max);

        switch (value) {
            keycode.lshift, keycode.rshift => self.clear_shift_if_both_up(),
            keycode.lctrl, keycode.rctrl => self.clear_ctrl_if_both_up(),
            keycode.lmenu, keycode.rmenu => self.clear_alt_if_both_up(),
            else => {},
        }
    }

    fn clear_shift_if_both_up(self: *Keyboard) void {
        const left_down = self.is_down(keycode.lshift);
        const right_down = self.is_down(keycode.rshift);

        if (!left_down and !right_down) {
            self.clear_bit(keycode.shift);
        }
    }

    fn clear_ctrl_if_both_up(self: *Keyboard) void {
        const left_down = self.is_down(keycode.lctrl);
        const right_down = self.is_down(keycode.rctrl);

        if (!left_down and !right_down) {
            self.clear_bit(keycode.control);
        }
    }

    fn clear_alt_if_both_up(self: *Keyboard) void {
        const left_down = self.is_down(keycode.lmenu);
        const right_down = self.is_down(keycode.rmenu);

        if (!left_down and !right_down) {
            self.clear_bit(keycode.menu);
        }
    }
};
