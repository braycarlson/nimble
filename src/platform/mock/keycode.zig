const std = @import("std");

const core = @import("../../keycode.zig");

const assert = std.debug.assert;

const Keycode = core.Keycode;

pub const value_min: u8 = 0;
pub const value_max: u8 = core.value_max;
pub const table_size: u16 = 256;

comptime {
    assert(value_min < value_max);
    assert_round_trip();
}

pub fn from_native(native: u8) ?Keycode {
    if (native > value_max) {
        return null;
    }

    return @enumFromInt(native);
}

pub fn to_native(code: Keycode) ?u8 {
    return @intFromEnum(code);
}

fn assert_round_trip() void {
    @setEvalBranchQuota(table_size * 64);

    for (@typeInfo(Keycode).@"enum".fields) |field| {
        const code: Keycode = @enumFromInt(field.value);
        const native = to_native(code) orelse unreachable;

        assert(from_native(native) == code);
    }

    for (0..table_size) |index| {
        const native: u8 = @intCast(index);
        const mapped = from_native(native) orelse continue;

        assert(to_native(mapped) == native);
    }
}

const testing = std.testing;

test "the mock table is the identity over every keycode" {
    inline for (@typeInfo(Keycode).@"enum".fields) |field| {
        const code: Keycode = @enumFromInt(field.value);

        try testing.expectEqual(@as(u8, field.value), to_native(code).?);
        try testing.expectEqual(code, from_native(field.value).?);
    }
}

test "native values past the keycode span stay unmapped" {
    var native: u16 = @as(u16, value_max) + 1;

    while (native < table_size) : (native += 1) {
        try testing.expect(from_native(@intCast(native)) == null);
    }
}
