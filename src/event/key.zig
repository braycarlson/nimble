const std = @import("std");

const w32 = @import("win32").everything;

const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");

pub const Key = struct {
    value: u8,
    scan: u16,
    down: bool,
    injected: bool,
    extended: bool,
    extra: u64,
    modifiers: modifier.Set = .{},

    pub fn is_valid(self: *const Key) bool {
        std.debug.assert(self.value <= 0xFF);
        std.debug.assert(self.modifiers.flags <= modifier.flag_all);

        return keycode.is_valid(self.value);
    }

    pub fn is_modifier(self: *const Key) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(self.value));

        return keycode.is_modifier(self.value);
    }

    pub fn is_ctrl_down(self: *const Key) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.modifiers.flags <= modifier.flag_all);

        return self.modifiers.ctrl();
    }

    pub fn is_alt_down(self: *const Key) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.modifiers.flags <= modifier.flag_all);

        return self.modifiers.alt();
    }

    pub fn is_shift_down(self: *const Key) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.modifiers.flags <= modifier.flag_all);

        return self.modifiers.shift();
    }

    pub fn is_win_down(self: *const Key) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.modifiers.flags <= modifier.flag_all);

        return self.modifiers.win();
    }

    pub fn parse(wparam: w32.WPARAM, lparam: w32.LPARAM) ?Key {
        std.debug.assert(@sizeOf(w32.WPARAM) >= 4);
        std.debug.assert(@sizeOf(w32.LPARAM) >= 4);

        const data = extract(lparam) orelse return null;

        if (!is_keycode_valid(data)) {
            return null;
        }

        const result = Key{
            .value = @truncate(data.vkCode),
            .scan = @truncate(data.scanCode),
            .down = is_down(wparam),
            .injected = data.flags.INJECTED == 1,
            .extended = data.flags.EXTENDED == 1,
            .extra = @intCast(data.dwExtraInfo),
            .modifiers = .{},
        };

        std.debug.assert(keycode.is_valid(result.value));
        std.debug.assert(result.modifiers.flags == modifier.flag_none);

        return result;
    }

    pub fn with_modifiers(self: Key, modifiers: modifier.Set) Key {
        std.debug.assert(self.is_valid());
        std.debug.assert(modifiers.flags <= modifier.flag_all);

        var result = self;
        result.modifiers = modifiers;

        std.debug.assert(result.modifiers.eql(&modifiers));
        std.debug.assert(result.value == self.value);

        return result;
    }

    fn extract(lparam: w32.LPARAM) ?*w32.KBDLLHOOKSTRUCT {
        std.debug.assert(@sizeOf(w32.LPARAM) == @sizeOf(u64) or @sizeOf(w32.LPARAM) == @sizeOf(u32));

        if (lparam == 0) {
            return null;
        }

        const address: u64 = @intCast(lparam);

        std.debug.assert(address != 0);

        return @ptrFromInt(address);
    }

    pub fn from_lparam(lparam: w32.LPARAM) ?*w32.KBDLLHOOKSTRUCT {
        std.debug.assert(@sizeOf(w32.LPARAM) == @sizeOf(u64) or @sizeOf(w32.LPARAM) == @sizeOf(u32));

        if (lparam == 0) {
            return null;
        }

        const address: u64 = @intCast(lparam);

        std.debug.assert(address != 0);

        return @ptrFromInt(address);
    }

    fn is_keycode_valid(data: *w32.KBDLLHOOKSTRUCT) bool {
        std.debug.assert(keycode.value_min == 0x01);
        std.debug.assert(keycode.value_max == 0xFE);

        const above = data.vkCode >= keycode.value_min;
        const below = data.vkCode <= keycode.value_max;

        return above and below;
    }

    fn is_down(wparam: w32.WPARAM) bool {
        std.debug.assert(wparam != 0);

        const is_keydown = wparam == w32.WM_KEYDOWN;
        const is_syskeydown = wparam == w32.WM_SYSKEYDOWN;

        return is_keydown or is_syskeydown;
    }
};
