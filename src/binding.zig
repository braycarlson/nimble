const std = @import("std");

const keycode = @import("keycode.zig");
const modifier = @import("modifier.zig");
const state = @import("state.zig");

const assert = std.debug.assert;
const Keycode = keycode.Keycode;
const Keyboard = state.Keyboard;

pub const hash_factor: u32 = 31;

pub const Binding = struct {
    value: Keycode = .silent,
    modifiers: modifier.Set = .{},

    pub fn init(value: Keycode, modifiers: modifier.Set) Binding {
        assert(modifiers.flags <= modifier.flag_all);

        const result = Binding{
            .value = value,
            .modifiers = modifiers,
        };

        assert(result.is_valid());
        assert(result.value == value);

        return result;
    }

    pub fn is_valid(binding: *const Binding) bool {
        assert(binding.modifiers.flags <= modifier.flag_all);

        return true;
    }

    pub fn eql(binding: *const Binding, other: *const Binding) bool {
        assert(binding.is_valid());
        assert(other.is_valid());

        const match_value = binding.value == other.value;
        const match_modifiers = binding.modifiers.eql(&other.modifiers);

        return match_value and match_modifiers;
    }

    pub fn has_win(binding: *const Binding) bool {
        assert(binding.is_valid());
        assert(binding.modifiers.flags <= modifier.flag_all);

        return binding.modifiers.win();
    }

    pub fn id(binding: *const Binding) u32 {
        assert(binding.is_valid());
        assert(binding.modifiers.flags <= modifier.flag_all);

        const mods: u32 = binding.modifiers.to_bits();
        const result: u32 = (mods << 8) | @as(u32, @intFromEnum(binding.value));

        assert(result & 0xFF == @intFromEnum(binding.value));
        assert(result >> 8 == mods);

        return result;
    }

    pub fn match(binding: *const Binding, keyboard: *const Keyboard) bool {
        assert(binding.is_valid());
        assert(keyboard.is_valid());

        if (!keyboard.is_down(binding.value)) {
            return false;
        }

        const match_ctrl = binding.modifiers.ctrl() == keyboard.is_ctrl_down();
        const match_alt = binding.modifiers.alt() == keyboard.is_alt_down();
        const match_shift = binding.modifiers.shift() == keyboard.is_shift_down();
        const match_win = binding.modifiers.win() == keyboard.is_win_down();

        return match_ctrl and match_alt and match_shift and match_win;
    }

    pub fn match_trigger(binding: *const Binding, value: Keycode) bool {
        assert(binding.is_valid());

        return binding.value == value;
    }

    pub fn to_keyboard(binding: *const Binding) Keyboard {
        assert(binding.is_valid());
        assert(binding.modifiers.flags <= modifier.flag_all);

        var result = Keyboard.init();

        result.keydown(binding.value);

        if (binding.modifiers.ctrl()) result.keydown(Keycode.control_left);
        if (binding.modifiers.alt()) result.keydown(Keycode.alt_left);
        if (binding.modifiers.shift()) result.keydown(Keycode.shift_left);
        if (binding.modifiers.win()) result.keydown(Keycode.super_left);

        assert(result.is_down(binding.value));
        assert(result.count() >= 1);

        return result;
    }
};

const testing = std.testing;

test "a binding carries the key and modifiers it was built from" {
    const modifiers = modifier.Set.from(.{ .ctrl = true, .alt = true });
    const b = Binding.init(.l, modifiers);

    try testing.expect(b.is_valid());
    try testing.expectEqual(.l, b.value);
    try testing.expect(b.modifiers.ctrl());
    try testing.expect(b.modifiers.alt());
    try testing.expect(!b.modifiers.shift());
    try testing.expect(!b.modifiers.win());
}

test "a binding can carry no modifiers" {
    const b = Binding.init(.x, modifier.Set.from(.{}));

    try testing.expect(b.is_valid());
    try testing.expectEqual(.x, b.value);
    try testing.expect(b.modifiers.none());
}

