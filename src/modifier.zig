const std = @import("std");

const keycode = @import("keycode.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

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

        assert(text.len > 0);
        assert(text.len <= 16);

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

    pub fn is_valid(kind: Kind) bool {
        const value = @intFromEnum(kind);

        assert(kind_max == 3);
        assert(kind_count == 4);

        return value <= kind_max;
    }

    pub fn to_keycode(kind: Kind) Keycode {
        assert(kind.is_valid());

        const result: Keycode = switch (kind) {
            .ctrl => .control_left,
            .alt => .alt_left,
            .shift => .shift_left,
            .win => .super_left,
        };

        assert(Keycode.is_modifier(result));

        return result;
    }

    pub fn to_flag(kind: Kind) u4 {
        assert(kind.is_valid());

        const result: u4 = @as(u4, 1) << @intCast(@intFromEnum(kind));

        assert(result != 0);
        assert(@popCount(result) == 1);

        return result;
    }

    pub fn to_string(kind: Kind) []const u8 {
        assert(kind.is_valid());

        const result = switch (kind) {
            .ctrl => "Ctrl",
            .alt => "Alt",
            .shift => "Shift",
            .win => "Win",
        };

        assert(result.len > 0);
        assert(result.len <= 5);

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

        assert(result.ctrl() == args.ctrl);
        assert(result.alt() == args.alt);
        assert(result.shift() == args.shift);
        assert(result.win() == args.win);

        return result;
    }

    pub fn alt(set: *const Set) bool {
        assert(set.flags <= flag_all);
        assert(@popCount(set.flags) <= kind_count);

        return (set.flags & flag_alt) != 0;
    }

    pub fn any(set: *const Set) bool {
        assert(set.flags <= flag_all);
        assert(@popCount(set.flags) <= kind_count);

        return set.flags != flag_none;
    }

    pub fn count(set: *const Set) u8 {
        assert(set.flags <= flag_all);

        const result: u8 = @popCount(set.flags);

        assert(result <= kind_count);

        return result;
    }

    pub fn ctrl(set: *const Set) bool {
        assert(set.flags <= flag_all);
        assert(@popCount(set.flags) <= kind_count);

        return (set.flags & flag_ctrl) != 0;
    }

    pub fn eql(set: *const Set, other: *const Set) bool {
        assert(set.flags <= flag_all);
        assert(other.flags <= flag_all);

        return set.flags == other.flags;
    }

    pub fn none(set: *const Set) bool {
        assert(set.flags <= flag_all);
        assert(@popCount(set.flags) <= kind_count);

        const result = set.flags == flag_none;

        assert(result == !set.any());

        return result;
    }

    pub fn shift(set: *const Set) bool {
        assert(set.flags <= flag_all);
        assert(@popCount(set.flags) <= kind_count);

        return (set.flags & flag_shift) != 0;
    }

    pub fn to_array(set: *const Set) [kind_count]?Kind {
        assert(set.flags <= flag_all);
        assert(set.count() <= kind_count);

        return [kind_count]?Kind{
            if (set.ctrl()) .ctrl else null,
            if (set.alt()) .alt else null,
            if (set.shift()) .shift else null,
            if (set.win()) .win else null,
        };
    }

    pub fn to_bits(set: *const Set) u4 {
        assert(set.flags <= flag_all);
        assert(@popCount(set.flags) <= kind_count);

        return set.flags;
    }

    pub fn update(set: *Set, value: Keycode, down: bool) void {
        assert(set.flags <= flag_all);

        const flag: ?u4 = switch (value) {
            Keycode.control, Keycode.control_left, Keycode.control_right => flag_ctrl,
            Keycode.alt, Keycode.alt_left, Keycode.alt_right => flag_alt,
            Keycode.shift, Keycode.shift_left, Keycode.shift_right => flag_shift,
            Keycode.super_left, Keycode.super_right => flag_win,
            else => null,
        };

        if (flag) |f| {
            if (down) {
                set.flags |= f;
            } else {
                set.flags &= ~f;
            }
        }

        assert(set.count() <= kind_count);
        assert(set.flags <= flag_all);
    }

    pub fn win(set: *const Set) bool {
        assert(set.flags <= flag_all);
        assert(@popCount(set.flags) <= kind_count);

        return (set.flags & flag_win) != 0;
    }
};

const testing = std.testing;

