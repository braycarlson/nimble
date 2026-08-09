const std = @import("std");

const assert = std.debug.assert;

const linux = std.os.linux;

pub const sleep_ms_max: u32 = 1000 * 60 * 60;
pub const ns_per_ms: i64 = 1000 * 1000;
pub const ms_per_s: i64 = 1000;

comptime {
    assert(sleep_ms_max > 0);
    assert(ns_per_ms == 1_000_000);
}

pub fn now_ms() i64 {
    var value: linux.timespec = .{ .sec = 0, .nsec = 0 };

    _ = linux.clock_gettime(linux.CLOCK.MONOTONIC, &value);

    assert(value.sec >= 0);
    assert(value.nsec >= 0);

    const seconds: i64 = @intCast(value.sec);
    const nanoseconds: i64 = @intCast(value.nsec);
    const result = seconds * ms_per_s + @divFloor(nanoseconds, ns_per_ms);

    assert(result >= 0);

    return result;
}

pub fn sleep_ms(duration_ms: u32) void {
    assert(duration_ms <= sleep_ms_max);

    if (duration_ms == 0) {
        return;
    }

    const seconds = duration_ms / 1000;
    const milliseconds = duration_ms % 1000;

    const request: linux.timespec = .{
        .sec = @intCast(seconds),
        .nsec = @intCast(@as(i64, milliseconds) * ns_per_ms),
    };

    _ = linux.nanosleep(&request, null);
}

const testing = std.testing;

test "now_ms is monotonic across calls" {
    const first = now_ms();
    const second = now_ms();

    try testing.expect(second >= first);
    try testing.expect(first >= 0);
}

test "sleep_ms advances the monotonic clock" {
    const before = now_ms();

    sleep_ms(2);

    const after = now_ms();

    try testing.expect(after >= before);
}

test "sleep_ms of zero returns immediately" {
    sleep_ms(0);

    try testing.expect(now_ms() >= 0);
}