test "a binding can carry every modifier" {
    const modifiers = modifier.Set.from(.{ .ctrl = true, .alt = true, .shift = true, .win = true });
    const b = Binding.init(.z, modifiers);

    try testing.expect(b.is_valid());
    try testing.expect(b.modifiers.ctrl());
    try testing.expect(b.modifiers.alt());
    try testing.expect(b.modifiers.shift());
    try testing.expect(b.modifiers.win());
}

test "two bindings with the same key and modifiers are equal" {
    const a = Binding.init(.a, modifier.Set.from(.{ .ctrl = true }));
    const b = Binding.init(.a, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(a.eql(&b));
    try testing.expect(b.eql(&a));
}

test "two bindings with different keys are not equal" {
    const a = Binding.init(.a, modifier.Set.from(.{ .ctrl = true }));
    const b = Binding.init(.b, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(!a.eql(&b));
}

test "two bindings with different modifiers are not equal" {
    const a = Binding.init(.a, modifier.Set.from(.{ .ctrl = true }));
    const b = Binding.init(.a, modifier.Set.from(.{ .alt = true }));

    try testing.expect(!a.eql(&b));
}

test "two bindings with no modifiers are equal" {
    const a = Binding.init(.x, modifier.Set.from(.{}));
    const b = Binding.init(.x, modifier.Set.from(.{}));

    try testing.expect(a.eql(&b));
}

test "a binding holding win reports it" {
    const b = Binding.init(.e, modifier.Set.from(.{ .win = true }));

    try testing.expect(b.has_win());
}

test "a binding without win reports it" {
    const b = Binding.init(.e, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(!b.has_win());
}

test "a binding reports win among several modifiers" {
    const b = Binding.init(.e, modifier.Set.from(.{ .ctrl = true, .win = true }));

    try testing.expect(b.has_win());
}

test "a binding matches the key and modifiers it names" {
    const modifiers = modifier.Set.from(.{ .ctrl = true });
    const b = Binding.init(.a, modifiers);

    var keyboard = Keyboard.init();
    keyboard.keydown(Keycode.control_left);
    keyboard.keydown(.a);

    try testing.expect(b.match(&keyboard));

    keyboard.keydown(Keycode.shift_left);

    try testing.expect(!b.match(&keyboard));
}

test "a binding matches on its trigger alone" {
    const modifiers = modifier.Set.from(.{});
    const b = Binding.init(.a, modifiers);

    var keyboard = Keyboard.init();
    keyboard.keydown(.a);

    try testing.expect(b.match(&keyboard));

    keyboard.keydown(Keycode.control_left);

    try testing.expect(!b.match(&keyboard));
}

test "a binding matches a right hand modifier" {
    const modifiers = modifier.Set.from(.{ .ctrl = true });
    const b = Binding.init(.a, modifiers);

    var keyboard = Keyboard.init();
    keyboard.keydown(Keycode.control_right);
    keyboard.keydown(.a);

    try testing.expect(b.match(&keyboard));
}

test "a binding does not match without its trigger" {
    const modifiers = modifier.Set.from(.{ .ctrl = true });
    const b = Binding.init(.a, modifiers);

    var keyboard = Keyboard.init();
    keyboard.keydown(Keycode.control_left);

    try testing.expect(!b.match(&keyboard));
}

test "a binding matches its trigger key" {
    const modifiers = modifier.Set.from(.{ .ctrl = true });
    const b = Binding.init(.a, modifiers);

    try testing.expect(b.match_trigger(.a));
    try testing.expect(!b.match_trigger(.b));
}

test "two different bindings get different ids" {
    const ctrl_a = Binding.init(.a, modifier.Set.from(.{ .ctrl = true }));
    const alt_a = Binding.init(.a, modifier.Set.from(.{ .alt = true }));
    const ctrl_b = Binding.init(.b, modifier.Set.from(.{ .ctrl = true }));

    const id1 = ctrl_a.id();
    const id2 = alt_a.id();
    const id3 = ctrl_b.id();

    try testing.expect(id1 != id2);
    try testing.expect(id1 != id3);
    try testing.expect(id2 != id3);
}

test "two equal bindings get the same id" {
    const a = Binding.init(.a, modifier.Set.from(.{ .ctrl = true }));
    const b = Binding.init(.a, modifier.Set.from(.{ .ctrl = true }));

    try testing.expectEqual(a.id(), b.id());
}

test "a binding id packs the modifiers above the keycode" {
    const low_ctrl = Binding.init(.backspace, modifier.Set.from(.{ .ctrl = true }));
    const space_plain = Binding.init(.space, modifier.Set.from(.{}));

    const low_expected = (@as(u32, modifier.flag_ctrl) << 8) | @intFromEnum(Keycode.backspace);
    const space_expected = @as(u32, @intFromEnum(Keycode.space));

    try testing.expect(low_ctrl.id() != space_plain.id());
    try testing.expectEqual(low_expected, low_ctrl.id());
    try testing.expectEqual(space_expected, space_plain.id());
}

test "binding ids are unique across every modifier set for one key" {
    const value: Keycode = .a;

    var seen = [_]bool{false} ** 0x1000;
    var flags: u8 = 0;

    while (flags <= 0xF) : (flags += 1) {
        const b = Binding{
            .value = value,
            .modifiers = .{ .flags = @intCast(flags) },
        };

        const packed_id = b.id();

        try testing.expect(packed_id < seen.len);
        try testing.expect(!seen[packed_id]);

        seen[packed_id] = true;
    }
}

test "binding ids are unique across every single modifier" {
    const none = Binding.init(.a, modifier.Set.from(.{}));
    const ctrl = Binding.init(.a, modifier.Set.from(.{ .ctrl = true }));
    const alt = Binding.init(.a, modifier.Set.from(.{ .alt = true }));
    const shift = Binding.init(.a, modifier.Set.from(.{ .shift = true }));
    const win = Binding.init(.a, modifier.Set.from(.{ .win = true }));

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

test "a binding converts to its keyboard form" {
    const b = Binding.init(.a, modifier.Set.from(.{ .ctrl = true, .shift = true }));
    const keyboard = b.to_keyboard();

    try testing.expect(keyboard.is_valid());
    try testing.expect(keyboard.is_down(.a));
    try testing.expect(keyboard.is_ctrl_down());
    try testing.expect(keyboard.is_shift_down());
    try testing.expect(!keyboard.is_alt_down());
    try testing.expect(!keyboard.is_win_down());
}

test "a binding with no modifiers converts to its keyboard form" {
    const b = Binding.init(.x, modifier.Set.from(.{}));
    const keyboard = b.to_keyboard();

    try testing.expect(keyboard.is_valid());
    try testing.expect(keyboard.is_down(.x));
    try testing.expect(!keyboard.is_ctrl_down());
    try testing.expect(!keyboard.is_alt_down());
    try testing.expect(!keyboard.is_shift_down());
    try testing.expect(!keyboard.is_win_down());
    try testing.expectEqual(@as(u32, 1), keyboard.count());
}

test "a binding with every modifier converts to its keyboard form" {
    const modifiers = modifier.Set.from(.{
        .ctrl = true,
        .alt = true,
        .shift = true,
        .win = true,
    });

    const b = Binding.init(.z, modifiers);
    const keyboard = b.to_keyboard();

    try testing.expect(keyboard.is_valid());
    try testing.expect(keyboard.is_down(.z));
    try testing.expect(keyboard.is_ctrl_down());
    try testing.expect(keyboard.is_alt_down());
    try testing.expect(keyboard.is_shift_down());
    try testing.expect(keyboard.is_win_down());
    try testing.expectEqual(@as(u32, 5), keyboard.count());
}
