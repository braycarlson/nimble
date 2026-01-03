const std = @import("std");
const input = @import("input");

const binding_mod = input.binding;
const modifier = input.modifier;
const keycode = input.keycode;
const state_mod = input.state;

const Binding = binding_mod.Binding;
const Keyboard = state_mod.Keyboard;

const testing = std.testing;

test "Binding.init" {
    const modifiers = modifier.Set.from(.{ .ctrl = true, .alt = true });
    const b = Binding.init('L', modifiers);

    try testing.expect(b.is_valid());
    try testing.expectEqual(@as(u8, 'L'), b.value);
    try testing.expect(b.modifiers.ctrl());
    try testing.expect(b.modifiers.alt());
    try testing.expect(!b.modifiers.shift());
    try testing.expect(!b.modifiers.win());
}

test "Binding.init with no modifiers" {
    const b = Binding.init('X', modifier.Set.from(.{}));

    try testing.expect(b.is_valid());
    try testing.expectEqual(@as(u8, 'X'), b.value);
    try testing.expect(b.modifiers.none());
}

test "Binding.init with all modifiers" {
    const modifiers = modifier.Set.from(.{ .ctrl = true, .alt = true, .shift = true, .win = true });
    const b = Binding.init('Z', modifiers);

    try testing.expect(b.is_valid());
    try testing.expect(b.modifiers.ctrl());
    try testing.expect(b.modifiers.alt());
    try testing.expect(b.modifiers.shift());
    try testing.expect(b.modifiers.win());
}