test "a known modifier name parses" {
    try testing.expectEqual(Kind.ctrl, Kind.from_string("ctrl").?);
    try testing.expectEqual(Kind.ctrl, Kind.from_string("control").?);
    try testing.expectEqual(Kind.alt, Kind.from_string("alt").?);
    try testing.expectEqual(Kind.shift, Kind.from_string("shift").?);
    try testing.expectEqual(Kind.win, Kind.from_string("win").?);
    try testing.expectEqual(Kind.win, Kind.from_string("windows").?);
    try testing.expectEqual(Kind.win, Kind.from_string("meta").?);
}

test "an unknown modifier name does not parse" {
    try testing.expect(Kind.from_string("") == null);
    try testing.expect(Kind.from_string("invalid") == null);
    try testing.expect(Kind.from_string("CTRL") == null);
}

test "a modifier kind reports whether it is valid" {
    try testing.expect(Kind.ctrl.is_valid());
    try testing.expect(Kind.alt.is_valid());
    try testing.expect(Kind.shift.is_valid());
    try testing.expect(Kind.win.is_valid());
}

test "a modifier kind maps to its keycode" {
    try testing.expectEqual(Keycode.control_left, Kind.ctrl.to_keycode());
    try testing.expectEqual(Keycode.alt_left, Kind.alt.to_keycode());
    try testing.expectEqual(Keycode.shift_left, Kind.shift.to_keycode());
    try testing.expectEqual(Keycode.super_left, Kind.win.to_keycode());
}

test "a modifier kind maps to its flag" {
    try testing.expectEqual(flag_ctrl, Kind.ctrl.to_flag());
    try testing.expectEqual(flag_alt, Kind.alt.to_flag());
    try testing.expectEqual(flag_shift, Kind.shift.to_flag());
    try testing.expectEqual(flag_win, Kind.win.to_flag());
}

test "a modifier kind maps to its name" {
    try testing.expectEqualStrings("Ctrl", Kind.ctrl.to_string());
    try testing.expectEqualStrings("Alt", Kind.alt.to_string());
    try testing.expectEqualStrings("Shift", Kind.shift.to_string());
    try testing.expectEqualStrings("Win", Kind.win.to_string());
}

test "a set is built from a list of modifiers" {
    const empty = Set.from(.{});
    const with_ctrl = Set.from(.{ .ctrl = true });
    const with_all = Set.from(.{ .ctrl = true, .alt = true, .shift = true, .win = true });

    try testing.expectEqual(flag_none, empty.flags);
    try testing.expectEqual(flag_ctrl, with_ctrl.flags);
    try testing.expectEqual(flag_all, with_all.flags);
}

test "two sets holding the same modifiers are equal" {
    const a = Set.from(.{ .ctrl = true, .alt = true });
    const b = Set.from(.{ .ctrl = true, .alt = true });
    const c = Set.from(.{ .ctrl = true });

    try testing.expect(a.eql(&b));
    try testing.expect(!a.eql(&c));
}

test "two empty sets are equal" {
    const a = Set.from(.{});
    const b = Set.from(.{});

    try testing.expect(a.eql(&b));
}

test "set equality ignores the order modifiers were given" {
    const a = Set.from(.{ .ctrl = true, .alt = true });
    const b = Set.from(.{ .alt = true, .ctrl = true });

    try testing.expect(a.eql(&b));
}

test "a set reports whether it holds any modifier" {
    const empty = Set{};
    const with_ctrl = Set{ .flags = flag_ctrl };

    try testing.expect(empty.none());
    try testing.expect(!empty.any());
    try testing.expect(with_ctrl.any());
    try testing.expect(!with_ctrl.none());
}

test "a set counts the modifiers it holds" {
    const empty = Set{};
    const one = Set{ .flags = flag_ctrl };
    const two = Set{ .flags = flag_ctrl | flag_alt };
    const all = Set{ .flags = flag_all };

    try testing.expectEqual(@as(u8, 0), empty.count());
    try testing.expectEqual(@as(u8, 1), one.count());
    try testing.expectEqual(@as(u8, 2), two.count());
    try testing.expectEqual(@as(u8, 4), all.count());
}

test "a set counts three modifiers" {
    const three = Set{ .flags = flag_ctrl | flag_alt | flag_shift };

    try testing.expectEqual(@as(u8, 3), three.count());
}

test "updating a set records the modifier" {
    var set = Set{};

    set.update(Keycode.control_left, true);
    try testing.expect(set.ctrl());

    set.update(Keycode.control_left, false);
    try testing.expect(!set.ctrl());

    set.update(Keycode.alt_left, true);
    try testing.expect(set.alt());
}

