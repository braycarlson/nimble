const std = @import("std");

const keycode = @import("../../keycode.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const flag_count: u32 = 2;
pub const bits_per_flag: u8 = 128;

var flags: [flag_count]u128 = .{ 0, 0 };

comptime {
    assert(flag_count == 2);
    assert(bits_per_flag == 128);
}

pub const Snapshot = struct {
    flags: [flag_count]u128 = .{ 0, 0 },
};

pub fn capture() Snapshot {
    return Snapshot{ .flags = flags };
}

pub fn is_key_down_at(snapshot: *const Snapshot, code: Keycode) bool {
    const value: u32 = @intFromEnum(code);
    const index: u32 = value / bits_per_flag;
    const position: u7 = @truncate(value % bits_per_flag);

    assert(index < flag_count);

    return (snapshot.flags[index] & (@as(u128, 1) << position)) != 0;
}

pub fn is_key_down(code: Keycode) bool {
    const value: u32 = @intFromEnum(code);
    const index: u32 = value / bits_per_flag;
    const position: u7 = @truncate(value % bits_per_flag);

    assert(index < flag_count);

    return (flags[index] & (@as(u128, 1) << position)) != 0;
}

pub fn set_down(code: Keycode) void {
    const value: u32 = @intFromEnum(code);
    const index: u32 = value / bits_per_flag;
    const position: u7 = @truncate(value % bits_per_flag);

    assert(index < flag_count);

    flags[index] |= @as(u128, 1) << position;

    assert(is_key_down(code));
}

pub fn set_up(code: Keycode) void {
    const value: u32 = @intFromEnum(code);
    const index: u32 = value / bits_per_flag;
    const position: u7 = @truncate(value % bits_per_flag);

    assert(index < flag_count);

    flags[index] &= ~(@as(u128, 1) << position);

    assert(!is_key_down(code));
}

pub fn reset() void {
    flags = .{ 0, 0 };

    assert(flags[0] == 0);
    assert(flags[1] == 0);
}
