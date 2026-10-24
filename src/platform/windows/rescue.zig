const std = @import("std");

const keycode = @import("../../keycode.zig");
const rescue_mod = @import("../../rescue.zig");
const runtime = @import("runtime.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

const regrab_delay_ms: i64 = 3000;

var tracker: rescue_mod.Tracker = .{};
var regrab_ms: ?i64 = null;

comptime {
    assert(regrab_delay_ms >= 1000);
}

pub fn observe(code: Keycode, down: bool, now_ms: i64) void {
    assert(now_ms >= 0);

    if (!rescues()) return;

    tracker.observe(code, down, now_ms);

    if (!tracker.poll(now_ms)) return;

    runtime.release_grab();

    regrab_ms = now_ms + regrab_delay_ms;

    assert(runtime.mode() == .observe);
}

pub fn regrab_if_due(now_ms: i64) void {
    assert(now_ms >= 0);

    const due_ms = regrab_ms orelse return;
    if (now_ms < due_ms) return;

    reset();

    runtime.acquire_grab();

    assert(regrab_ms == null);
}

pub fn reset() void {
    tracker = .{};
    regrab_ms = null;

    assert(!tracker.is_armed());
}

fn rescues() bool {
    if (!runtime.is_open()) return false;

    const options = runtime.options();
    return options.rescue and options.mode == .grab;
}

const testing = std.testing;

const hold_ms = rescue_mod.hold_ms_default;

const Released = struct {
    var count: u32 = 0;

    fn on_released() void {
        count += 1;
    }
};

test "holding both shifts releases the grab and the regrab restores it" {
    runtime.close();
    reset();

    try runtime.open(.{ .mode = .grab });
    defer runtime.close();

    Released.count = 0;

    runtime.set_release_callback(Released.on_released);
    defer runtime.set_release_callback(null);

    observe(.shift_left, true, 0);
    observe(.shift_right, true, 0);

    try testing.expectEqual(runtime.Mode.grab, runtime.mode());

    observe(.shift_right, true, hold_ms);

    try testing.expectEqual(runtime.Mode.observe, runtime.mode());
    try testing.expectEqual(@as(u32, 1), Released.count);

    regrab_if_due(hold_ms + regrab_delay_ms - 1);

    try testing.expectEqual(runtime.Mode.observe, runtime.mode());

    regrab_if_due(hold_ms + regrab_delay_ms);

    try testing.expectEqual(runtime.Mode.grab, runtime.mode());
    try testing.expectEqual(@as(u32, 1), Released.count);
}

test "a disabled rescue never releases the grab" {
    runtime.close();
    reset();

    try runtime.open(.{ .mode = .grab, .rescue = false });
    defer runtime.close();

    observe(.shift_left, true, 0);
    observe(.shift_right, true, 0);
    observe(.shift_right, true, hold_ms * 4);

    try testing.expectEqual(runtime.Mode.grab, runtime.mode());
}

test "an observing runtime has nothing to rescue" {
    runtime.close();
    reset();

    try runtime.open(.{ .mode = .observe });
    defer runtime.close();

    observe(.shift_left, true, 0);
    observe(.shift_right, true, 0);
    observe(.shift_right, true, hold_ms * 4);
    regrab_if_due(hold_ms * 8);

    try testing.expectEqual(runtime.Mode.observe, runtime.mode());
}
