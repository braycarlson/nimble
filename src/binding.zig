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

        var hash: u32 = 0;

        hash = hash *% hash_factor +% @as(u32, self.value);

        if (self.modifiers.ctrl()) hash = hash *% hash_factor +% 1;
        if (self.modifiers.alt()) hash = hash *% hash_factor +% 2;
        if (self.modifiers.shift()) hash = hash *% hash_factor +% 3;
        if (self.modifiers.win()) hash = hash *% hash_factor +% 4;

        std.debug.assert(hash >= self.value);

        return hash;
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
