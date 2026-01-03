const std = @import("std");
const input = @import("input");

const modifier = input.modifier;
const keycode = input.keycode;

const Kind = modifier.Kind;
const Set = modifier.Set;
const flag_none = modifier.flag_none;
const flag_ctrl = modifier.flag_ctrl;
const flag_alt = modifier.flag_alt;
const flag_shift = modifier.flag_shift;
const flag_win = modifier.flag_win;
const flag_all = modifier.flag_all;

const testing = std.testing;

test "Kind.from_string valid" {
    try testing.expectEqual(Kind.ctrl, Kind.from_string("ctrl").?);
    try testing.expectEqual(Kind.ctrl, Kind.from_string("control").?);
    try testing.expectEqual(Kind.alt, Kind.from_string("alt").?);
    try testing.expectEqual(Kind.shift, Kind.from_string("shift").?);
    try testing.expectEqual(Kind.win, Kind.from_string("win").?);
    try testing.expectEqual(Kind.win, Kind.from_string("windows").?);
    try testing.expectEqual(Kind.win, Kind.from_string("meta").?);
}

test "Kind.from_string invalid" {
    try testing.expect(Kind.from_string("") == null);
    try testing.expect(Kind.from_string("invalid") == null);
    try testing.expect(Kind.from_string("CTRL") == null);
}

test "Kind.is_valid" {
    try testing.expect(Kind.ctrl.is_valid());
    try testing.expect(Kind.alt.is_valid());
    try testing.expect(Kind.shift.is_valid());
    try testing.expect(Kind.win.is_valid());
}

test "Kind.to_keycode" {
    try testing.expectEqual(keycode.lctrl, Kind.ctrl.to_keycode());
    try testing.expectEqual(keycode.lmenu, Kind.alt.to_keycode());
    try testing.expectEqual(keycode.lshift, Kind.shift.to_keycode());
    try testing.expectEqual(keycode.lwin, Kind.win.to_keycode());
}

test "Kind.to_flag" {
    try testing.expectEqual(flag_ctrl, Kind.ctrl.to_flag());
    try testing.expectEqual(flag_alt, Kind.alt.to_flag());
    try testing.expectEqual(flag_shift, Kind.shift.to_flag());
    try testing.expectEqual(flag_win, Kind.win.to_flag());
}

test "Kind.to_string" {
    try testing.expectEqualStrings("Ctrl", Kind.ctrl.to_string());
    try testing.expectEqualStrings("Alt", Kind.alt.to_string());
    try testing.expectEqualStrings("Shift", Kind.shift.to_string());
    try testing.expectEqualStrings("Win", Kind.win.to_string());
}

test "Set.from" {
    const empty = Set.from(.{});
    const with_ctrl = Set.from(.{ .ctrl = true });
    const with_all = Set.from(.{ .ctrl = true, .alt = true, .shift = true, .win = true });

    try testing.expectEqual(flag_none, empty.flags);
    try testing.expectEqual(flag_ctrl, with_ctrl.flags);
    try testing.expectEqual(flag_all, with_all.flags);
}

test "Set.eql" {
    const a = Set.from(.{ .ctrl = true, .alt = true });
    const b = Set.from(.{ .ctrl = true, .alt = true });
    const c = Set.from(.{ .ctrl = true });

    try testing.expect(a.eql(&b));
    try testing.expect(!a.eql(&c));
}

test "Set.eql empty" {
    const a = Set.from(.{});
    const b = Set.from(.{});

    try testing.expect(a.eql(&b));
}

test "Set.eql order independent" {
    const a = Set.from(.{ .ctrl = true, .alt = true });
    const b = Set.from(.{ .alt = true, .ctrl = true });

    try testing.expect(a.eql(&b));
}

test "Set.any and none" {
    const empty = Set{};
    const with_ctrl = Set{ .flags = flag_ctrl };

    try testing.expect(empty.none());
    try testing.expect(!empty.any());
    try testing.expect(with_ctrl.any());
    try testing.expect(!with_ctrl.none());
}

