const std = @import("std");

const device = @import("device.zig");
const evdev = @import("evdev.zig");
const frame_mod = @import("frame.zig");
const hotplug = @import("hotplug.zig");
const key_event = @import("../../event/key.zig");
const keyboard = @import("keyboard.zig");
const mapping = @import("keycode.zig");
const mouse = @import("mouse.zig");
const mouse_event = @import("../../event/mouse.zig");
const rescue = @import("rescue.zig");
const runtime = @import("runtime.zig");
const time = @import("time.zig");
const timer = @import("timer.zig");
const uinput = @import("uinput.zig");

const assert = std.debug.assert;
const linux = std.os.linux;
const log = std.log.scoped(.nimble);
const posix = std.posix;

const Axes = frame_mod.Axes;
const Key = key_event.Key;
const Mouse = mouse_event.Mouse;
const MouseButton = mouse_event.Button;
const Stamp = mouse_event.Stamp;

pub const event_batch_max: u16 = 64;
pub const frame_event_max: u16 = 64;
pub const wake_event_max: u16 = 16;
pub const drain_reads_max: u16 = 64;
pub const poll_timeout_ms_default: u32 = 10;
pub const interrupt_retry_max: u8 = 8;

const Frame = struct {
    events: [frame_event_max]evdev.Event = undefined,
    keep: [frame_event_max]bool = @splat(true),
    count: u16 = 0,
    virtual: bool = false,
    resyncing: bool = false,
    dropped: bool = false,

    fn is_valid(frame: *const Frame) bool {
        if (frame.resyncing and frame.count != 0) {
            return false;
        }

        return frame.count <= frame_event_max;
    }
};

var frame_global: Frame = .{};
var stopped: bool = false;

comptime {
    assert(event_batch_max > 0);
    assert(frame_event_max > 0);
    assert(wake_event_max > 0);
    assert(drain_reads_max > 0);
    assert(poll_timeout_ms_default > 0);
    assert(interrupt_retry_max > 0);
}

pub fn run() void {
    assert(runtime.is_open());

    stopped = false;

    while (poll(poll_timeout_ms_default)) {
        assert(runtime.is_open());
    }

    assert(stopped or !runtime.is_open());
}

pub fn stop() void {
    stopped = true;

    assert(stopped);
}

pub fn poll(timeout_ms: u32) bool {
    const session = runtime.current();

    if (stopped or !session.opened) {
        return false;
    }

    assert(session.epoll >= 0);

    runtime.suspend_if_requested();
    runtime.regrab_if_requested();
    runtime.reselect_if_due();

    var wakes: [wake_event_max]linux.epoll_event = undefined;
    var attempt: u8 = 0;
    var ready: usize = 0;

    while (attempt < interrupt_retry_max) : (attempt += 1) {
        const count = linux.epoll_wait(
            session.epoll,
            &wakes,
            wake_event_max,
            @intCast(timeout_ms),
        );

        const errno = posix.errno(count);

        if (errno == .SUCCESS) {
            ready = @intCast(count);

            break;
        }

        if (errno != .INTR) {
            runtime.release_grab();
            stop();

            return false;
        }
    }

    assert(attempt <= interrupt_retry_max);

    if (attempt == interrupt_retry_max) {
        return !stopped;
    }

    assert(ready <= wake_event_max);

    var index: usize = 0;

    while (index < ready) : (index += 1) {
        drain(wakes[index].data.fd);
    }

    assert(index == ready);

    rescue_local(time.now_ms());
    rescue_shared();

    return !stopped;
}

fn rescue_local(now_ms: i64) void {
    if (!rescues()) {
        return;
    }

    if (!rescue.poll(now_ms)) {
        return;
    }

    log.info("rescue: chord held, releasing and signalling siblings", .{});

    rescue.share_signal(now_ms);

    runtime.release_grab();
    runtime.schedule_regrab();
}

pub fn rescues() bool {
    const session = runtime.current();

    return session.options.rescue and session.grabs();
}

fn rescue_shared() void {
    const session = runtime.current();

    if (!session.options.rescue) {
        return;
    }

    if (!rescue.share_tripped()) {
        return;
    }

    log.info("rescue: sibling signalled, releasing", .{});

    runtime.release_grab();
    runtime.schedule_regrab();
}

