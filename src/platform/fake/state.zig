const std = @import("std");

const keycode = @import("../../keycode.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

flags: [flag_count]u128 = .{ 0, 0 },

const State = @This();

pub const Snapshot = struct {
    flags: [flag_count]u128 = .{ 0, 0 },

    pub fn is_key_down(snapshot: *const Snapshot, code: Keycode) bool {
        return flags_test(&snapshot.flags, code);
    }
};

const Bit = struct {
    index: u32,
    position: u7,
};

const flag_count: u32 = 2;
const bits_per_flag: u8 = 128;

comptime {
    assert(flag_count == 2);
    assert(bits_per_flag == 128);
}

pub fn capture(state: *const State) Snapshot {
    const result = Snapshot{ .flags = state.flags };

    assert(result.flags[0] == state.flags[0]);
    assert(result.flags[1] == state.flags[1]);

    return result;
}

pub fn is_key_down(state: *const State, code: Keycode) bool {
    return flags_test(&state.flags, code);
}

pub fn set_down(state: *State, code: Keycode) void {
    const bit = bit_of(code);

    state.flags[bit.index] |= @as(u128, 1) << bit.position;

    assert(state.is_key_down(code));
}

pub fn set_up(state: *State, code: Keycode) void {
    const bit = bit_of(code);

    state.flags[bit.index] &= ~(@as(u128, 1) << bit.position);

    assert(!state.is_key_down(code));
}

fn bit_of(code: Keycode) Bit {
    const value: u32 = @backingInt(code);

    const result = Bit{
        .index = value / bits_per_flag,
        .position = @truncate(value % bits_per_flag),
    };

    assert(result.index < flag_count);

    return result;
}

fn flags_test(flags: *const [flag_count]u128, code: Keycode) bool {
    const bit = bit_of(code);

    return (flags[bit.index] & (@as(u128, 1) << bit.position)) != 0;
}

const testing = std.testing;

test "a captured snapshot keeps the keys held when it was taken" {
    var state: State = .{};

    state.set_down(.a);

    const snapshot = state.capture();

    state.set_up(.a);

    try testing.expect(snapshot.is_key_down(.a));
    try testing.expect(!state.is_key_down(.a));
    try testing.expect(!snapshot.is_key_down(.b));
}
