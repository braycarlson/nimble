const std = @import("std");

const interface = @import("../interface.zig");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

const Tick = interface.Tick;
const TimerId = interface.TimerId;

descriptor: posix.fd_t = -1,
tick: ?Tick = null,
context: ?*anyopaque = null,
watch: ?Watch = null,

const Timer = @This();

pub const WatchError = error{
    WatchFailed,
};

pub const Watch = struct {
    context: *anyopaque,
    add: *const fn (context: *anyopaque, fd: posix.fd_t) WatchError!void,
    remove: *const fn (context: *anyopaque, fd: posix.fd_t) void,
};

pub fn set_watch(timer: *Timer, watch: Watch) WatchError!void {
    timer.watch = watch;

    assert(timer.watch != null);

    if (timer.descriptor >= 0) {
        try watch.add(watch.context, timer.descriptor);
    }
}

pub fn clear_watch(timer: *Timer) void {
    if (timer.descriptor >= 0) {
        if (timer.watch) |watch| {
            watch.remove(watch.context, timer.descriptor);
        }
    }

    timer.watch = null;

    assert(timer.watch == null);
}

pub fn start(timer: *Timer, interval_ms: u32, tick: Tick, context: *anyopaque) ?TimerId {
    assert(interval_ms >= interface.timer_interval_ms_min);
    assert(interval_ms <= interface.timer_interval_ms_max);

    if (timer.descriptor >= 0) {
        return null;
    }

    const flags = linux.TFD{ .NONBLOCK = true, .CLOEXEC = true };
    const created = linux.timerfd_create(.MONOTONIC, flags);

    if (linux.errno(created) != .SUCCESS) {
        return null;
    }

    const fd: posix.fd_t = @intCast(created);
    const seconds: i64 = interval_ms / 1000;
    const nanoseconds: i64 = @as(i64, interval_ms % 1000) * std.time.ns_per_ms;

    const spec = linux.itimerspec{
        .it_interval = .{ .sec = seconds, .nsec = nanoseconds },
        .it_value = .{ .sec = seconds, .nsec = nanoseconds },
    };

    const armed = linux.timerfd_settime(fd, .{}, &spec, null);

    if (linux.errno(armed) != .SUCCESS) {
        _ = linux.close(fd);

        return null;
    }

    timer.descriptor = fd;
    timer.tick = tick;
    timer.context = context;

    if (timer.watch) |watch| {
        watch.add(watch.context, fd) catch {
            timer.descriptor = -1;
            timer.tick = null;
            timer.context = null;

            _ = linux.close(fd);

            return null;
        };
    }

    assert(timer.descriptor >= 0);

    return @intCast(fd);
}

pub fn stop(timer: *Timer, id: TimerId) bool {
    assert(id != 0);

    if (timer.descriptor < 0) {
        return false;
    }

    assert(id == @as(TimerId, @intCast(timer.descriptor)));

    if (timer.watch) |watch| {
        watch.remove(watch.context, timer.descriptor);
    }

    _ = linux.close(timer.descriptor);

    timer.descriptor = -1;
    timer.tick = null;
    timer.context = null;

    assert(timer.descriptor < 0);

    return true;
}

pub fn handle(timer: *const Timer) posix.fd_t {
    return timer.descriptor;
}

pub fn drain(timer: *Timer) u32 {
    if (timer.descriptor < 0) {
        return 0;
    }

    var expirations: u64 = 0;
    const bytes = std.mem.asBytes(&expirations);

    _ = posix.read(timer.descriptor, bytes) catch return 0;

    if (expirations == 0) {
        return 0;
    }

    if (timer.tick) |tick| {
        if (timer.context) |context| tick(context);
    }

    assert(expirations >= 1);

    return @intCast(@min(expirations, std.math.maxInt(u32)));
}

const testing = std.testing;

const Watcher = struct {
    added: posix.fd_t = -1,
    removed: posix.fd_t = -1,

    fn watch(watcher: *Watcher) Watch {
        return .{ .context = watcher, .add = add, .remove = remove };
    }

    fn add(context: *anyopaque, fd: posix.fd_t) WatchError!void {
        const watcher: *Watcher = @ptrCast(@alignCast(context));

        watcher.added = fd;
    }

    fn remove(context: *anyopaque, fd: posix.fd_t) void {
        const watcher: *Watcher = @ptrCast(@alignCast(context));

        watcher.removed = fd;
    }
};

const Refuser = struct {
    refusals: u32 = 0,

    fn watch(refuser: *Refuser) Watch {
        return .{ .context = refuser, .add = add, .remove = remove };
    }

    fn add(context: *anyopaque, _: posix.fd_t) WatchError!void {
        const refuser: *Refuser = @ptrCast(@alignCast(context));

        refuser.refusals += 1;

        return WatchError.WatchFailed;
    }

    fn remove(_: *anyopaque, _: posix.fd_t) void {}
};

