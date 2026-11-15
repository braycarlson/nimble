const std = @import("std");

const interface = @import("../interface.zig");

const assert = std.debug.assert;

const Tick = interface.Tick;
const TimerId = interface.TimerId;

armed: Armed = .{},
id_next: TimerId = 1,

const Timer = @This();

const Armed = struct {
    id: TimerId = 0,
    interval_ms: u32 = 0,
    deadline_ms: i64 = 0,
    tick: ?Tick = null,
    context: ?*anyopaque = null,

    fn is_valid(armed: *const Armed) bool {
        if (armed.id == 0) {
            return armed.tick == null;
        }

        return armed.tick != null and armed.interval_ms >= interface.timer_interval_ms_min;
    }
};

pub fn start(
    timer: *Timer,
    now_ms: i64,
    interval_ms: u32,
    tick: Tick,
    context: *anyopaque,
) ?TimerId {
    assert(now_ms >= 0);
    assert(interval_ms >= interface.timer_interval_ms_min);
    assert(interval_ms <= interface.timer_interval_ms_max);

    if (timer.armed.id != 0) {
        return null;
    }

    const id = timer.id_next;

    timer.id_next += 1;

    timer.armed = Armed{
        .id = id,
        .interval_ms = interval_ms,
        .deadline_ms = now_ms + interval_ms,
        .tick = tick,
        .context = context,
    };

    assert(timer.armed.is_valid());
    assert(id >= 1);

    return id;
}

pub fn stop(timer: *Timer, id: TimerId) bool {
    assert(id != 0);

    if (timer.armed.id == 0) {
        return false;
    }

    assert(timer.armed.id == id);

    timer.armed = .{};

    assert(timer.armed.is_valid());

    return true;
}

pub fn fire_due(timer: *Timer, now_ms: i64) u32 {
    assert(now_ms >= 0);
    assert(timer.armed.is_valid());

    if (timer.armed.id == 0) {
        return 0;
    }

    if (timer.armed.deadline_ms > now_ms) {
        return 0;
    }

    timer.armed.deadline_ms = now_ms + timer.armed.interval_ms;

    const tick = timer.armed.tick orelse return 0;
    const context = timer.armed.context orelse return 0;

    tick(context);

    return 1;
}

pub fn is_armed(timer: *const Timer) bool {
    return timer.armed.id != 0;
}

const testing = std.testing;

const Counter = struct {
    hits: u32 = 0,

    fn fire(context: *anyopaque) void {
        const counter: *Counter = @ptrCast(@alignCast(context));

        counter.hits += 1;
    }
};

test "no tick is armed before start" {
    var timer: Timer = .{};

    try testing.expect(!timer.is_armed());
    try testing.expectEqual(@as(u32, 0), timer.fire_due(0));
}

test "one tick arms and refuses a second" {
    var timer: Timer = .{};
    var counter = Counter{};

    const id = timer.start(0, 10, Counter.fire, &counter) orelse return error.TimerUnavailable;

    try testing.expect(id >= 1);
    try testing.expect(timer.is_armed());
    try testing.expect(timer.start(0, 10, Counter.fire, &counter) == null);
    try testing.expect(timer.stop(id));
    try testing.expect(!timer.is_armed());
    try testing.expect(!timer.stop(id));
}

test "an armed tick fires once its interval elapses" {
    var timer: Timer = .{};
    var counter = Counter{};

    const id = timer.start(0, 100, Counter.fire, &counter) orelse return error.TimerUnavailable;
    defer _ = timer.stop(id);

    try testing.expectEqual(@as(u32, 0), timer.fire_due(0));
    try testing.expectEqual(@as(u32, 1), timer.fire_due(100));
    try testing.expectEqual(@as(u32, 1), counter.hits);
    try testing.expectEqual(@as(u32, 0), timer.fire_due(100));
    try testing.expectEqual(@as(u32, 1), timer.fire_due(200));
    try testing.expectEqual(@as(u32, 2), counter.hits);
}
