const std = @import("std");

const w32 = @import("win32").everything;

const keycode = @import("keycode.zig");

pub const kind_count: u8 = 4;
pub const kind_max: u8 = 3;

pub const flag_none: u4 = 0b0000;
pub const flag_ctrl: u4 = 0b0001;
pub const flag_alt: u4 = 0b0010;
pub const flag_shift: u4 = 0b0100;
pub const flag_win: u4 = 0b1000;
pub const flag_all: u4 = 0b1111;

pub const Kind = enum(u8) {
    ctrl = 0,
    alt = 1,
    shift = 2,
    win = 3,

    pub fn from_string(text: []const u8) ?Kind {
        if (text.len == 0) {
            return null;
        }

        std.debug.assert(text.len > 0);
        std.debug.assert(text.len <= 16);

        const map = std.StaticStringMap(Kind).initComptime(.{
            .{ "ctrl", .ctrl },
            .{ "control", .ctrl },
            .{ "alt", .alt },
            .{ "shift", .shift },
            .{ "win", .win },
            .{ "windows", .win },
            .{ "meta", .win },
        });

        return map.get(text);
    }

    pub fn is_valid(self: Kind) bool {
        const value = @intFromEnum(self);

        std.debug.assert(kind_max == 3);
        std.debug.assert(kind_count == 4);

        return value <= kind_max;
    }

    pub fn to_keycode(self: Kind) u8 {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromEnum(self) <= kind_max);

        const result = switch (self) {
            .ctrl => keycode.lctrl,
            .alt => keycode.lmenu,
            .shift => keycode.lshift,
            .win => keycode.lwin,
        };

        std.debug.assert(keycode.is_valid(result));
        std.debug.assert(keycode.is_modifier(result));

        return result;
    }

    pub fn to_flag(self: Kind) u4 {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromEnum(self) <= kind_max);

        const result: u4 = @as(u4, 1) << @intCast(@intFromEnum(self));

        std.debug.assert(result != 0);
        std.debug.assert(@popCount(result) == 1);

        return result;
    }

    pub fn to_string(self: Kind) []const u8 {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromEnum(self) <= kind_max);

        const result = switch (self) {
            .ctrl => "Ctrl",
            .alt => "Alt",
            .shift => "Shift",
            .win => "Win",
        };

        std.debug.assert(result.len > 0);
        std.debug.assert(result.len <= 5);

        return result;
    }
};

pub const Set = struct {
    flags: u4 = flag_none,

    pub const Args = struct {
        ctrl: bool = false,
        alt: bool = false,
        shift: bool = false,
        win: bool = false,
    };

    pub fn from(args: Args) Set {
        var flags: u4 = flag_none;

        if (args.ctrl) flags |= flag_ctrl;
        if (args.alt) flags |= flag_alt;
        if (args.shift) flags |= flag_shift;
        if (args.win) flags |= flag_win;

        const result = Set{ .flags = flags };

        std.debug.assert(result.ctrl() == args.ctrl);
        std.debug.assert(result.alt() == args.alt);
        std.debug.assert(result.shift() == args.shift);
        std.debug.assert(result.win() == args.win);

        return result;
    }

    pub fn poll() Set {
        const down_ctrl = is_key_down(keycode.lctrl) or is_key_down(keycode.rctrl);
        const down_alt = is_key_down(keycode.lmenu) or is_key_down(keycode.rmenu);
        const down_shift = is_key_down(keycode.lshift) or is_key_down(keycode.rshift);
        const down_win = is_key_down(keycode.lwin) or is_key_down(keycode.rwin);

        const result = Set.from(.{
            .ctrl = down_ctrl,
            .alt = down_alt,
            .shift = down_shift,
            .win = down_win,
        });

        std.debug.assert(result.count() <= kind_count);
        std.debug.assert(result.flags <= flag_all);

        return result;
    }

    fn is_key_down(value: u8) bool {
        std.debug.assert(keycode.is_valid(value));
        std.debug.assert(value >= keycode.value_min);
        std.debug.assert(value <= keycode.value_max);

        const state = w32.GetAsyncKeyState(@intCast(value));

        return state < 0;
    }

    pub fn alt(self: *const Set) bool {
        std.debug.assert(self.flags <= flag_all);
        std.debug.assert(@popCount(self.flags) <= kind_count);

        return (self.flags & flag_alt) != 0;
    }

    pub fn any(self: *const Set) bool {
        std.debug.assert(self.flags <= flag_all);
        std.debug.assert(@popCount(self.flags) <= kind_count);

        return self.flags != flag_none;
    }

    pub fn count(self: *const Set) u8 {
        std.debug.assert(self.flags <= flag_all);

        const result: u8 = @popCount(self.flags);

        std.debug.assert(result <= kind_count);

        return result;
    }

    pub fn ctrl(self: *const Set) bool {
        std.debug.assert(self.flags <= flag_all);
        std.debug.assert(@popCount(self.flags) <= kind_count);

        return (self.flags & flag_ctrl) != 0;
    }

    pub fn eql(self: *const Set, other: *const Set) bool {
        std.debug.assert(self.flags <= flag_all);
        std.debug.assert(other.flags <= flag_all);

        return self.flags == other.flags;
    }

    pub fn none(self: *const Set) bool {
        std.debug.assert(self.flags <= flag_all);
        std.debug.assert(@popCount(self.flags) <= kind_count);

        const result = self.flags == flag_none;

        std.debug.assert(result == !self.any());

        return result;
    }

    pub fn shift(self: *const Set) bool {
        std.debug.assert(self.flags <= flag_all);
        std.debug.assert(@popCount(self.flags) <= kind_count);

        return (self.flags & flag_shift) != 0;
    }

    pub fn to_array(self: *const Set) [kind_count]?Kind {
        std.debug.assert(self.flags <= flag_all);
        std.debug.assert(self.count() <= kind_count);

        return [kind_count]?Kind{
            if (self.ctrl()) .ctrl else null,
            if (self.alt()) .alt else null,
            if (self.shift()) .shift else null,
            if (self.win()) .win else null,
        };
    }

    pub fn to_bits(self: *const Set) u4 {
        std.debug.assert(self.flags <= flag_all);
        std.debug.assert(@popCount(self.flags) <= kind_count);

        return self.flags;
    }

    pub fn update(self: *Set, value: u8, down: bool) void {
        std.debug.assert(keycode.is_valid(value));
        std.debug.assert(self.flags <= flag_all);

        const flag: ?u4 = switch (value) {
            keycode.control, keycode.lctrl, keycode.rctrl => flag_ctrl,
            keycode.menu, keycode.lmenu, keycode.rmenu => flag_alt,
            keycode.shift, keycode.lshift, keycode.rshift => flag_shift,
            keycode.lwin, keycode.rwin => flag_win,
            else => null,
        };

        if (flag) |f| {
            if (down) {
                self.flags |= f;
            } else {
                self.flags &= ~f;
            }
        }

        std.debug.assert(self.count() <= kind_count);
        std.debug.assert(self.flags <= flag_all);
    }

    pub fn win(self: *const Set) bool {
        std.debug.assert(self.flags <= flag_all);
        std.debug.assert(@popCount(self.flags) <= kind_count);

        return (self.flags & flag_win) != 0;
    }
};
