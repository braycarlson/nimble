const std = @import("std");

const keycode = @import("../../keycode.zig");
const rescue_module = @import("../../rescue.zig");
const Runtime = @import("runtime.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

tracker: rescue_module.Tracker = .{},
regrab_ms: ?i64 = null,

const Rescue = @This();

const regrab_delay_ms: i64 = 3000;

comptime {
    assert(regrab_delay_ms >= 1000);
}

pub fn observe(rescue: *Rescue, runtime: *Runtime, code: Keycode, down: bool, now_ms: i64) void {
    assert(now_ms >= 0);

    if (!rescues(runtime)) return;

    rescue.tracker.observe(code, down, now_ms);

    if (!rescue.tracker.poll(now_ms)) return;

    runtime.release_grab();

    rescue.regrab_ms = now_ms + regrab_delay_ms;

    assert(runtime.mode() == .observe);
}

pub fn regrab_if_due(rescue: *Rescue, runtime: *Runtime, now_ms: i64) void {
    assert(now_ms >= 0);

    const due_ms = rescue.regrab_ms orelse return;
    if (now_ms < due_ms) return;

    rescue.reset();

    runtime.acquire_grab();

    assert(rescue.regrab_ms == null);
}

pub fn reset(rescue: *Rescue) void {
    rescue.tracker = .{};
    rescue.regrab_ms = null;

    assert(!rescue.tracker.is_armed());
}

fn rescues(runtime: *const Runtime) bool {
    if (!runtime.is_open()) return false;

    const options = runtime.options();
    return options.rescue and options.mode == .grab;
}

const testing = std.testing;

const hold_ms = rescue_module.hold_ms_default;

const Counter = struct {
    count: u32 = 0,

    fn on_released(context: *anyopaque) void {
        const counter: *Counter = @ptrCast(@alignCast(context));

        counter.count += 1;
    }
};

test "holding both shifts releases the grab and the regrab restores it" {
    var rescue: Rescue = .{};
    var runtime: Runtime = .{};
    var counter = Counter{};

    runtime.open(.{ .mode = .grab });
    defer runtime.close();

    runtime.set_release_callback(.{ .context = &counter, .invoke = Counter.on_released });
    defer runtime.set_release_callback(null);

    rescue.observe(&runtime, .shift_left, true, 0);
    rescue.observe(&runtime, .shift_right, true, 0);

    try testing.expectEqual(.grab, runtime.mode());

    rescue.observe(&runtime, .shift_right, true, hold_ms);

    try testing.expectEqual(.observe, runtime.mode());
    try testing.expectEqual(@as(u32, 1), counter.count);

    rescue.regrab_if_due(&runtime, hold_ms + regrab_delay_ms - 1);

    try testing.expectEqual(.observe, runtime.mode());

    rescue.regrab_if_due(&runtime, hold_ms + regrab_delay_ms);

    try testing.expectEqual(.grab, runtime.mode());
    try testing.expectEqual(@as(u32, 1), counter.count);
}

test "a disabled rescue never releases the grab" {
    var rescue: Rescue = .{};
    var runtime: Runtime = .{};

    runtime.open(.{ .mode = .grab, .rescue = false });
    defer runtime.close();

    rescue.observe(&runtime, .shift_left, true, 0);
    rescue.observe(&runtime, .shift_right, true, 0);
    rescue.observe(&runtime, .shift_right, true, hold_ms * 4);

    try testing.expectEqual(.grab, runtime.mode());
}

test "an observing runtime has nothing to rescue" {
    var rescue: Rescue = .{};
    var runtime: Runtime = .{};

    runtime.open(.{ .mode = .observe });
    defer runtime.close();

    rescue.observe(&runtime, .shift_left, true, 0);
    rescue.observe(&runtime, .shift_right, true, 0);
    rescue.observe(&runtime, .shift_right, true, hold_ms * 4);
    rescue.regrab_if_due(&runtime, hold_ms * 8);

    try testing.expectEqual(.observe, runtime.mode());
}
