const std = @import("std");

const interface = @import("../interface.zig");

const assert = std.debug.assert;

clock_ms: std.atomic.Value(i64) = .init(0),

const Time = @This();

pub fn now_ms(time: *const Time) i64 {
    const result = time.clock_ms.load(.seq_cst);

    assert(result >= 0);

    return result;
}

pub fn sleep_ms(time: *Time, duration_ms: u32) void {
    assert(duration_ms <= interface.sleep_ms_max);

    time.advance(duration_ms);
}

pub fn advance(time: *Time, duration_ms: u32) void {
    assert(duration_ms <= std.math.maxInt(i32));

    const before = time.clock_ms.fetchAdd(duration_ms, .seq_cst);

    assert(before >= 0);
    assert(time.now_ms() >= before + duration_ms);
}

const testing = std.testing;

test "the fake clock moves only when it is advanced" {
    var time: Time = .{};

    try testing.expectEqual(@as(i64, 0), time.now_ms());

    time.sleep_ms(250);
    time.advance(50);

    try testing.expectEqual(@as(i64, 300), time.now_ms());
}
