test {
    _ = @import("platform/linux/clipboard.zig");
    _ = @import("platform/linux/device.zig");
    _ = @import("platform/linux/evdev.zig");
    _ = @import("platform/linux/frame.zig");
    _ = @import("platform/linux/hook.zig");
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

const nimble = @import("root.zig");
const platform = @import("platform.zig");

const linux_loop = @import("platform/linux/loop.zig");
const linux_runtime = @import("platform/linux/runtime.zig");
const linux_timer = @import("platform/linux/timer.zig");

const linux = std.os.linux;
const posix = std.posix;
const testing = std.testing;

const poll_attempt_max: u32 = 400;
const poll_timeout_ms: u32 = 10;
const tick_interval_ms: u32 = 10;

const Ticker = struct {
    var hits: u32 = 0;

    fn on_tick(_: *anyopaque) void {
        hits += 1;
    }
};

fn watch_added(fd: posix.fd_t) linux_timer.WatchError!void {
    linux_runtime.watch(fd) catch return linux_timer.WatchError.WatchFailed;
}

fn watch_removed(fd: posix.fd_t) void {
    linux_runtime.unwatch(fd);
}

fn open_session() !void {
    const session = linux_runtime.current();

    try testing.expect(!session.opened);

    const created = linux.epoll_create1(linux.EPOLL.CLOEXEC);

    if (posix.errno(created) != .SUCCESS) {
        return error.EpollUnavailable;
    }

    session.epoll = @intCast(created);
    session.options = .{ .mode = .observe };
    session.opened = true;

    try testing.expect(session.epoll >= 0);
}

fn drive_until_tick() !void {
    var attempt: u32 = 0;

    while (attempt < poll_attempt_max) : (attempt += 1) {
        if (Ticker.hits > 0) {
            return;
        }

        try testing.expect(linux_loop.poll(poll_timeout_ms));
    }

    return error.TimerNeverFired;
}

test "the Linux backend satisfies the contract" {
    try testing.expect(platform.capabilities.clipboard);
    try testing.expect(!platform.capabilities.injected_flag_exact);
    try testing.expect(platform.capabilities.monitor_query);
    try testing.expect(!platform.capabilities.window_filter);
    try testing.expect(!platform.capabilities.window_targeted_input);
}

test "the core keyboard pipeline instantiates against the Linux backend" {
    const Keyboard = nimble.KeyboardType(.{});

    var hook = Keyboard.init();
    defer hook.deinit();

    try testing.expect(!hook.is_running());
    try testing.expect(!hook.is_blocked());
    try testing.expect(@sizeOf(Keyboard) > 0);
}

test "the core mouse pipeline instantiates against the Linux backend" {
    const Mouse = nimble.MouseType(.{});

    var hook = Mouse.init();
    defer hook.deinit();

    try testing.expect(!hook.is_running());
    try testing.expect(@sizeOf(Mouse) > 0);
}

test "backend time is monotonic through the contract" {
    const first = platform.backend.time.now_ms();
    const second = platform.backend.time.now_ms();

    try testing.expect(second >= first);
}

test "a timer armed before the watch registers still ticks through the loop" {
    Ticker.hits = 0;

    var registry = nimble.TimerRegistryType(4).init();
    var context: u8 = 0;

    try open_session();
    defer linux_runtime.close();

    const id = try registry.register(tick_interval_ms, Ticker.on_tick, &context, .{});

    registry.set_global();
    defer registry.clear_global();

    try linux_timer.set_watch(watch_added, watch_removed);
    defer linux_timer.clear_watch();

    try testing.expect(linux_timer.handle() >= 0);

    try registry.start(id);
    try drive_until_tick();

    try testing.expect(Ticker.hits >= 1);
}

test "a timer armed after the watch registers ticks through the loop" {
    Ticker.hits = 0;

    var registry = nimble.TimerRegistryType(4).init();
    var context: u8 = 0;

    try open_session();
    defer linux_runtime.close();

    try linux_timer.set_watch(watch_added, watch_removed);
    defer linux_timer.clear_watch();

    const id = try registry.register(tick_interval_ms, Ticker.on_tick, &context, .{});

    registry.set_global();
    defer registry.clear_global();

    try testing.expect(linux_timer.handle() >= 0);

    try registry.start(id);
    try drive_until_tick();

    try testing.expect(Ticker.hits >= 1);
}