const Noop = struct {
    fn fire(_: *anyopaque) void {}
};

test "no timer is armed before start" {
    var timer: Timer = .{};

    try testing.expect(timer.handle() < 0);
    try testing.expectEqual(@as(u32, 0), timer.drain());
}

test "a timerfd arms and disarms" {
    var timer: Timer = .{};
    var context: u8 = 0;

    const id = timer.start(10, Noop.fire, &context) orelse return error.TimerUnavailable;

    try testing.expect(timer.handle() >= 0);
    try testing.expect(timer.start(10, Noop.fire, &context) == null);
    try testing.expect(timer.stop(id));
    try testing.expect(timer.handle() < 0);
    try testing.expect(!timer.stop(id));
}

test "a timerfd expires and drives its tick" {
    const Counter = struct {
        hits: u32 = 0,

        fn fire(context: *anyopaque) void {
            const counter: *@This() = @ptrCast(@alignCast(context));

            counter.hits += 1;
        }
    };

    var timer: Timer = .{};
    var counter = Counter{};

    const id = timer.start(5, Counter.fire, &counter) orelse return error.TimerUnavailable;
    defer _ = timer.stop(id);

    @import("time.zig").sleep_ms(30);

    const fired = timer.drain();

    try testing.expect(fired >= 1);
    try testing.expectEqual(@as(u32, 1), counter.hits);
}

test "a watch registered after the timer is armed adopts the live descriptor" {
    var timer: Timer = .{};
    var watcher = Watcher{};
    var context: u8 = 0;

    const id = timer.start(1000, Noop.fire, &context) orelse return error.TimerUnavailable;
    defer _ = timer.stop(id);

    try testing.expectEqual(@as(posix.fd_t, -1), watcher.added);

    try timer.set_watch(watcher.watch());
    defer timer.clear_watch();

    try testing.expectEqual(timer.handle(), watcher.added);
}

test "a timer armed after the watch registers itself immediately" {
    var timer: Timer = .{};
    var watcher = Watcher{};
    var context: u8 = 0;

    try timer.set_watch(watcher.watch());
    defer timer.clear_watch();

    try testing.expectEqual(@as(posix.fd_t, -1), watcher.added);

    const id = timer.start(1000, Noop.fire, &context) orelse return error.TimerUnavailable;
    defer _ = timer.stop(id);

    try testing.expectEqual(timer.handle(), watcher.added);
}

test "stopping a timer unregisters its descriptor before closing it" {
    var timer: Timer = .{};
    var watcher = Watcher{};
    var context: u8 = 0;

    try timer.set_watch(watcher.watch());
    defer timer.clear_watch();

    const id = timer.start(1000, Noop.fire, &context) orelse return error.TimerUnavailable;
    const fd = timer.handle();

    try testing.expect(fd >= 0);
    try testing.expect(timer.stop(id));
    try testing.expectEqual(fd, watcher.removed);
    try testing.expect(timer.handle() < 0);
}

test "clearing the watch releases a still armed descriptor" {
    var timer: Timer = .{};
    var watcher = Watcher{};
    var context: u8 = 0;

    try timer.set_watch(watcher.watch());

    const id = timer.start(1000, Noop.fire, &context) orelse return error.TimerUnavailable;
    defer _ = timer.stop(id);

    const fd = timer.handle();

    timer.clear_watch();

    try testing.expectEqual(fd, watcher.removed);
    try testing.expect(timer.handle() >= 0);
}

test "an unwatched timer arms and disarms without a registrar" {
    var timer: Timer = .{};
    const watcher = Watcher{};
    var context: u8 = 0;

    const id = timer.start(1000, Noop.fire, &context) orelse return error.TimerUnavailable;

    try testing.expect(timer.handle() >= 0);
    try testing.expect(timer.stop(id));
    try testing.expectEqual(@as(posix.fd_t, -1), watcher.added);
    try testing.expectEqual(@as(posix.fd_t, -1), watcher.removed);
}

test "a timer whose watch refuses registration never arms" {
    var timer: Timer = .{};
    var refuser = Refuser{};
    var context: u8 = 0;

    try timer.set_watch(refuser.watch());
    defer timer.clear_watch();

    try testing.expect(timer.start(1000, Noop.fire, &context) == null);
    try testing.expect(timer.handle() < 0);
}

test "adopting a live descriptor reports a refused watch" {
    var timer: Timer = .{};
    var refuser = Refuser{};
    var context: u8 = 0;

    const id = timer.start(1000, Noop.fire, &context) orelse return error.TimerUnavailable;
    defer _ = timer.stop(id);

    try testing.expectError(WatchError.WatchFailed, timer.set_watch(refuser.watch()));

    timer.clear_watch();
}
