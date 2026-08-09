const std = @import("std");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

pub const Id = usize;
pub const Tick = *const fn () void;

pub const WatchError = error{
    WatchFailed,
};

pub const Watch = *const fn (posix.fd_t) WatchError!void;
pub const Unwatch = *const fn (posix.fd_t) void;

pub const interval_ms_min: u32 = 1;
pub const interval_ms_max: u32 = 1000 * 60 * 60;
pub const ns_per_ms: i64 = 1000 * 1000;

var descriptor: posix.fd_t = -1;
var tick_global: ?Tick = null;
var watch_add: ?Watch = null;
var watch_remove: ?Unwatch = null;

comptime {
    assert(interval_ms_min >= 1);
    assert(interval_ms_max > interval_ms_min);
}

pub fn set_watch(add: Watch, remove: Unwatch) WatchError!void {
    watch_add = add;
    watch_remove = remove;

    assert(watch_add != null);

    if (descriptor >= 0) {
        try add(descriptor);
    }
}

pub fn clear_watch() void {
    if (descriptor >= 0) {
        if (watch_remove) |remove| {
            remove(descriptor);
        }
    }

    watch_add = null;
    watch_remove = null;

    assert(watch_add == null);
}

pub fn start(interval_ms: u32, tick: Tick) ?Id {
    assert(interval_ms >= interval_ms_min);
    assert(interval_ms <= interval_ms_max);

    if (descriptor >= 0) {
        return null;
    }

    const flags = linux.TFD{ .NONBLOCK = true, .CLOEXEC = true };
    const created = linux.timerfd_create(.MONOTONIC, flags);

    if (posix.errno(created) != .SUCCESS) {
        return null;
    }

    const fd: posix.fd_t = @intCast(created);
    const seconds: i64 = interval_ms / 1000;
    const nanoseconds: i64 = @as(i64, interval_ms % 1000) * ns_per_ms;

    const spec = linux.itimerspec{
        .it_interval = .{ .sec = seconds, .nsec = nanoseconds },
        .it_value = .{ .sec = seconds, .nsec = nanoseconds },
    };

    const armed = linux.timerfd_settime(fd, .{}, &spec, null);

    if (posix.errno(armed) != .SUCCESS) {
        _ = linux.close(fd);

        return null;
    }

    descriptor = fd;
    tick_global = tick;

    if (watch_add) |add| {
        add(fd) catch {
            descriptor = -1;
            tick_global = null;

            _ = linux.close(fd);

            return null;
        };
    }

    assert(descriptor >= 0);

    return @intCast(fd);
}

pub fn stop(id: Id) bool {
    assert(id != 0);

    if (descriptor < 0) {
        return false;
    }

    assert(id == @as(Id, @intCast(descriptor)));

    if (watch_remove) |remove| {
        remove(descriptor);
    }

    _ = linux.close(descriptor);

    descriptor = -1;
    tick_global = null;

    assert(descriptor < 0);

    return true;
}

pub fn handle() posix.fd_t {
    return descriptor;
}

pub fn drain() u32 {
    if (descriptor < 0) {
        return 0;
    }

    var expirations: u64 = 0;
    const bytes = std.mem.asBytes(&expirations);

    _ = posix.read(descriptor, bytes) catch return 0;

    if (expirations == 0) {
        return 0;
    }

    if (tick_global) |tick| {
        tick();
    }

    assert(expirations >= 1);

    return @intCast(@min(expirations, std.math.maxInt(u32)));
}

const testing = std.testing;

test "no timer is armed before start" {
    try testing.expect(handle() < 0);
    try testing.expectEqual(@as(u32, 0), drain());
}

test "a timerfd arms and disarms" {
    const id = start(10, Noop.fire) orelse return error.TimerUnavailable;

    try testing.expect(handle() >= 0);
    try testing.expect(start(10, Noop.fire) == null);
    try testing.expect(stop(id));
    try testing.expect(handle() < 0);
    try testing.expect(!stop(id));
}

