const std = @import("std");

const keycode = @import("keycode.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const Tracker = struct {
    left_down: bool = false,
    right_down: bool = false,
    since_ms: ?i64 = null,
    hold_ms: u32 = hold_ms_default,
    triggered: bool = false,

    pub fn observe(tracker: *Tracker, code: Keycode, down: bool, now_ms: i64) void {
        assert(now_ms >= 0);

        switch (code) {
            .shift_left => tracker.left_down = down,
            .shift_right => tracker.right_down = down,
            else => return,
        }

        if (!tracker.is_armed()) {
            tracker.since_ms = null;
            tracker.triggered = false;

            return;
        }

        if (tracker.since_ms == null) {
            tracker.since_ms = now_ms;
        }

        assert(tracker.since_ms != null);
    }

    pub fn poll(tracker: *Tracker, now_ms: i64) bool {
        assert(now_ms >= 0);

        if (!tracker.is_armed()) return false;
        if (tracker.triggered) return false;

        const since_ms = tracker.since_ms orelse return false;
        const held_ms = now_ms - since_ms;

        assert(held_ms >= 0);

        if (held_ms < tracker.hold_ms) {
            return false;
        }

        tracker.triggered = true;

        return true;
    }

    pub fn is_armed(tracker: *const Tracker) bool {
        return tracker.left_down and tracker.right_down;
    }
};

pub const hold_ms_default: u32 = 2000;

comptime {
    assert(hold_ms_default >= 500);
}

const testing = std.testing;

test "both shifts held past the threshold trip the tracker once" {
    var tracker = Tracker{};

    tracker.observe(.shift_left, true, 1000);
    tracker.observe(.shift_right, true, 1000);

    try testing.expect(tracker.is_armed());
    try testing.expect(!tracker.poll(1000 + hold_ms_default - 1));
    try testing.expect(tracker.poll(1000 + hold_ms_default));
    try testing.expect(!tracker.poll(1000 + hold_ms_default * 2));
}

test "the hold is timed from the second shift" {
    var tracker = Tracker{};

    tracker.observe(.shift_left, true, 0);
    tracker.observe(.shift_right, true, 500);

    try testing.expect(!tracker.poll(hold_ms_default));
    try testing.expect(tracker.poll(500 + hold_ms_default));
}

test "a repeated shift press keeps the original start" {
    var tracker = Tracker{};

    tracker.observe(.shift_left, true, 0);
    tracker.observe(.shift_right, true, 0);
    tracker.observe(.shift_right, true, hold_ms_default - 10);

    try testing.expect(tracker.poll(hold_ms_default));
}

test "releasing either shift disarms the tracker and allows a fresh trip" {
    var tracker = Tracker{};

    tracker.observe(.shift_left, true, 0);
    tracker.observe(.shift_right, true, 0);

    try testing.expect(tracker.poll(hold_ms_default));

    tracker.observe(.shift_left, false, hold_ms_default + 1);

    try testing.expect(!tracker.is_armed());
    try testing.expect(!tracker.poll(hold_ms_default * 4));

    tracker.observe(.shift_left, true, hold_ms_default * 5);

    try testing.expect(!tracker.poll(hold_ms_default * 6 - 1));
    try testing.expect(tracker.poll(hold_ms_default * 6));
}

test "other keys never arm the tracker" {
    var tracker = Tracker{};

    tracker.observe(.a, true, 0);
    tracker.observe(.control_left, true, 0);
    tracker.observe(.shift, true, 0);

    try testing.expect(!tracker.is_armed());
    try testing.expect(!tracker.poll(hold_ms_default * 4));
}
