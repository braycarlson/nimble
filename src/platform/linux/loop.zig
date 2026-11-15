const std = @import("std");

const Device = @import("device.zig").Device;
const evdev = @import("evdev.zig");
const frame_module = @import("frame.zig");
const Hotplug = @import("hotplug.zig");
const key_event = @import("../../event.zig").key;
const Keyboard = @import("keyboard.zig");
const mapping = @import("keycode.zig");
const Mouse = @import("mouse.zig");
const mouse_event = @import("../../event.zig").mouse;
const Rescue = @import("rescue.zig");
const Runtime = @import("runtime.zig");
const time = @import("time.zig");
const Timer = @import("timer.zig");
const uinput = @import("uinput.zig");

const assert = std.debug.assert;
const linux = std.os.linux;
const log = std.log.scoped(.nimble);
const posix = std.posix;

const Axes = frame_module.Axes;
const Key = key_event.Key;
const MouseEvent = mouse_event.MouseEvent;
const MouseButton = MouseEvent.Button;
const Stamp = MouseEvent.Stamp;

frame: Frame = .{},
stopped: bool = false,
peers: Peers,

const Loop = @This();

pub const Peers = struct {
    hotplug: *Hotplug,
    keyboard: *Keyboard,
    mouse: *Mouse,
    rescue: *Rescue,
    runtime: *Runtime,
    timer: *Timer,
};

const event_batch_max: u16 = 64;
const frame_event_max: u16 = 64;
const wake_event_max: u16 = 16;
const drain_reads_max: u16 = 64;
const poll_timeout_ms_default: u32 = 10;
const interrupt_retry_max: u8 = 8;

const Frame = struct {
    events: [frame_event_max]evdev.Event = undefined,
    keep: [frame_event_max]bool = @splat(true),
    count: u16 = 0,
    virtual: bool = false,
    resyncing: bool = false,
    dropped: bool = false,

    fn is_valid(frame: *const Frame) bool {
        if (frame.resyncing) {
            if (frame.count != 0) return false;
        }

        return frame.count <= frame_event_max;
    }
};

comptime {
    assert(event_batch_max > 0);
    assert(frame_event_max > 0);
    assert(wake_event_max > 0);
    assert(drain_reads_max > 0);
    assert(poll_timeout_ms_default > 0);
    assert(interrupt_retry_max > 0);
}

pub fn run(loop: *Loop) void {
    assert(loop.peers.runtime.is_open());

    loop.stopped = false;

    while (loop.poll(poll_timeout_ms_default)) {
        assert(loop.peers.runtime.is_open());
    }

    assert(loop.stopped or !loop.peers.runtime.is_open());
}

pub fn stop(loop: *Loop) void {
    loop.stopped = true;

    assert(loop.stopped);
}

pub fn poll(loop: *Loop, timeout_ms: u32) bool {
    const session = &loop.peers.runtime.session;

    if (loop.stopped) return false;
    if (!session.opened) return false;

    assert(session.epoll >= 0);

    loop.peers.runtime.suspend_if_requested();
    loop.peers.runtime.regrab_if_requested();
    loop.peers.runtime.reselect_if_due();

    var wakes: [wake_event_max]linux.epoll_event = undefined;
    var attempt: u8 = 0;
    var ready: usize = 0;

    while (attempt < interrupt_retry_max) : (attempt += 1) {
        const count = linux.epoll_wait(session.epoll, &wakes, wake_event_max, @intCast(timeout_ms));
        const errno = linux.errno(count);

        if (errno == .SUCCESS) {
            ready = @intCast(count);

            break;
        }

        if (errno != .INTR) {
            loop.peers.runtime.release_grab();
            loop.stop();

            return false;
        }
    }

    assert(attempt <= interrupt_retry_max);

    if (attempt == interrupt_retry_max) {
        return !loop.stopped;
    }

    assert(ready <= wake_event_max);

    var index: usize = 0;

    while (index < ready) : (index += 1) {
        loop.drain(wakes[index].data.fd);
    }

    assert(index == ready);

    loop.rescue_local(time.now_ms());
    loop.rescue_shared();

    return !loop.stopped;
}