fn drain(fd: posix.fd_t) void {
    if (fd == timer.handle()) {
        _ = timer.drain();

        return;
    }

    if (fd == hotplug.handle()) {
        if (hotplug.drain()) {
            runtime.refresh();
        }

        return;
    }

    const source = runtime.current().devices.find(fd) orelse {
        runtime.unwatch(fd);

        return;
    };

    if (!drain_device(source)) {
        log.warn("drain: source {s} is dead, refreshing", .{source.name()});

        runtime.refresh();
    }
}

fn drain_device(source: *const device.Device) bool {
    assert(source.is_open());
    assert(!frame_global.resyncing);
    assert(!frame_global.dropped);

    frame_global.virtual = is_synthetic(source);

    var reads: u16 = 0;
    var alive = true;

    while (reads < drain_reads_max) : (reads += 1) {
        var batch: [event_batch_max]evdev.Event = undefined;

        const count = evdev.read_events(source.fd, &batch) catch {
            alive = false;

            break;
        };

        assert(count <= event_batch_max);

        if (count == 0) {
            break;
        }

        var index: usize = 0;

        while (index < count) : (index += 1) {
            push(&batch[index]);
        }

        assert(index == count);
    }

    assert(reads <= drain_reads_max);

    flush();

    if (frame_global.dropped) {
        log.warn("drain: kernel dropped events on {s}, resyncing", .{source.name()});

        resync_source(source);
    }

    frame_global.resyncing = false;
    frame_global.dropped = false;

    assert(!frame_global.resyncing);
    assert(!frame_global.dropped);

    return alive;
}

fn push(raw: *const evdev.Event) void {
    assert(frame_global.is_valid());

    if (raw.type == evdev.EV_SYN and raw.code == evdev.SYN_DROPPED) {
        push_dropped();

        return;
    }

    if (raw.type == evdev.EV_SYN and raw.code == evdev.SYN_REPORT) {
        push_report();

        return;
    }

    if (frame_global.resyncing) {
        return;
    }

    if (frame_global.count == frame_event_max) {
        flush();
    }

    assert(frame_global.count < frame_event_max);

    frame_global.events[frame_global.count] = raw.*;
    frame_global.keep[frame_global.count] = true;
    frame_global.count += 1;
}

fn push_dropped() void {
    assert(frame_global.is_valid());

    frame_global.count = 0;
    frame_global.resyncing = true;
    frame_global.dropped = true;

    assert(frame_global.count == 0);
    assert(frame_global.resyncing);
    assert(frame_global.is_valid());
}

fn push_report() void {
    assert(frame_global.is_valid());

    if (!frame_global.resyncing) {
        flush();

        return;
    }

    frame_global.count = 0;
    frame_global.resyncing = false;

    assert(!frame_global.resyncing);
    assert(frame_global.is_valid());
}

fn resync_source(source: *const device.Device) void {
    assert(source.is_open());
    assert(source.kind != .other);

    const session = runtime.current();

    if (session.options.mode == .observe) {
        return;
    }

    const pointer = source.kind == .mouse;
    const target = if (pointer) &session.mouse_out else &session.keyboard_out;

    if (!target.is_open()) {
        return;
    }

    var capable: [evdev.KEY_BYTES]u8 = @splat(0);
    var pressed: [evdev.KEY_BYTES]u8 = @splat(0);

    evdev.key_bits(source.fd, &capable) catch return;
    evdev.key_state(source.fd, &pressed) catch return;

    var code: u16 = 0;
    var wrote = false;

    while (code <= evdev.KEY_MAX) : (code += 1) {
        if (!evdev.bit_is_set(&capable, code)) {
            continue;
        }

        if ((button_of(code) != null) != pointer) {
            continue;
        }

        const down = evdev.bit_is_set(&pressed, code);
        const value = if (down) evdev.value_down else evdev.value_up;

        target.emit(evdev.EV_KEY, code, value) catch continue;

        wrote = true;
    }

    assert(code == evdev.KEY_MAX + 1);

    if (wrote) {
        sync(target);
    }
}

