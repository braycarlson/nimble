const std = @import("std");

const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const Key = struct {
    value: Keycode,
    down: bool,
    injected: bool = false,
    time_ms: i64 = 0,
    modifiers: modifier.Set = .{},

    pub fn is_valid(key: *const Key) bool {
        if (key.time_ms < 0) {
            return false;
        }

        return keycode.is_defined(key.value);
    }

    pub fn is_modifier(key: *const Key) bool {
        assert(key.is_valid());

        return key.value.is_modifier();
    }

    pub fn is_ctrl_down(key: *const Key) bool {
        assert(key.is_valid());

        return key.modifiers.ctrl();
    }

    pub fn is_alt_down(key: *const Key) bool {
        assert(key.is_valid());

        return key.modifiers.alt();
    }

    pub fn is_shift_down(key: *const Key) bool {
        assert(key.is_valid());

        return key.modifiers.shift();
    }

    pub fn is_win_down(key: *const Key) bool {
        assert(key.is_valid());

        return key.modifiers.win();
    }

    pub fn with_modifiers(key: Key, modifiers: modifier.Set) Key {
        assert(key.is_valid());
        assert(modifiers.flags <= modifier.flag_all);

        var result = key;
        result.modifiers = modifiers;

        assert(result.modifiers.eql(&modifiers));
        assert(result.value == key.value);
        assert(result.is_valid());

        return result;
    }
};

const testing = std.testing;

fn make_key(value: Keycode, mods: modifier.Set) Key {
    return Key{ .value = value, .down = true, .modifiers = mods };
}

test "every defined keycode makes a valid key event" {
    inline for (@typeInfo(Keycode).@"enum".fields) |field| {
        const key = make_key(@enumFromInt(field.value), .{});

        try testing.expect(key.is_valid());
    }
}

test "a negative timestamp is rejected before anything else" {
    var key = make_key(.a, .{});
    key.time_ms = -1;

    try testing.expect(!key.is_valid());
}

test "a stamped key event is valid" {
    const key = Key{ .value = .a, .down = true, .injected = true, .time_ms = 1234 };

    try testing.expect(key.is_valid());
    try testing.expect(key.injected);
    try testing.expectEqual(@as(i64, 1234), key.time_ms);
}

test "a key event reports sided and generic modifiers alike" {
    try testing.expect(make_key(Keycode.control_left, .{}).is_modifier());
    try testing.expect(make_key(Keycode.control_right, .{}).is_modifier());
    try testing.expect(make_key(Keycode.shift_left, .{}).is_modifier());
    try testing.expect(make_key(Keycode.alt_left, .{}).is_modifier());
    try testing.expect(make_key(Keycode.super_left, .{}).is_modifier());
    try testing.expect(!make_key(.a, .{}).is_modifier());
    try testing.expect(!make_key(Keycode.space, .{}).is_modifier());
}

test "a key reads its modifier predicates from the modifier set" {
    const key = make_key(.a, modifier.Set.from(.{
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

test "a bare key reports no modifiers" {
    const key = make_key(.a, .{});

    try testing.expect(!key.is_ctrl_down());
    try testing.expect(!key.is_alt_down());
    try testing.expect(!key.is_shift_down());
    try testing.expect(!key.is_win_down());
}

test "replacing the modifiers leaves the rest of the event alone" {
    const key = Key{ .value = .b, .down = true, .injected = true, .time_ms = 42 };
    const mods = modifier.Set.from(.{ .ctrl = true, .shift = true });

    const result = key.with_modifiers(mods);

    try testing.expectEqual(Keycode.b, result.value);
    try testing.expect(result.down);
    try testing.expect(result.injected);
    try testing.expectEqual(@as(i64, 42), result.time_ms);
    try testing.expect(result.is_ctrl_down());
    try testing.expect(result.is_shift_down());
    try testing.expect(!result.is_alt_down());
    try testing.expect(!result.is_win_down());
}

test "a key down and a key up are distinguishable" {
    const down = Key{ .value = .d, .down = true };
    const up = Key{ .value = .d, .down = false };

    try testing.expect(down.down);
    try testing.expect(!up.down);
}

test "a key defaults to a local, unstamped event" {
    const key = Key{ .value = .e, .down = true };

    try testing.expect(!key.injected);
    try testing.expectEqual(@as(i64, 0), key.time_ms);
    try testing.expect(key.modifiers.none());
}