fn rescue_local(loop: *Loop, now_ms: i64) void {
    assert(now_ms >= 0);

    if (!loop.rescues()) {
        return;
    }

    if (!loop.peers.rescue.poll(now_ms)) {
        return;
    }

    log.info("rescue: chord held, releasing and signalling siblings", .{});

    loop.peers.rescue.share_signal(now_ms);

    loop.peers.runtime.release_grab();
    loop.peers.runtime.schedule_regrab();
}

pub fn rescues(loop: *const Loop) bool {
    const session = &loop.peers.runtime.session;
    return session.options.rescue and session.grabs();
}

fn rescue_shared(loop: *Loop) void {
    const session = &loop.peers.runtime.session;

    if (!session.options.rescue) {
        return;
    }

    if (!loop.peers.rescue.share_tripped()) {
        return;
    }

    log.info("rescue: sibling signalled, releasing", .{});

    loop.peers.runtime.release_grab();
    loop.peers.runtime.schedule_regrab();
}

fn drain(loop: *Loop, fd: posix.fd_t) void {
    if (fd == loop.peers.timer.handle()) {
        _ = loop.peers.timer.drain();

        return;
    }

    if (fd == loop.peers.hotplug.handle()) {
        if (loop.peers.hotplug.drain()) {
            loop.peers.runtime.refresh();
        }

        return;
    }

    const source = loop.peers.runtime.session.inputs.find(fd) orelse {
        loop.peers.runtime.unwatch(fd);

        return;
    };

    if (!loop.drain_device(source)) {
        log.warn("drain: source {s} is dead, refreshing", .{source.name()});

        loop.peers.runtime.refresh();
    }
}

fn drain_device(loop: *Loop, source: *const Device) bool {
    assert(source.is_open());
    assert(!loop.frame.resyncing);
    assert(!loop.frame.dropped);

    loop.frame.virtual = is_synthetic(source);

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
            loop.push(&batch[index]);
        }

        assert(index == count);
    }

    assert(reads <= drain_reads_max);

    loop.flush();

    if (loop.frame.dropped) {
        log.warn("drain: kernel dropped events on {s}, resyncing", .{source.name()});

        loop.resync_source(source);
    }

    loop.frame.resyncing = false;
    loop.frame.dropped = false;

    assert(!loop.frame.resyncing);
    assert(!loop.frame.dropped);

    return alive;
}

fn push(loop: *Loop, raw: *const evdev.Event) void {
    assert(loop.frame.is_valid());

    if (raw.type == evdev.EV_SYN) {
        if (raw.code == evdev.SYN_DROPPED) {
            loop.push_dropped();

            return;
        }

        if (raw.code == evdev.SYN_REPORT) {
            loop.push_report();

            return;
        }
    }

    if (loop.frame.resyncing) {
        return;
    }

    if (loop.frame.count == frame_event_max) {
        loop.flush();
    }

    assert(loop.frame.count < frame_event_max);

    loop.frame.events[loop.frame.count] = raw.*;
    loop.frame.keep[loop.frame.count] = true;
    loop.frame.count += 1;
}

fn push_dropped(loop: *Loop) void {
    assert(loop.frame.is_valid());

    loop.frame.count = 0;
    loop.frame.resyncing = true;
    loop.frame.dropped = true;

    assert(loop.frame.count == 0);
    assert(loop.frame.resyncing);
    assert(loop.frame.is_valid());
}

fn push_report(loop: *Loop) void {
    assert(loop.frame.is_valid());

    if (!loop.frame.resyncing) {
        loop.flush();

        return;
    }

    loop.frame.count = 0;
    loop.frame.resyncing = false;

    assert(!loop.frame.resyncing);
    assert(loop.frame.is_valid());
}