fn flush() void {
    assert(frame_global.is_valid());

    const count = frame_global.count;

    if (count == 0) {
        return;
    }

    frame_global.count = 0;

    const stamp = Stamp{ .injected = frame_global.virtual, .time_ms = time.now_ms() };

    var axes = Axes{};
    var index: u16 = 0;

    while (index < count) : (index += 1) {
        const raw = &frame_global.events[index];

        if (raw.type == evdev.EV_KEY) {
            frame_global.keep[index] = !dispatch_key(raw, stamp);

            continue;
        }

        axes.add(raw);
    }

    assert(index == count);

    const block_motion = blocks(axes.motion_event(stamp));
    const block_wheel = blocks(axes.wheel_event(stamp));

    mark_pointer_axes(count, block_motion, block_wheel);
    refeed(count);
}

fn blocks(event: ?Mouse) bool {
    const value = event orelse return false;

    return feed(value);
}

fn mark_pointer_axes(count: u16, block_motion: bool, block_wheel: bool) void {
    assert(count <= frame_event_max);

    var index: u16 = 0;

    while (index < count) : (index += 1) {
        const raw = &frame_global.events[index];

        if (raw.type != evdev.EV_REL) {
            continue;
        }

        if (Axes.is_motion_axis(raw.code)) {
            frame_global.keep[index] = !block_motion;
        }

        if (Axes.is_wheel_axis(raw.code)) {
            frame_global.keep[index] = !block_wheel;
        }
    }

    assert(index == count);
}

fn dispatch_key(raw: *const evdev.Event, stamp: Stamp) bool {
    assert(raw.type == evdev.EV_KEY);

    if (button_of(raw.code)) |button| {
        return dispatch_button(button, raw, stamp);
    }

    const native: u8 = if (raw.code <= 255) @intCast(raw.code) else return false;
    const code = mapping.from_native(native) orelse return false;
    const down = raw.value != evdev.value_up;

    if (rescues()) {
        _ = rescue.observe(code, down, time.now_ms());
    }

    const key = Key{
        .value = code,
        .down = down,
        .injected = stamp.injected,
        .time_ms = stamp.time_ms,
    };

    const response = keyboard.feed(&key);

    assert(response.is_valid());

    return response.should_block();
}

fn dispatch_button(button: MouseButton, raw: *const evdev.Event, stamp: Stamp) bool {
    assert(raw.type == evdev.EV_KEY);

    const down = raw.value != evdev.value_up;

    return feed(Mouse.from_button(.{ .button = button, .down = down }, stamp));
}

fn feed(event: Mouse) bool {
    assert(event.is_valid());

    const response = mouse.feed(&event);

    assert(response.is_valid());

    return response.should_block();
}

pub fn button_of(code: u16) ?MouseButton {
    return switch (code) {
        evdev.BTN_LEFT => .left,
        evdev.BTN_RIGHT => .right,
        evdev.BTN_MIDDLE => .middle,
        evdev.BTN_SIDE => .x1,
        evdev.BTN_EXTRA => .x2,
        else => null,
    };
}

fn refeed(count: u16) void {
    assert(count <= frame_event_max);

    const session = runtime.current();

    if (session.options.mode == .observe) {
        return;
    }

    var wrote_keyboard = false;
    var wrote_mouse = false;
    var index: u16 = 0;

    while (index < count) : (index += 1) {
        const raw = &frame_global.events[index];
        const pointer = is_pointer_event(raw);
        const target = if (pointer) &session.mouse_out else &session.keyboard_out;

        if (!target.is_open()) {
            continue;
        }

        if (!should_forward(target, raw, frame_global.keep[index])) {
            continue;
        }

        target.emit(raw.type, raw.code, raw.value) catch continue;

        if (pointer) {
            wrote_mouse = true;
        } else {
            wrote_keyboard = true;
        }
    }

    assert(index == count);

    if (wrote_keyboard) {
        sync(&session.keyboard_out);
    }

    if (wrote_mouse) {
        sync(&session.mouse_out);
    }
}

fn should_forward(target: *const uinput.Device, raw: *const evdev.Event, keep: bool) bool {
    if (raw.type != evdev.EV_KEY) {
        return keep;
    }

    const held = target.is_down(raw.code);

    if (raw.value == evdev.value_up) {
        return held;
    }

    if (raw.value == evdev.value_repeat) {
        return keep and held;
    }

    assert(raw.value == evdev.value_down);

    return keep;
}