test "a timerfd expires and drives its tick" {
    const Counter = struct {
        var hits: u32 = 0;

        fn fire() void {
            hits += 1;
        }
    };

    Counter.hits = 0;

    const id = start(5, Counter.fire) orelse return error.TimerUnavailable;
    defer _ = stop(id);

    @import("time.zig").sleep_ms(30);

    const fired = drain();

    try testing.expect(fired >= 1);
    try testing.expectEqual(@as(u32, 1), Counter.hits);
}

const Watcher = struct {
    var added: posix.fd_t = -1;
    var removed: posix.fd_t = -1;

    fn reset() void {
        added = -1;
        removed = -1;
    }

    fn add(fd: posix.fd_t) WatchError!void {
        added = fd;
    }

    fn remove(fd: posix.fd_t) void {
        removed = fd;
    }
};

const Refuser = struct {
    fn add(_: posix.fd_t) WatchError!void {
        return WatchError.WatchFailed;
    }

    fn remove(_: posix.fd_t) void {}
};

const Noop = struct {
    fn fire() void {}
};

test "a watch registered after the timer is armed adopts the live descriptor" {
    Watcher.reset();
    clear_watch();

    const id = start(1000, Noop.fire) orelse return error.TimerUnavailable;
    defer _ = stop(id);

    try testing.expectEqual(@as(posix.fd_t, -1), Watcher.added);

    try set_watch(Watcher.add, Watcher.remove);
    defer clear_watch();

    try testing.expectEqual(handle(), Watcher.added);
}

test "a timer armed after the watch registers itself immediately" {
    Watcher.reset();
    clear_watch();
    try set_watch(Watcher.add, Watcher.remove);
    defer clear_watch();

    try testing.expectEqual(@as(posix.fd_t, -1), Watcher.added);

    const id = start(1000, Noop.fire) orelse return error.TimerUnavailable;
    defer _ = stop(id);

    try testing.expectEqual(handle(), Watcher.added);
}

test "stopping a timer unregisters its descriptor before closing it" {
    Watcher.reset();
    clear_watch();
    try set_watch(Watcher.add, Watcher.remove);
    defer clear_watch();

    const id = start(1000, Noop.fire) orelse return error.TimerUnavailable;
    const fd = handle();

    try testing.expect(fd >= 0);
    try testing.expect(stop(id));
    try testing.expectEqual(fd, Watcher.removed);
    try testing.expect(handle() < 0);
}

test "clearing the watch releases a still armed descriptor" {
    Watcher.reset();
    clear_watch();
    try set_watch(Watcher.add, Watcher.remove);

    const id = start(1000, Noop.fire) orelse return error.TimerUnavailable;
    defer _ = stop(id);

    const fd = handle();

    clear_watch();

    try testing.expectEqual(fd, Watcher.removed);
    try testing.expect(handle() >= 0);
}

test "an unwatched timer arms and disarms without a registrar" {
    Watcher.reset();
    clear_watch();

    const id = start(1000, Noop.fire) orelse return error.TimerUnavailable;

    try testing.expect(handle() >= 0);
    try testing.expect(stop(id));
    try testing.expectEqual(@as(posix.fd_t, -1), Watcher.added);
    try testing.expectEqual(@as(posix.fd_t, -1), Watcher.removed);
}

test "a timer whose watch refuses registration never arms" {
    clear_watch();

    try set_watch(Refuser.add, Refuser.remove);
    defer clear_watch();

    try testing.expect(start(1000, Noop.fire) == null);
    try testing.expect(handle() < 0);
}

test "adopting a live descriptor reports a refused watch" {
    clear_watch();

    const id = start(1000, Noop.fire) orelse return error.TimerUnavailable;
    defer _ = stop(id);

    try testing.expectError(WatchError.WatchFailed, set_watch(Refuser.add, Refuser.remove));

    clear_watch();
}