test "Binding.eql same binding" {
    const a = Binding.init('A', modifier.Set.from(.{ .ctrl = true }));
    const b = Binding.init('A', modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(a.eql(&b));
    try testing.expect(b.eql(&a));
}

test "Binding.eql different key" {
    const a = Binding.init('A', modifier.Set.from(.{ .ctrl = true }));
    const b = Binding.init('B', modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(!a.eql(&b));
}

test "Binding.eql different modifiers" {
    const a = Binding.init('A', modifier.Set.from(.{ .ctrl = true }));
    const b = Binding.init('A', modifier.Set.from(.{ .alt = true }));

    try testing.expect(!a.eql(&b));
}

test "Binding.eql no modifiers" {
    const a = Binding.init('X', modifier.Set.from(.{}));
    const b = Binding.init('X', modifier.Set.from(.{}));

    try testing.expect(a.eql(&b));
}

test "Binding.has_win true" {
    const b = Binding.init('E', modifier.Set.from(.{ .win = true }));

    try testing.expect(b.has_win());
}

test "Binding.has_win false" {
    const b = Binding.init('E', modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(!b.has_win());
}

test "Binding.has_win with multiple modifiers" {
    const b = Binding.init('E', modifier.Set.from(.{ .ctrl = true, .win = true }));

    try testing.expect(b.has_win());
}

test "Binding.match" {
    const modifiers = modifier.Set.from(.{ .ctrl = true });
    const b = Binding.init('A', modifiers);

    var keyboard = Keyboard.init();
    keyboard.keydown(keycode.lctrl);
    keyboard.keydown('A');

    try testing.expect(b.match(&keyboard));

    keyboard.keydown(keycode.lshift);

    try testing.expect(!b.match(&keyboard));
}

test "Binding.match trigger only" {
    const modifiers = modifier.Set.from(.{});
    const b = Binding.init('A', modifiers);

    var keyboard = Keyboard.init();
    keyboard.keydown('A');

    try testing.expect(b.match(&keyboard));

    keyboard.keydown(keycode.lctrl);

    try testing.expect(!b.match(&keyboard));
}

test "Binding.match with right modifier" {
    const modifiers = modifier.Set.from(.{ .ctrl = true });
    const b = Binding.init('A', modifiers);

    var keyboard = Keyboard.init();
    keyboard.keydown(keycode.rctrl);
    keyboard.keydown('A');

    try testing.expect(b.match(&keyboard));
}

test "Binding.match missing trigger key" {
    const modifiers = modifier.Set.from(.{ .ctrl = true });
    const b = Binding.init('A', modifiers);

    var keyboard = Keyboard.init();
    keyboard.keydown(keycode.lctrl);

    try testing.expect(!b.match(&keyboard));
}

test "Binding.match_trigger" {
    const modifiers = modifier.Set.from(.{ .ctrl = true });
    const b = Binding.init('A', modifiers);

    try testing.expect(b.match_trigger('A'));
    try testing.expect(!b.match_trigger('B'));
}

test "Binding.id unique" {
    const ctrl_a = Binding.init('A', modifier.Set.from(.{ .ctrl = true }));
    const alt_a = Binding.init('A', modifier.Set.from(.{ .alt = true }));
    const ctrl_b = Binding.init('B', modifier.Set.from(.{ .ctrl = true }));

    const id1 = ctrl_a.id();
    const id2 = alt_a.id();
    const id3 = ctrl_b.id();

    try testing.expect(id1 != id2);
    try testing.expect(id1 != id3);
    try testing.expect(id2 != id3);
}

test "Binding.id same" {
    const a = Binding.init('A', modifier.Set.from(.{ .ctrl = true }));
    const b = Binding.init('A', modifier.Set.from(.{ .ctrl = true }));

    try testing.expectEqual(a.id(), b.id());
}

test "Binding.id unique for all single modifiers" {
    const none = Binding.init('A', modifier.Set.from(.{}));
    const ctrl = Binding.init('A', modifier.Set.from(.{ .ctrl = true }));
    const alt = Binding.init('A', modifier.Set.from(.{ .alt = true }));
    const shift = Binding.init('A', modifier.Set.from(.{ .shift = true }));
    const win = Binding.init('A', modifier.Set.from(.{ .win = true }));

    try testing.expect(none.id() != ctrl.id());
    try testing.expect(none.id() != alt.id());
    try testing.expect(none.id() != shift.id());
    try testing.expect(none.id() != win.id());
    try testing.expect(ctrl.id() != alt.id());
    try testing.expect(ctrl.id() != shift.id());
    try testing.expect(ctrl.id() != win.id());
    try testing.expect(alt.id() != shift.id());
    try testing.expect(alt.id() != win.id());
    try testing.expect(shift.id() != win.id());
}

test "Binding.to_keyboard" {
    const b = Binding.init('A', modifier.Set.from(.{ .ctrl = true, .shift = true }));
    const keyboard = b.to_keyboard();

    try testing.expect(keyboard.is_valid());
    try testing.expect(keyboard.is_down('A'));
    try testing.expect(keyboard.is_ctrl_down());
    try testing.expect(keyboard.is_shift_down());
    try testing.expect(!keyboard.is_alt_down());
    try testing.expect(!keyboard.is_win_down());
}

test "Binding.to_keyboard no modifiers" {
    const b = Binding.init('X', modifier.Set.from(.{}));
    const keyboard = b.to_keyboard();

    try testing.expect(keyboard.is_valid());
    try testing.expect(keyboard.is_down('X'));
    try testing.expect(!keyboard.is_ctrl_down());
    try testing.expect(!keyboard.is_alt_down());
    try testing.expect(!keyboard.is_shift_down());
    try testing.expect(!keyboard.is_win_down());
    try testing.expectEqual(@as(u32, 1), keyboard.count());
}

test "Binding.to_keyboard all modifiers" {
    const b = Binding.init('Z', modifier.Set.from(.{ .ctrl = true, .alt = true, .shift = true, .win = true }));
    const keyboard = b.to_keyboard();

    try testing.expect(keyboard.is_valid());
    try testing.expect(keyboard.is_down('Z'));
    try testing.expect(keyboard.is_ctrl_down());
    try testing.expect(keyboard.is_alt_down());
    try testing.expect(keyboard.is_shift_down());
    try testing.expect(keyboard.is_win_down());
    try testing.expectEqual(@as(u32, 5), keyboard.count());
}
