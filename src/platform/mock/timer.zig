const std = @import("std");

const time = @import("time.zig");

const assert = std.debug.assert;

pub const Id = usize;
pub const Tick = *const fn () void;

pub const interval_ms_min: u32 = 1;
pub const interval_ms_max: u32 = 1000 * 60 * 60;

const Armed = struct {
    id: Id = 0,
    interval_ms: u32 = 0,
    next_ms: i64 = 0,
    tick: ?Tick = null,

    fn is_valid(armed: *const Armed) bool {
        if (armed.id == 0) {
            return armed.tick == null;
        }

        return armed.tick != null and armed.interval_ms >= interval_ms_min;
    }
};

var armed_global: Armed = .{};
var next_id: Id = 1;

comptime {
    assert(interval_ms_min >= 1);
    assert(interval_ms_max > interval_ms_min);
}

pub fn start(interval_ms: u32, tick: Tick) ?Id {
    assert(interval_ms >= interval_ms_min);
    assert(interval_ms <= interval_ms_max);

    if (armed_global.id != 0) {
        return null;
    }

    const id = next_id;

    next_id += 1;

    armed_global = Armed{
        .id = id,
        .interval_ms = interval_ms,
        .next_ms = time.now_ms() + interval_ms,
        .tick = tick,
    };

    assert(armed_global.is_valid());
    assert(id >= 1);

    return id;
}

pub fn stop(id: Id) bool {
    assert(id != 0);

    if (armed_global.id == 0) {
        return false;
    }

    assert(armed_global.id == id);

    armed_global = .{};

    assert(armed_global.is_valid());

    return true;
}

pub fn fire_due() u32 {
    if (armed_global.id == 0) {
        return 0;
    }

    const now = time.now_ms();

    if (armed_global.next_ms > now) {
        return 0;
    }

    armed_global.next_ms = now + armed_global.interval_ms;

    const tick = armed_global.tick orelse return 0;

    tick();

    return 1;
}

pub fn is_armed() bool {
    return armed_global.id != 0;
}

pub fn reset() void {
    armed_global = .{};
    next_id = 1;

    assert(!is_armed());
}

const testing = std.testing;

const Counter = struct {
    var hits: u32 = 0;

    fn fire() void {
        hits += 1;
    }
};

test "no tick is armed_global before start" {
    reset();

    try testing.expect(!is_armed());
    try testing.expectEqual(@as(u32, 0), fire_due());
}

test "one global tick arms and refuses a second" {
    reset();

    const id = start(10, Counter.fire) orelse return error.TimerUnavailable;

    try testing.expect(id >= 1);
    try testing.expect(is_armed());
    try testing.expect(start(10, Counter.fire) == null);
    try testing.expect(stop(id));
    try testing.expect(!is_armed());
    try testing.expect(!stop(id));

    reset();
}

test "an armed_global tick fires once its interval elapses" {
    reset();
    time.reset();

    Counter.hits = 0;

    const id = start(100, Counter.fire) orelse return error.TimerUnavailable;
    defer _ = stop(id);

    try testing.expectEqual(@as(u32, 0), fire_due());

    time.advance(100);

    try testing.expectEqual(@as(u32, 1), fire_due());
    try testing.expectEqual(@as(u32, 1), Counter.hits);
    try testing.expectEqual(@as(u32, 0), fire_due());

    time.advance(100);

    try testing.expectEqual(@as(u32, 1), fire_due());
    try testing.expectEqual(@as(u32, 2), Counter.hits);

    reset();
    time.reset();
}
