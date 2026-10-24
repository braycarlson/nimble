const std = @import("std");

const assert = std.debug.assert;

pub const sleep_ms_max: u32 = 1000 * 60 * 60;

var clock_ms: std.atomic.Value(i64) = .init(0);

comptime {
    assert(sleep_ms_max > 0);
}

pub fn now_ms() i64 {
    const result = clock_ms.load(.seq_cst);

    assert(result >= 0);

    return result;
}

pub fn sleep_ms(duration_ms: u32) void {
    assert(duration_ms <= sleep_ms_max);

    advance(duration_ms);
}

pub fn advance(duration_ms: u32) void {
    assert(duration_ms <= sleep_ms_max);

    const before = clock_ms.fetchAdd(duration_ms, .seq_cst);

    assert(before >= 0);
}

pub fn reset() void {
    clock_ms.store(0, .seq_cst);

    assert(now_ms() == 0);
}
