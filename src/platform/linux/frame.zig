const std = @import("std");

const evdev = @import("evdev.zig");
const mouse_event = @import("../../event/mouse.zig");

const Motion = mouse_event.Motion;
const Mouse = mouse_event.Mouse;
const Stamp = mouse_event.Stamp;
const Wheel = mouse_event.Wheel;

pub const Axes = struct {
    motion: Motion = .{},
    wheel: Wheel = .{},
    has_motion: bool = false,
    has_wheel: bool = false,

    pub fn add(axes: *Axes, raw: *const evdev.Event) void {
        if (raw.type != evdev.EV_REL) {
            return;
        }

        switch (raw.code) {
            evdev.REL_X => {
                axes.motion.delta_x += raw.value;
                axes.has_motion = true;
            },
            evdev.REL_Y => {
                axes.motion.delta_y += raw.value;
                axes.has_motion = true;
            },
            evdev.REL_WHEEL => {
                axes.wheel.steps_vertical += raw.value;
                axes.has_wheel = true;
            },
            evdev.REL_HWHEEL => {
                axes.wheel.steps_horizontal += raw.value;
                axes.has_wheel = true;
            },
            else => {},
        }
    }

    pub fn is_motion_axis(code: u16) bool {
        return code == evdev.REL_X or code == evdev.REL_Y;
    }

    pub fn is_wheel_axis(code: u16) bool {
        return code == evdev.REL_WHEEL or code == evdev.REL_HWHEEL;
    }

    pub fn motion_event(axes: *const Axes, stamp: Stamp) ?Mouse {
        if (!axes.has_motion) {
            return null;
        }

        return Mouse.from_motion(axes.motion, stamp);
    }

    pub fn wheel_event(axes: *const Axes, stamp: Stamp) ?Mouse {
        if (!axes.has_wheel) {
            return null;
        }

        return Mouse.from_wheel(axes.wheel, stamp);
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

const testing = std.testing;

test "an empty frame produces no neutral event" {
    var axes = Axes{};

    try testing.expect(!axes.has_motion);
    try testing.expect(!axes.has_wheel);
    try testing.expect(axes.motion_event(.{}) == null);
    try testing.expect(axes.wheel_event(.{}) == null);
}

test "motion axes coalesce into a single neutral event" {
    var axes = Axes{};

    axes.add(&relative(evdev.REL_X, 3));
    axes.add(&relative(evdev.REL_Y, -2));
    axes.add(&relative(evdev.REL_X, 4));

    const event = axes.motion_event(.{ .time_ms = 5 }) orelse return error.MissingMotion;

    try testing.expect(event.is_valid());
    try testing.expectEqual(mouse_event.Kind.move, event.kind);
    try testing.expectEqual(@as(i32, 7), event.payload.motion.delta_x);
    try testing.expectEqual(@as(i32, -2), event.payload.motion.delta_y);
    try testing.expectEqual(@as(i64, 5), event.time_ms);
    try testing.expect(event.position() == null);
}

test "wheel axes coalesce into one signed neutral event per direction" {
    var axes = Axes{};

    axes.add(&relative(evdev.REL_WHEEL, 1));
    axes.add(&relative(evdev.REL_WHEEL, 1));
    axes.add(&relative(evdev.REL_HWHEEL, -1));

    const event = axes.wheel_event(.{}) orelse return error.MissingWheel;

    try testing.expect(event.is_valid());
    try testing.expectEqual(mouse_event.Kind.wheel, event.kind);
    try testing.expectEqual(@as(i32, 2), event.payload.wheel.steps_vertical);
    try testing.expectEqual(@as(i32, -1), event.payload.wheel.steps_horizontal);
}

test "a scroll down carries a negative step, matching the Windows detent sign" {
    var axes = Axes{};

    axes.add(&relative(evdev.REL_WHEEL, -1));

    const event = axes.wheel_event(.{}) orelse return error.MissingWheel;

    try testing.expectEqual(@as(i32, -1), event.payload.wheel.steps_vertical);
    try testing.expectEqual(@as(i32, 0), event.payload.wheel.steps_horizontal);
}

test "motion and wheel in one frame stay separate events" {
    var axes = Axes{};

    axes.add(&relative(evdev.REL_X, 1));
    axes.add(&relative(evdev.REL_WHEEL, 1));

    try testing.expect(axes.has_motion);
    try testing.expect(axes.has_wheel);
    try testing.expect(axes.motion_event(.{}) != null);
    try testing.expect(axes.wheel_event(.{}) != null);
}

test "non relative events never reach the axes" {
    var axes = Axes{};

    axes.add(&evdev.Event{
        .time = .{ .sec = 0, .usec = 0 },
        .type = evdev.EV_KEY,
        .code = 30,
        .value = evdev.value_down,
    });

    try testing.expect(!axes.has_motion);
    try testing.expect(!axes.has_wheel);
}

test "unknown relative axes are ignored" {
    var axes = Axes{};

    axes.add(&relative(0x0A, 5));

    try testing.expect(!axes.has_motion);
    try testing.expect(!axes.has_wheel);
}

test "axis classification splits motion from wheel" {
    try testing.expect(Axes.is_motion_axis(evdev.REL_X));
    try testing.expect(Axes.is_motion_axis(evdev.REL_Y));
    try testing.expect(!Axes.is_motion_axis(evdev.REL_WHEEL));
    try testing.expect(Axes.is_wheel_axis(evdev.REL_WHEEL));
    try testing.expect(Axes.is_wheel_axis(evdev.REL_HWHEEL));
    try testing.expect(!Axes.is_wheel_axis(evdev.REL_X));
}
