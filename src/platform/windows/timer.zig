const std = @import("std");

const interface = @import("../interface.zig");
const win32 = @import("win32.zig");

const assert = std.debug.assert;

const Tick = interface.Tick;
const TimerId = interface.TimerId;

tick: std.atomic.Value(?Tick) = .init(null),
context: std.atomic.Value(?*anyopaque) = .init(null),
id: std.atomic.Value(TimerId) = .init(0),

const Timer = @This();

pub fn start(
    timer: *Timer,
    interval_ms: u32,
    tick: Tick,
    context: *anyopaque,
    procedure: win32.TIMERPROC,
) ?TimerId {
    assert(interval_ms >= interface.timer_interval_ms_min);
    assert(interval_ms <= interface.timer_interval_ms_max);

    if (timer.id.load(.seq_cst) != 0) {
        return null;
    }

    const id = win32.SetTimer(null, 0, interval_ms, procedure);

    if (id == 0) {
        return null;
    }

    timer.context.store(context, .seq_cst);
    timer.tick.store(tick, .seq_cst);
    timer.id.store(id, .seq_cst);

    assert(timer.id.load(.seq_cst) == id);

    return id;
}

pub fn stop(timer: *Timer, id: TimerId) bool {
    assert(id != 0);

    const armed = timer.id.load(.seq_cst);

    if (armed == 0) {
        return false;
    }

    assert(armed == id);

    const status = win32.KillTimer(null, armed);

    timer.tick.store(null, .seq_cst);
    timer.context.store(null, .seq_cst);
    timer.id.store(0, .seq_cst);

    assert(timer.id.load(.seq_cst) == 0);

    return status != 0;
}

pub fn is_armed(timer: *const Timer) bool {
    return timer.id.load(.seq_cst) != 0;
}

pub fn fire(timer: *const Timer) void {
    const tick = timer.tick.load(.seq_cst) orelse return;
    const context = timer.context.load(.seq_cst) orelse return;

    tick(context);
}

const testing = std.testing;

const Noop = struct {
    fn fire(_: *anyopaque) void {}
};

fn ignore(_: ?win32.HWND, _: u32, _: usize, _: u32) callconv(.c) void {}

test "no tick is armed before start" {
    const timer: Timer = .{};

    try testing.expect(!timer.is_armed());
    try testing.expect(timer.tick.load(.seq_cst) == null);
}

test "stopping an unarmed tick reports nothing was stopped" {
    var timer: Timer = .{};

    try testing.expect(!timer.is_armed());
    try testing.expect(!timer.stop(1));
}

test "one tick arms, refuses a second, and disarms" {
    var timer: Timer = .{};
    var context: u8 = 0;

    const id = timer.start(10, Noop.fire, &context, ignore) orelse return error.TimerUnavailable;
    defer _ = timer.stop(id);

    try testing.expect(timer.is_armed());
    try testing.expect(timer.start(10, Noop.fire, &context, ignore) == null);
    try testing.expect(timer.tick.load(.seq_cst) != null);
}

test "stopping the armed tick clears the callback" {
    var timer: Timer = .{};
    var context: u8 = 0;

    const id = timer.start(10, Noop.fire, &context, ignore) orelse return error.TimerUnavailable;

    _ = timer.stop(id);

    try testing.expect(!timer.is_armed());
    try testing.expect(timer.tick.load(.seq_cst) == null);
    try testing.expect(!timer.stop(id));
}