fn sync(target: *uinput.Device) void {
    target.sync() catch return;
}

fn is_pointer_event(raw: *const evdev.Event) bool {
    if (raw.type == evdev.EV_REL) {
        return true;
    }

    return raw.type == evdev.EV_KEY and button_of(raw.code) != null;
}

fn is_synthetic(source: *const device.Device) bool {
    assert(source.origin != .own);

    return source.virtual and source.origin == .direct;
}

const testing = std.testing;

fn relative(code: u16, value: i32) evdev.Event {
    return evdev.Event{
        .time = .{ .sec = 0, .usec = 0 },
        .type = evdev.EV_REL,
        .code = code,
        .value = value,
    };
}

test "polling a closed runtime is inert and reports the loop unrunnable" {
    stopped = false;

    try testing.expect(!runtime.is_open());
    try testing.expect(!poll(0));
}

test "stop makes the loop unrunnable" {
    stop();

    try testing.expect(!poll(0));

    stopped = false;
}

test "the rescue runs only when it is requested and the devices are grabbed" {
    const session = runtime.current();
    const saved_options = session.options;
    const saved_opened = session.opened;
    defer session.options = saved_options;
    defer session.opened = saved_opened;

    session.opened = true;
    session.options = .{ .mode = .grab, .rescue = true };

    try testing.expect(rescues());

    session.options = .{ .mode = .grab, .rescue = false };

    try testing.expect(!rescues());

    session.options = .{ .mode = .observe, .rescue = true };

    try testing.expect(!rescues());

    session.opened = false;
    session.options = .{ .mode = .grab, .rescue = true };

    try testing.expect(!rescues());
}

test "button codes map onto neutral buttons" {
    try testing.expectEqual(MouseButton.left, button_of(evdev.BTN_LEFT).?);
    try testing.expectEqual(MouseButton.right, button_of(evdev.BTN_RIGHT).?);
    try testing.expectEqual(MouseButton.middle, button_of(evdev.BTN_MIDDLE).?);
    try testing.expectEqual(MouseButton.x1, button_of(evdev.BTN_SIDE).?);
    try testing.expectEqual(MouseButton.x2, button_of(evdev.BTN_EXTRA).?);
    try testing.expect(button_of(30) == null);
    try testing.expect(button_of(0x999) == null);
}

test "a sibling source is relayed hardware input, not synthetic input" {
    const hardware = device.Device{ .virtual = false, .origin = .direct };
    const foreign = device.Device{ .virtual = true, .origin = .direct };
    const sibling = device.Device{ .virtual = true, .origin = .sibling };

    try testing.expect(!is_synthetic(&hardware));
    try testing.expect(is_synthetic(&foreign));
    try testing.expect(!is_synthetic(&sibling));
}

test "pointer events route to the virtual mouse, keys to the virtual keyboard" {
    const motion = evdev.Event{
        .time = .{ .sec = 0, .usec = 0 },
        .type = evdev.EV_REL,
        .code = evdev.REL_X,
        .value = 3,
    };

    const button = evdev.Event{
        .time = .{ .sec = 0, .usec = 0 },
        .type = evdev.EV_KEY,
        .code = evdev.BTN_LEFT,
        .value = evdev.value_down,
    };

    const letter = evdev.Event{
        .time = .{ .sec = 0, .usec = 0 },
        .type = evdev.EV_KEY,
        .code = 30,
        .value = evdev.value_down,
    };

    try testing.expect(is_pointer_event(&motion));
    try testing.expect(is_pointer_event(&button));
    try testing.expect(!is_pointer_event(&letter));
}

fn key_event_raw(code: u16, value: i32) evdev.Event {
    return evdev.Event{
        .time = .{ .sec = 0, .usec = 0 },
        .type = evdev.EV_KEY,
        .code = code,
        .value = value,
    };
}

test "a key up always follows a forwarded key down, even when blocked" {
    var target = uinput.Device{};

    const down = key_event_raw(30, evdev.value_down);
    const up = key_event_raw(30, evdev.value_up);

    try testing.expect(!should_forward(&target, &up, true));
    try testing.expect(should_forward(&target, &down, true));

    target.pressed[30 / 8] |= @as(u8, 1) << @truncate(30 % 8);

    try testing.expect(should_forward(&target, &up, false));
    try testing.expect(should_forward(&target, &up, true));
}

