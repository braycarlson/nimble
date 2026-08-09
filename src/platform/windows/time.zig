const std = @import("std");

const win32 = @import("win32.zig");

const loop = @import("loop.zig");

const assert = std.debug.assert;

pub const tick_ms_max: i64 = std.math.maxInt(i64);
pub const sleep_ms_max: u32 = 1000 * 60 * 60;

pub fn now_ms() i64 {
    const ticks = win32.GetTickCount64();

    assert(ticks <= @as(u64, @intCast(tick_ms_max)));

    const result: i64 = @intCast(ticks);

    assert(result >= 0);

    return result;
}

pub fn sleep_ms(duration_ms: u32) void {
    assert(duration_ms <= sleep_ms_max);
    assert(!loop.is_loop_thread());

    win32.Sleep(duration_ms);
}
