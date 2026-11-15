test {
    _ = @import("platform/linux.zig");
    _ = @import("platform/linux/clipboard.zig");
    _ = @import("platform/linux/device.zig");
    _ = @import("platform/linux/evdev.zig");
    _ = @import("platform/linux/frame.zig");
    _ = @import("platform/linux/hotplug.zig");
    _ = @import("platform/linux/keyboard.zig");
    _ = @import("platform/linux/loop.zig");
    _ = @import("platform/linux/monitor.zig");
    _ = @import("platform/linux/mouse.zig");
    _ = @import("platform/linux/remote/client.zig");
    _ = @import("platform/linux/remote/protocol.zig");
    _ = @import("platform/linux/rescue.zig");
    _ = @import("platform/linux/runtime.zig");
    _ = @import("platform/linux/simulate/key.zig");
    _ = @import("platform/linux/simulate/mouse.zig");
    _ = @import("platform/linux/simulate/text.zig");
    _ = @import("platform/linux/state.zig");
    _ = @import("platform/linux/suspension.zig");
    _ = @import("platform/linux/sync.zig");
    _ = @import("platform/linux/time.zig");
    _ = @import("platform/linux/timer.zig");
    _ = @import("platform/linux/uinput.zig");
    _ = @import("platform/linux/wayland/client.zig");
    _ = @import("platform/linux/wayland/data_control.zig");
    _ = @import("platform/linux/wayland/fd.zig");
    _ = @import("platform/linux/wayland/output.zig");
    _ = @import("platform/linux/wayland/wire.zig");
}

const std = @import("std");

const Linux = @import("platform/linux.zig");
const Runtime = @import("platform/linux/runtime.zig");
const time = @import("platform/linux/time.zig");
const Timer = @import("platform/linux/timer.zig");
const TimerRegistryType = @import("registry/timer.zig").TimerRegistryType;

const assert = std.debug.assert;
const linux = std.os.linux;
const posix = std.posix;
const testing = std.testing;

const Registry = TimerRegistryType(4);

const poll_attempt_max: u32 = 400;
const poll_timeout_ms: u32 = 10;
const tick_interval_ms: u32 = 10;

const Ticker = struct {
    hits: u32 = 0,

    fn on_tick(context: *anyopaque) void {
        const ticker: *Ticker = @ptrCast(@alignCast(context));

        ticker.hits += 1;
    }
};

fn registry_tick(context: *anyopaque) void {
    const registry: *Registry = @ptrCast(@alignCast(context));

    registry.tick(time.now_ms());
}

fn watch_added(context: *anyopaque, fd: posix.fd_t) Timer.WatchError!void {
    const runtime: *Runtime = @ptrCast(@alignCast(context));

    assert(fd >= 0);

    runtime.watch(fd) catch return Timer.WatchError.WatchFailed;
}

fn watch_removed(context: *anyopaque, fd: posix.fd_t) void {
    const runtime: *Runtime = @ptrCast(@alignCast(context));

    assert(fd >= 0);

    runtime.unwatch(fd);
}

fn open_session(backend: *Linux) !void {
    backend.wire();

    const session = &backend.runtime.session;

    try testing.expect(!session.opened);

    const created = linux.epoll_create1(linux.EPOLL.CLOEXEC);

    if (linux.errno(created) != .SUCCESS) {
        return error.EpollUnavailable;
    }

    session.epoll = @intCast(created);
    session.options = .{ .mode = .observe };
    session.opened = true;

    try testing.expect(session.epoll >= 0);
}

fn drive_until_tick(backend: *Linux, ticker: *const Ticker) !void {
    var attempt: u32 = 0;

    while (attempt < poll_attempt_max) : (attempt += 1) {
        if (ticker.hits > 0) {
            return;
        }

        try testing.expect(backend.loop_poll(poll_timeout_ms));
    }

    return error.TimerNeverFired;
}

test "the Linux backend satisfies the interface" {
    try testing.expect(Linux.capabilities.clipboard);
    try testing.expect(!Linux.capabilities.injected_flag_exact);
    try testing.expect(Linux.capabilities.monitor_query);
    try testing.expect(!Linux.capabilities.window_filter);
    try testing.expect(!Linux.capabilities.window_targeted_input);
}

test "backend time is monotonic through the interface" {
    var backend: Linux = undefined;

    backend.wire();

    const first = backend.now_ms();
    const second = backend.now_ms();

    try testing.expect(second >= first);
}

test "a timer armed before the watch registers still ticks through the loop" {
    var backend: Linux = undefined;
    var registry = Registry.init();
    var ticker = Ticker{};

    try open_session(&backend);
    defer backend.runtime.close();

    const id = try registry.register(tick_interval_ms, Ticker.on_tick, &ticker, .{});

    const armed = backend.timer.start(tick_interval_ms, registry_tick, &registry) orelse {
        return error.TimerUnavailable;
    };

    defer _ = backend.timer.stop(armed);

    const watch = Timer.Watch{
        .context = &backend.runtime,
        .add = watch_added,
        .remove = watch_removed,
    };

    try backend.timer.set_watch(watch);
    defer backend.timer.clear_watch();

    try testing.expect(backend.timer.handle() >= 0);

    try registry.start(id, time.now_ms());
    try drive_until_tick(&backend, &ticker);

    try testing.expect(ticker.hits >= 1);
}

test "a timer armed after the watch registers ticks through the loop" {
    var backend: Linux = undefined;
    var registry = Registry.init();
    var ticker = Ticker{};

    try open_session(&backend);
    defer backend.runtime.close();

    const watch = Timer.Watch{
        .context = &backend.runtime,
        .add = watch_added,
        .remove = watch_removed,
    };

    try backend.timer.set_watch(watch);
    defer backend.timer.clear_watch();

    const id = try registry.register(tick_interval_ms, Ticker.on_tick, &ticker, .{});

    const armed = backend.timer.start(tick_interval_ms, registry_tick, &registry) orelse {
        return error.TimerUnavailable;
    };

    defer _ = backend.timer.stop(armed);

    try testing.expect(backend.timer.handle() >= 0);

    try registry.start(id, time.now_ms());
    try drive_until_tick(&backend, &ticker);

    try testing.expect(ticker.hits >= 1);
}