test "Set.count" {
    const empty = Set{};
    const one = Set{ .flags = flag_ctrl };
    const two = Set{ .flags = flag_ctrl | flag_alt };
    const all = Set{ .flags = flag_all };

    try testing.expectEqual(@as(u8, 0), empty.count());
    try testing.expectEqual(@as(u8, 1), one.count());
    try testing.expectEqual(@as(u8, 2), two.count());
    try testing.expectEqual(@as(u8, 4), all.count());
}

test "Set.count three modifiers" {
    const three = Set{ .flags = flag_ctrl | flag_alt | flag_shift };

    try testing.expectEqual(@as(u8, 3), three.count());
}

test "Set.update" {
    var set = Set{};

    set.update(keycode.lctrl, true);
    try testing.expect(set.ctrl());

    set.update(keycode.lctrl, false);
    try testing.expect(!set.ctrl());

    set.update(keycode.lmenu, true);
    try testing.expect(set.alt());
}

test "Set.update all modifiers" {
    var set = Set{};

    set.update(keycode.lctrl, true);
    set.update(keycode.lmenu, true);
    set.update(keycode.lshift, true);
    set.update(keycode.lwin, true);

    try testing.expect(set.ctrl());
    try testing.expect(set.alt());
    try testing.expect(set.shift());
    try testing.expect(set.win());
    try testing.expectEqual(@as(u8, 4), set.count());
}

test "Set.update right modifiers" {
    var set = Set{};

    set.update(keycode.rctrl, true);
    try testing.expect(set.ctrl());

    set.update(keycode.rmenu, true);
    try testing.expect(set.alt());

    set.update(keycode.rshift, true);
    try testing.expect(set.shift());

    set.update(keycode.rwin, true);
    try testing.expect(set.win());
}

test "Set.to_array" {
    const set = Set.from(.{ .ctrl = true, .shift = true });
    const array = set.to_array();

    try testing.expectEqual(Kind.ctrl, array[0].?);
    try testing.expect(array[1] == null);
    try testing.expectEqual(Kind.shift, array[2].?);
    try testing.expect(array[3] == null);
}

test "Set.to_array empty" {
    const set = Set.from(.{});
    const array = set.to_array();

    try testing.expect(array[0] == null);
    try testing.expect(array[1] == null);
    try testing.expect(array[2] == null);
    try testing.expect(array[3] == null);
}

test "Set.to_array all" {
    const set = Set.from(.{ .ctrl = true, .alt = true, .shift = true, .win = true });
    const array = set.to_array();

    try testing.expectEqual(Kind.ctrl, array[0].?);
    try testing.expectEqual(Kind.alt, array[1].?);
    try testing.expectEqual(Kind.shift, array[2].?);
    try testing.expectEqual(Kind.win, array[3].?);
}

test "Set.to_bits" {
    const set = Set.from(.{ .ctrl = true, .alt = true });

    try testing.expectEqual(flag_ctrl | flag_alt, set.to_bits());
}

test "Set.to_bits empty" {
    const set = Set.from(.{});

    try testing.expectEqual(flag_none, set.to_bits());
}

test "Set.to_bits all" {
    const set = Set.from(.{ .ctrl = true, .alt = true, .shift = true, .win = true });

    try testing.expectEqual(flag_all, set.to_bits());
}

test "Set.ctrl accessor" {
    const with = Set.from(.{ .ctrl = true });
    const without = Set.from(.{ .alt = true });

    try testing.expect(with.ctrl());
    try testing.expect(!without.ctrl());
}

test "Set.alt accessor" {
    const with = Set.from(.{ .alt = true });
    const without = Set.from(.{ .ctrl = true });

    try testing.expect(with.alt());
    try testing.expect(!without.alt());
}

test "Set.shift accessor" {
    const with = Set.from(.{ .shift = true });
    const without = Set.from(.{ .ctrl = true });

    try testing.expect(with.shift());
    try testing.expect(!without.shift());
}

test "Set.win accessor" {
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