test "updating a set records every modifier" {
    var set = Set{};

    set.update(Keycode.control_left, true);
    set.update(Keycode.alt_left, true);
    set.update(Keycode.shift_left, true);
    set.update(Keycode.super_left, true);

    try testing.expect(set.ctrl());
    try testing.expect(set.alt());
    try testing.expect(set.shift());
    try testing.expect(set.win());
    try testing.expectEqual(@as(u8, 4), set.count());
}

test "updating a set records the right hand modifiers" {
    var set = Set{};

    set.update(Keycode.control_right, true);
    try testing.expect(set.ctrl());

    set.update(Keycode.alt_right, true);
    try testing.expect(set.alt());

    set.update(Keycode.shift_right, true);
    try testing.expect(set.shift());

    set.update(Keycode.super_right, true);
    try testing.expect(set.win());
}

test "a set converts to an array of its modifiers" {
    const set = Set.from(.{ .ctrl = true, .shift = true });
    const array = set.to_array();

    try testing.expectEqual(Kind.ctrl, array[0].?);
    try testing.expect(array[1] == null);
    try testing.expectEqual(Kind.shift, array[2].?);
    try testing.expect(array[3] == null);
}

test "an empty set converts to an empty array" {
    const set = Set.from(.{});
    const array = set.to_array();

    try testing.expect(array[0] == null);
    try testing.expect(array[1] == null);
    try testing.expect(array[2] == null);
    try testing.expect(array[3] == null);
}

test "a full set converts to an array of every modifier" {
    const set = Set.from(.{ .ctrl = true, .alt = true, .shift = true, .win = true });
    const array = set.to_array();

    try testing.expectEqual(Kind.ctrl, array[0].?);
    try testing.expectEqual(Kind.alt, array[1].?);
    try testing.expectEqual(Kind.shift, array[2].?);
    try testing.expectEqual(Kind.win, array[3].?);
}

test "a set converts to its bit pattern" {
    const set = Set.from(.{ .ctrl = true, .alt = true });

    try testing.expectEqual(flag_ctrl | flag_alt, set.to_bits());
}

test "an empty set converts to no bits" {
    const set = Set.from(.{});

    try testing.expectEqual(flag_none, set.to_bits());
}

test "a full set converts to every bit" {
    const set = Set.from(.{ .ctrl = true, .alt = true, .shift = true, .win = true });

    try testing.expectEqual(flag_all, set.to_bits());
}

test "a set reports whether ctrl is held" {
    const with = Set.from(.{ .ctrl = true });
    const without = Set.from(.{ .alt = true });

    try testing.expect(with.ctrl());
    try testing.expect(!without.ctrl());
}

test "a set reports whether alt is held" {
    const with = Set.from(.{ .alt = true });
    const without = Set.from(.{ .ctrl = true });

    try testing.expect(with.alt());
    try testing.expect(!without.alt());
}

test "a set reports whether shift is held" {
    const with = Set.from(.{ .shift = true });
    const without = Set.from(.{ .ctrl = true });

    try testing.expect(with.shift());
    try testing.expect(!without.shift());
}

test "a set reports whether win is held" {
    const with = Set.from(.{ .win = true });
    const without = Set.from(.{ .ctrl = true });

    try testing.expect(with.win());
    try testing.expect(!without.win());
}

test "flag constants" {
    try testing.expectEqual(@as(u4, 0b0000), flag_none);
    try testing.expectEqual(@as(u4, 0b0001), flag_ctrl);
    try testing.expectEqual(@as(u4, 0b0010), flag_alt);
    try testing.expectEqual(@as(u4, 0b0100), flag_shift);
    try testing.expectEqual(@as(u4, 0b1000), flag_win);
    try testing.expectEqual(@as(u4, 0b1111), flag_all);
}

test "flag combinations" {
    try testing.expectEqual(@as(u4, 0b0011), flag_ctrl | flag_alt);
    try testing.expectEqual(@as(u4, 0b0101), flag_ctrl | flag_shift);
    try testing.expectEqual(@as(u4, 0b1001), flag_ctrl | flag_win);
    try testing.expectEqual(@as(u4, 0b0110), flag_alt | flag_shift);
    try testing.expectEqual(@as(u4, 0b1010), flag_alt | flag_win);
    try testing.expectEqual(@as(u4, 0b1100), flag_shift | flag_win);
}