test "a blocked key down suppresses its repeats until the key is released" {
    var target = uinput.Device{};

    const repeat = key_event_raw(30, evdev.value_repeat);

    try testing.expect(!should_forward(&target, &repeat, true));
    try testing.expect(!should_forward(&target, &repeat, false));

    target.pressed[30 / 8] |= @as(u8, 1) << @truncate(30 % 8);

    try testing.expect(should_forward(&target, &repeat, true));
    try testing.expect(!should_forward(&target, &repeat, false));
}

test "non key events follow the middleware verdict unchanged" {
    const target = uinput.Device{};
    const motion = relative(evdev.REL_X, 3);

    try testing.expect(should_forward(&target, &motion, true));
    try testing.expect(!should_forward(&target, &motion, false));
}

test "a frame_global accumulates relative axes until its report arrives" {
    frame_global = .{};

    const axes = [_]evdev.Event{
        relative(evdev.REL_X, 3),
        relative(evdev.REL_Y, -2),
        relative(evdev.REL_X, 4),
    };

    for (&axes) |*raw| {
        push(raw);
    }

    try testing.expectEqual(@as(u16, 3), frame_global.count);

    const report = evdev.Event{
        .time = .{ .sec = 0, .usec = 0 },
        .type = evdev.EV_SYN,
        .code = evdev.SYN_REPORT,
        .value = 0,
    };

    push(&report);

    try testing.expectEqual(@as(u16, 0), frame_global.count);
}

test "a frame_global never overruns its bound" {
    frame_global = .{};

    const raw = relative(evdev.REL_X, 1);

    var index: u16 = 0;

    while (index < frame_event_max * 2 + 1) : (index += 1) {
        push(&raw);

        try testing.expect(frame_global.is_valid());
    }

    frame_global = .{};
}

fn syn_event(code: u16) evdev.Event {
    return evdev.Event{
        .time = .{ .sec = 0, .usec = 0 },
        .type = evdev.EV_SYN,
        .code = code,
        .value = 0,
    };
}

test "a dropped packet discards the partial frame_global the kernel already lost" {
    frame_global = .{};

    push(&relative(evdev.REL_X, 3));

    try testing.expectEqual(@as(u16, 1), frame_global.count);

    push(&syn_event(evdev.SYN_DROPPED));

    try testing.expectEqual(@as(u16, 0), frame_global.count);
    try testing.expect(frame_global.resyncing);
    try testing.expect(frame_global.dropped);
    try testing.expect(frame_global.is_valid());

    frame_global = .{};
}

test "events between a drop and its report never reach the frame_global" {
    frame_global = .{};

    push(&syn_event(evdev.SYN_DROPPED));
    push(&relative(evdev.REL_X, 9));
    push(&relative(evdev.REL_Y, 9));

    try testing.expectEqual(@as(u16, 0), frame_global.count);
    try testing.expect(frame_global.resyncing);

    push(&syn_event(evdev.SYN_REPORT));

    try testing.expectEqual(@as(u16, 0), frame_global.count);
    try testing.expect(!frame_global.resyncing);
    try testing.expect(frame_global.dropped);

    frame_global = .{};
}

test "the frame_global buffers again once a drop closes" {
    frame_global = .{};

    push(&syn_event(evdev.SYN_DROPPED));
    push(&syn_event(evdev.SYN_REPORT));
    push(&relative(evdev.REL_X, 2));
    push(&relative(evdev.REL_Y, 2));

    try testing.expectEqual(@as(u16, 2), frame_global.count);
    try testing.expect(!frame_global.resyncing);
    try testing.expect(frame_global.is_valid());

    frame_global = .{};
}

test "a resyncing frame_global holding events is invalid" {
    var probe = Frame{};

    probe.resyncing = true;
    probe.count = 1;

    try testing.expect(!probe.is_valid());

    probe.count = 0;

    try testing.expect(probe.is_valid());

    probe.resyncing = false;
    probe.count = frame_event_max;

    try testing.expect(probe.is_valid());
}
