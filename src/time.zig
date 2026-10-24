const std = @import("std");

const platform = @import("platform.zig");

const assert = std.debug.assert;

const backend = platform.backend.time;

pub const sleep_ms_max: u32 = 1000 * 60 * 60;

comptime {
    assert(sleep_ms_max <= backend.sleep_ms_max);
}

pub fn now_ms() i64 {
    const result = backend.now_ms();

    assert(result >= 0);

    return result;
}

pub fn sleep_ms(duration_ms: u32) void {
    assert(duration_ms <= sleep_ms_max);

    backend.sleep_ms(duration_ms);
}

const testing = std.testing;

test now_ms {
    platform.mock.reset();

    const before = now_ms();

    sleep_ms(250);

    try testing.expectEqual(before + 250, now_ms());
}

test sleep_ms {
    platform.mock.reset();

    sleep_ms(1000);
    sleep_ms(0);

    try testing.expectEqual(@as(i64, 1000), now_ms());
}
