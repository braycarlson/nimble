const std = @import("std");
const input = @import("input");

const key_event = input.event.key;
const keycode = input.keycode;
const modifier = input.modifier;

const Key = key_event.Key;

const testing = std.testing;

fn make_key(value: u8, mods: modifier.Set) Key {
    return Key{
        .value = value,
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = mods,
    };
}

fn make_key_full(
    value: u8,
    scan: u16,
    down: bool,
    injected: bool,
    extended: bool,
    extra: u64,
    mods: modifier.Set,
) Key {
    return Key{
        .value = value,
        .scan = scan,
        .down = down,
        .injected = injected,
        .extended = extended,
        .extra = extra,
        .modifiers = mods,
    };
}

test "Key.is_valid alpha" {
    const key = make_key('A', modifier.Set{});

    try testing.expect(key.is_valid());
}

test "Key.is_valid digit" {
    const key = make_key('5', modifier.Set{});

    try testing.expect(key.is_valid());
}

test "Key.is_valid function key" {
    const key = make_key(keycode.f1, modifier.Set{});

    try testing.expect(key.is_valid());
}

test "Key.is_valid special key" {
    const key = make_key(keycode.space, modifier.Set{});

    try testing.expect(key.is_valid());
}

test "Key.is_modifier ctrl" {
    const key = make_key(keycode.lctrl, modifier.Set{});

    try testing.expect(key.is_modifier());
}

test "Key.is_modifier rctrl" {
    const key = make_key(keycode.rctrl, modifier.Set{});

    try testing.expect(key.is_modifier());
}

test "Key.is_modifier shift" {
    const key = make_key(keycode.lshift, modifier.Set{});

    try testing.expect(key.is_modifier());
}

test "Key.is_modifier alt" {
    const key = make_key(keycode.lmenu, modifier.Set{});

    try testing.expect(key.is_modifier());
}

test "Key.is_modifier win" {
    const key = make_key(keycode.lwin, modifier.Set{});

    try testing.expect(key.is_modifier());
}

test "Key.is_modifier non-modifier" {
    const key = make_key('A', modifier.Set{});

    try testing.expect(!key.is_modifier());
}

test "Key.is_ctrl_down" {
    const with_ctrl = make_key('A', modifier.Set.from(.{ .ctrl = true }));
    const without_ctrl = make_key('A', modifier.Set{});

    try testing.expect(with_ctrl.is_ctrl_down());
    try testing.expect(!without_ctrl.is_ctrl_down());
}

test "Key.is_alt_down" {
    const with_alt = make_key('A', modifier.Set.from(.{ .alt = true }));
    const without_alt = make_key('A', modifier.Set{});

    try testing.expect(with_alt.is_alt_down());
    try testing.expect(!without_alt.is_alt_down());
}

test "Key.is_shift_down" {
    const with_shift = make_key('A', modifier.Set.from(.{ .shift = true }));
    const without_shift = make_key('A', modifier.Set{});

    try testing.expect(with_shift.is_shift_down());
    try testing.expect(!without_shift.is_shift_down());
}

test "Key.is_win_down" {
    const with_win = make_key('A', modifier.Set.from(.{ .win = true }));
    const without_win = make_key('A', modifier.Set{});

    try testing.expect(with_win.is_win_down());
    try testing.expect(!without_win.is_win_down());
}

test "Key.with_modifiers" {
    const key = make_key_full('A', 0, true, false, false, 0, modifier.Set{});
    const mods = modifier.Set.from(.{ .ctrl = true, .shift = true });

    const result = key.with_modifiers(mods);

    try testing.expectEqual(@as(u8, 'A'), result.value);
    try testing.expect(result.down);
    try testing.expect(result.modifiers.ctrl());
    try testing.expect(result.modifiers.shift());
    try testing.expect(!result.modifiers.alt());
    try testing.expect(!result.modifiers.win());
}

test "Key.with_modifiers preserves fields" {
    const key = make_key_full('B', 123, true, true, true, 456, modifier.Set{});
    const mods = modifier.Set.from(.{ .alt = true });

    const result = key.with_modifiers(mods);

    try testing.expectEqual(@as(u8, 'B'), result.value);
    try testing.expectEqual(@as(u16, 123), result.scan);
    try testing.expect(result.down);
    try testing.expect(result.injected);
    try testing.expect(result.extended);
    try testing.expectEqual(@as(u64, 456), result.extra);
    try testing.expect(result.modifiers.alt());
}

test "Key all modifiers" {
    const key = make_key('C', modifier.Set.from(.{
        .ctrl = true,
        .alt = true,
        .shift = true,
        .win = true,
    }));

    try testing.expect(key.is_ctrl_down());
    try testing.expect(key.is_alt_down());
    try testing.expect(key.is_shift_down());
    try testing.expect(key.is_win_down());
}

test "Key down state" {
    const down = make_key_full('D', 0, true, false, false, 0, modifier.Set{});
    const up = make_key_full('D', 0, false, false, false, 0, modifier.Set{});

    try testing.expect(down.down);
    try testing.expect(!up.down);
}

test "Key injected state" {
    const injected = make_key_full('E', 0, true, true, false, 0, modifier.Set{});
    const not_injected = make_key_full('E', 0, true, false, false, 0, modifier.Set{});

    try testing.expect(injected.injected);
    try testing.expect(!not_injected.injected);
}

test "Key extended state" {
    const extended = make_key_full(keycode.insert, 0, true, false, true, 0, modifier.Set{});
    const not_extended = make_key_full('F', 0, true, false, false, 0, modifier.Set{});

    try testing.expect(extended.extended);
    try testing.expect(!not_extended.extended);
}

test "Key extra data" {
    const key = make_key_full('G', 0, true, false, false, 0xDEADBEEF, modifier.Set{});

    try testing.expectEqual(@as(u64, 0xDEADBEEF), key.extra);
}

test "Key scan code" {
    const key = make_key_full('H', 0x23, true, false, false, 0, modifier.Set{});

    try testing.expectEqual(@as(u16, 0x23), key.scan);
}
