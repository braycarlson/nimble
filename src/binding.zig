const std = @import("std");

const keycode = @import("keycode.zig");
const modifier = @import("modifier.zig");
const state = @import("state.zig");

const Keyboard = state.Keyboard;

pub const hash_factor: u32 = 31;

pub const Binding = struct {
    value: u8 = 0,
    modifiers: modifier.Set = .{},

    pub fn init(value: u8, modifiers: modifier.Set) Binding {
        std.debug.assert(keycode.is_valid(value));
        std.debug.assert(modifiers.flags <= modifier.flag_all);

        const result = Binding{
            .value = value,
            .modifiers = modifiers,
        };

        std.debug.assert(result.is_valid());
        std.debug.assert(result.value == value);

        return result;
    }

    pub fn is_valid(self: *const Binding) bool {
        std.debug.assert(self.modifiers.flags <= modifier.flag_all);

        return keycode.is_valid(self.value);
    }

    pub fn eql(self: *const Binding, other: *const Binding) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(other.is_valid());

        const match_value = self.value == other.value;
        const match_modifiers = self.modifiers.eql(&other.modifiers);

        return match_value and match_modifiers;
    }

    pub fn has_win(self: *const Binding) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.modifiers.flags <= modifier.flag_all);

        return self.modifiers.win();
    }

    pub fn id(self: *const Binding) u32 {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.modifiers.flags <= modifier.flag_all);

        const mods: u32 = self.modifiers.to_bits();
        const result: u32 = (mods << 8) | @as(u32, self.value);

        std.debug.assert(result & 0xFF == self.value);
        std.debug.assert(result >> 8 == mods);

        return result;
    }

    pub fn match(self: *const Binding, keyboard: *const Keyboard) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(keyboard.is_valid());

        if (!keyboard.is_down(self.value)) {
            return false;
        }

        const match_ctrl = self.modifiers.ctrl() == keyboard.is_ctrl_down();
        const match_alt = self.modifiers.alt() == keyboard.is_alt_down();
        const match_shift = self.modifiers.shift() == keyboard.is_shift_down();
        const match_win = self.modifiers.win() == keyboard.is_win_down();

        return match_ctrl and match_alt and match_shift and match_win;
    }

    pub fn match_trigger(self: *const Binding, value: u8) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(value));

        return self.value == value;
    }

    pub fn to_keyboard(self: *const Binding) Keyboard {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.modifiers.flags <= modifier.flag_all);

        var result = Keyboard.init();

        result.keydown(self.value);

        if (self.modifiers.ctrl()) result.keydown(keycode.lctrl);
        if (self.modifiers.alt()) result.keydown(keycode.lmenu);
        if (self.modifiers.shift()) result.keydown(keycode.lshift);
        if (self.modifiers.win()) result.keydown(keycode.lwin);

        std.debug.assert(result.is_down(self.value));
        std.debug.assert(result.count() >= 1);

        return result;
    }
};
