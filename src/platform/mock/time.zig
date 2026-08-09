const std = @import("std");

const assert = std.debug.assert;

pub const sleep_ms_max: u32 = 1000 * 60 * 60;

var clock_ms: i64 = 0;

comptime {
    assert(sleep_ms_max > 0);
}

pub fn now_ms() i64 {
    assert(clock_ms >= 0);

    return clock_ms;
}

pub fn sleep_ms(duration_ms: u32) void {
    assert(duration_ms <= sleep_ms_max);

    advance(duration_ms);
}

pub fn advance(duration_ms: u32) void {
    assert(duration_ms <= sleep_ms_max);

    const before = clock_ms;

    clock_ms += duration_ms;

    assert(clock_ms >= before);
}

pub fn reset() void {
    clock_ms = 0;

    assert(clock_ms == 0);
}