fn resync_source(loop: *Loop, source: *const Device) void {
    assert(source.is_open());
    assert(source.kind != .other);

    const session = &loop.peers.runtime.session;

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

fn flush(loop: *Loop) void {
    assert(loop.frame.is_valid());

    const count = loop.frame.count;

    if (count == 0) {
        return;
    }

    loop.frame.count = 0;

    const stamp = Stamp{ .injected = loop.frame.virtual, .time_ms = time.now_ms() };

    var axes = Axes{};
    var index: u16 = 0;

    while (index < count) : (index += 1) {
        const raw = &loop.frame.events[index];

        if (raw.type == evdev.EV_KEY) {
            loop.frame.keep[index] = !loop.dispatch_key(raw, stamp);

            continue;
        }

        axes.add(raw);
    }

    assert(index == count);

    const block_motion = loop.blocks(axes.motion_event(stamp));
    const block_wheel = loop.blocks(axes.wheel_event(stamp));

    loop.mark_pointer_axes(count, block_motion, block_wheel);
    loop.refeed(count);
}

fn blocks(loop: *Loop, event: ?MouseEvent) bool {
    if (event) |value| assert(value.is_valid());

    const value = event orelse return false;
    return loop.feed(value);
}

fn mark_pointer_axes(loop: *Loop, count: u16, block_motion: bool, block_wheel: bool) void {
    assert(count <= frame_event_max);

    var index: u16 = 0;

    while (index < count) : (index += 1) {
        const raw = &loop.frame.events[index];

        if (raw.type != evdev.EV_REL) {
            continue;
        }

        if (Axes.is_motion_axis(raw.code)) {
            loop.frame.keep[index] = !block_motion;
        }

        if (Axes.is_wheel_axis(raw.code)) {
            loop.frame.keep[index] = !block_wheel;
        }
    }

    assert(index == count);
}

fn dispatch_key(loop: *Loop, raw: *const evdev.Event, stamp: Stamp) bool {
    assert(raw.type == evdev.EV_KEY);
    assert(stamp.is_valid());

    if (button_of(raw.code)) |button| {
        return loop.dispatch_button(button, raw, stamp);
    }

    const native: u8 = if (raw.code <= 255) @intCast(raw.code) else return false;
    const code = mapping.from_native(native) orelse return false;
    const down = raw.value != evdev.value_up;

    if (loop.rescues()) {
        _ = loop.peers.rescue.observe(code, down, time.now_ms());
    }

    const key = Key{
        .value = code,
        .down = down,
        .injected = stamp.injected,
        .time_ms = stamp.time_ms,
    };

    const response = loop.peers.keyboard.feed(&key);

    assert(response.is_valid());

    return response.should_block();
}

fn dispatch_button(loop: *Loop, button: MouseButton, raw: *const evdev.Event, stamp: Stamp) bool {
    assert(raw.type == evdev.EV_KEY);
    assert(stamp.is_valid());

    const down = raw.value != evdev.value_up;
    return loop.feed(MouseEvent.from_button(.{ .button = button, .down = down }, stamp));
}

fn feed(loop: *Loop, event: MouseEvent) bool {
    assert(event.is_valid());

    const response = loop.peers.mouse.feed(&event);

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

fn refeed(loop: *Loop, count: u16) void {
    assert(count <= frame_event_max);

    const session = &loop.peers.runtime.session;

    if (session.options.mode == .observe) {
        return;
    }

    var wrote_keyboard = false;
    var wrote_mouse = false;
    var index: u16 = 0;

    while (index < count) : (index += 1) {
        const raw = &loop.frame.events[index];
        const pointer = is_pointer_event(raw);
        const target = if (pointer) &session.mouse_out else &session.keyboard_out;

        if (!target.is_open()) {
            continue;
        }

        if (!should_forward(target, raw, loop.frame.keep[index])) {
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

fn is_synthetic(source: *const Device) bool {
    assert(source.origin != .own);

    return source.virtual and source.origin == .direct;
}

const testing = std.testing;

const Harness = struct {
    hotplug: Hotplug = .{},
    keyboard: Keyboard = .{},
    mouse: Mouse = .{},
    rescue: Rescue = .{},
    runtime: Runtime = .{ .peers = undefined },
    timer: Timer = .{},
    loop: Loop = .{ .peers = undefined },

    fn wire(harness: *Harness) *Loop {
        harness.loop = .{
            .peers = .{
                .hotplug = &harness.hotplug,
                .keyboard = &harness.keyboard,
                .mouse = &harness.mouse,
                .rescue = &harness.rescue,
                .runtime = &harness.runtime,
                .timer = &harness.timer,
            },
        };

        assert(!harness.runtime.is_open());

        return &harness.loop;
    }
};

fn relative(code: u16, value: i32) evdev.Event {
    return evdev.Event{
        .time = .{ .sec = 0, .usec = 0 },
        .type = evdev.EV_REL,
        .code = code,
        .value = value,
    };
}

test "polling a closed runtime is inert and reports the loop unrunnable" {
    var harness = Harness{};

    const loop = harness.wire();

    try testing.expect(!harness.runtime.is_open());
    try testing.expect(!loop.poll(0));
}

test "stop makes the loop unrunnable" {
    var harness = Harness{};

    const loop = harness.wire();

    loop.stop();

    try testing.expect(!loop.poll(0));
}

test "the rescue runs only when it is requested and the devices are grabbed" {
    var harness = Harness{};

    const loop = harness.wire();
    const session = &harness.runtime.session;

    session.opened = true;
    session.options = .{ .mode = .grab, .rescue = true };

    try testing.expect(loop.rescues());

    session.options = .{ .mode = .grab, .rescue = false };

    try testing.expect(!loop.rescues());

    session.options = .{ .mode = .observe, .rescue = true };

    try testing.expect(!loop.rescues());

    session.opened = false;
    session.options = .{ .mode = .grab, .rescue = true };

    try testing.expect(!loop.rescues());
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
    const hardware = Device{ .virtual = false, .origin = .direct };
    const foreign = Device{ .virtual = true, .origin = .direct };
    const sibling = Device{ .virtual = true, .origin = .sibling };

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
    assert(code <= evdev.KEY_MAX);
    assert(value >= evdev.value_up);
    assert(value <= evdev.value_repeat);

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

test "a frame accumulates relative axes until its report arrives" {
    var harness = Harness{};

    const loop = harness.wire();

    const axes = [_]evdev.Event{
        relative(evdev.REL_X, 3),
        relative(evdev.REL_Y, -2),
        relative(evdev.REL_X, 4),
    };

    for (&axes) |*raw| {
        loop.push(raw);
    }

    try testing.expectEqual(@as(u16, 3), loop.frame.count);

    const report = evdev.Event{
        .time = .{ .sec = 0, .usec = 0 },
        .type = evdev.EV_SYN,
        .code = evdev.SYN_REPORT,
        .value = 0,
    };

    loop.push(&report);

    try testing.expectEqual(@as(u16, 0), loop.frame.count);
}

test "a frame never overruns its bound" {
    var harness = Harness{};

    const loop = harness.wire();

    const raw = relative(evdev.REL_X, 1);

    var index: u16 = 0;

    while (index < frame_event_max * 2 + 1) : (index += 1) {
        loop.push(&raw);

        try testing.expect(loop.frame.is_valid());
    }
}

fn syn_event(code: u16) evdev.Event {
    return evdev.Event{
        .time = .{ .sec = 0, .usec = 0 },
        .type = evdev.EV_SYN,
        .code = code,
        .value = 0,
    };
}

test "a dropped packet discards the partial frame the kernel already lost" {
    var harness = Harness{};

    const loop = harness.wire();

    loop.push(&relative(evdev.REL_X, 3));

    try testing.expectEqual(@as(u16, 1), loop.frame.count);

    loop.push(&syn_event(evdev.SYN_DROPPED));

    try testing.expectEqual(@as(u16, 0), loop.frame.count);
    try testing.expect(loop.frame.resyncing);
    try testing.expect(loop.frame.dropped);
    try testing.expect(loop.frame.is_valid());
}

test "events between a drop and its report never reach the frame" {
    var harness = Harness{};

    const loop = harness.wire();

    loop.push(&syn_event(evdev.SYN_DROPPED));
    loop.push(&relative(evdev.REL_X, 9));
    loop.push(&relative(evdev.REL_Y, 9));

    try testing.expectEqual(@as(u16, 0), loop.frame.count);
    try testing.expect(loop.frame.resyncing);

    loop.push(&syn_event(evdev.SYN_REPORT));

    try testing.expectEqual(@as(u16, 0), loop.frame.count);
    try testing.expect(!loop.frame.resyncing);
    try testing.expect(loop.frame.dropped);
}

test "the frame buffers again once a drop closes" {
    var harness = Harness{};

    const loop = harness.wire();

    loop.push(&syn_event(evdev.SYN_DROPPED));
    loop.push(&syn_event(evdev.SYN_REPORT));
    loop.push(&relative(evdev.REL_X, 2));
    loop.push(&relative(evdev.REL_Y, 2));

    try testing.expectEqual(@as(u16, 2), loop.frame.count);
    try testing.expect(!loop.frame.resyncing);
    try testing.expect(loop.frame.is_valid());
}

test "a resyncing frame holding events is invalid" {
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
