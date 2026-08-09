const std = @import("std");

const win32 = @import("win32.zig");

const assert = std.debug.assert;

pub const Id = usize;
pub const Tick = *const fn () void;

pub const interval_ms_min: u32 = 1;
pub const interval_ms_max: u32 = 1000 * 60 * 60;

var tick_global: std.atomic.Value(?Tick) = std.atomic.Value(?Tick).init(null);
var id_global: std.atomic.Value(Id) = std.atomic.Value(Id).init(0);

comptime {
    assert(interval_ms_min >= 1);
    assert(interval_ms_max > interval_ms_min);
}

pub fn start(interval_ms: u32, tick: Tick) ?Id {
    assert(interval_ms >= interval_ms_min);
    assert(interval_ms <= interval_ms_max);

    if (id_global.load(.seq_cst) != 0) {
        return null;
    }

    const procedure = @as(win32.TIMERPROC, @ptrCast(&callback));
    const id = win32.SetTimer(null, 0, interval_ms, procedure);

    if (id == 0) {
        return null;
    }

    tick_global.store(tick, .seq_cst);
    id_global.store(id, .seq_cst);

    assert(id_global.load(.seq_cst) == id);

    return id;
}

pub fn stop(id: Id) bool {
    assert(id != 0);

    const armed = id_global.load(.seq_cst);

    if (armed == 0) {
        return false;
    }

    assert(armed == id);

    const status = win32.KillTimer(null, armed);

    tick_global.store(null, .seq_cst);
    id_global.store(0, .seq_cst);

    assert(id_global.load(.seq_cst) == 0);

    return status != 0;
}

pub fn is_armed() bool {
    return id_global.load(.seq_cst) != 0;
}

fn callback(_: win32.HWND, _: u32, _: usize, _: u32) callconv(.c) void {
    const tick = tick_global.load(.seq_cst) orelse return;

    tick();
}

const testing = std.testing;

const Noop = struct {
    fn fire() void {}
};

test "no tick is armed before start" {
    try testing.expect(!is_armed());
    try testing.expect(tick_global.load(.seq_cst) == null);
}

test "stopping an unarmed tick reports nothing was stopped" {
    try testing.expect(!is_armed());
    try testing.expect(!stop(1));
}

test "one global tick arms, refuses a second, and disarms" {
    const id = start(10, Noop.fire) orelse return error.TimerUnavailable;
    defer _ = stop(id);

    try testing.expect(is_armed());
    try testing.expect(start(10, Noop.fire) == null);
    try testing.expect(tick_global.load(.seq_cst) != null);
}

test "stopping the armed tick clears the callback" {
    const id = start(10, Noop.fire) orelse return error.TimerUnavailable;

    _ = stop(id);

    try testing.expect(!is_armed());
    try testing.expect(tick_global.load(.seq_cst) == null);
    try testing.expect(!stop(id));
}
