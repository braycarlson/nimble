const std = @import("std");

const position_module = @import("../position.zig");

const assert = std.debug.assert;

const Position = position_module.Position;

const kind_count: u8 = 11;
const kind_max: u8 = 10;
const button_count: u8 = 5;
const button_max: u8 = 4;

pub const MouseEvent = struct {
    kind: Kind,
    payload: Payload = .none,
    injected: bool = false,
    time_ms: i64 = 0,

    pub const Kind = enum(u8) {
        left_down = 0,
        left_up = 1,
        right_down = 2,
        right_up = 3,
        middle_down = 4,
        middle_up = 5,
        x_down = 6,
        x_up = 7,
        wheel = 8,
        move = 9,
        other = 10,

        pub fn is_valid(kind: Kind) bool {
            const value = @backingInt(kind);

            assert(kind_max == 10);
            assert(kind_count == 11);

            return value <= kind_max;
        }

        pub fn is_button(kind: Kind) bool {
            assert(kind.is_valid());

            return kind.carries() == .button;
        }

        pub fn is_down(kind: Kind) bool {
            assert(kind.is_valid());

            return switch (kind) {
                .left_down, .right_down, .middle_down, .x_down => true,
                else => false,
            };
        }

        pub fn is_up(kind: Kind) bool {
            assert(kind.is_valid());

            return switch (kind) {
                .left_up, .right_up, .middle_up, .x_up => true,
                else => false,
            };
        }

        pub fn carries(kind: Kind) std.meta.Tag(Payload) {
            return switch (kind) {
                .left_down, .left_up => .button,
                .right_down, .right_up => .button,
                .middle_down, .middle_up => .button,
                .x_down, .x_up => .button,
                .wheel => .wheel,
                .move => .motion,
                .other => .none,
            };
        }
    };

    pub const Button = enum(u8) {
        left = 0,
        right = 1,
        middle = 2,
        x1 = 3,
        x2 = 4,

        pub fn is_valid(value: Button) bool {
            return @backingInt(value) <= button_max;
        }
    };

    pub const ButtonEvent = struct {
        button: Button,
        down: bool,
        position: ?Position = null,
    };

    pub const Motion = struct {
        delta_x: i32 = 0,
        delta_y: i32 = 0,
        position: ?Position = null,
    };

    pub const Wheel = struct {
        steps_vertical: i32 = 0,
        steps_horizontal: i32 = 0,
        position: ?Position = null,
    };

    pub const Payload = union(enum) {
        none: void,
        button: ButtonEvent,
        motion: Motion,
        wheel: Wheel,

        pub fn position(payload: Payload) ?Position {
            return switch (payload) {
                .none => null,
                .button => |event| event.position,
                .motion => |event| event.position,
                .wheel => |event| event.position,
            };
        }
    };

    pub const Stamp = struct {
        injected: bool = false,
        time_ms: i64 = 0,

        pub fn is_valid(stamp: Stamp) bool {
            return stamp.time_ms >= 0;
        }
    };

    pub fn from_button(event: ButtonEvent, stamp: Stamp) MouseEvent {
        assert(event.button.is_valid());
        assert(stamp.is_valid());

        const result = MouseEvent{
            .kind = kind_of(event),
            .payload = .{ .button = event },
            .injected = stamp.injected,
            .time_ms = stamp.time_ms,
        };

        assert(result.is_valid());

        return result;
    }

    pub fn from_motion(event: Motion, stamp: Stamp) MouseEvent {
        assert(stamp.is_valid());

        const result = MouseEvent{
            .kind = .move,
            .payload = .{ .motion = event },
            .injected = stamp.injected,
            .time_ms = stamp.time_ms,
        };

        assert(result.is_valid());

        return result;
    }

    pub fn from_wheel(event: Wheel, stamp: Stamp) MouseEvent {
        assert(stamp.is_valid());

        const result = MouseEvent{
            .kind = .wheel,
            .payload = .{ .wheel = event },
            .injected = stamp.injected,
            .time_ms = stamp.time_ms,
        };

        assert(result.is_valid());

        return result;
    }

    pub fn is_valid(event: *const MouseEvent) bool {
        if (!event.kind.is_valid()) {
            return false;
        }

        if (event.time_ms < 0) {
            return false;
        }

        if (event.kind.carries() != event.payload) {
            return false;
        }

        return switch (event.payload) {
            .none, .motion, .wheel => true,
            .button => |button_event| kind_of(button_event) == event.kind,
        };
    }

    pub fn is_button(event: *const MouseEvent) bool {
        assert(event.is_valid());

        return event.kind.is_button();
    }

    pub fn is_down(event: *const MouseEvent) bool {
        assert(event.is_valid());

        return event.kind.is_down();
    }

    pub fn is_up(event: *const MouseEvent) bool {
        assert(event.is_valid());

        return event.kind.is_up();
    }

    pub fn position(event: *const MouseEvent) ?Position {
        assert(event.is_valid());

        return event.payload.position();
    }

    pub fn button(event: *const MouseEvent) ?Button {
        assert(event.is_valid());

        return switch (event.payload) {
            .button => |button_event| button_event.button,
            else => null,
        };
    }
};

fn kind_of(event: MouseEvent.ButtonEvent) MouseEvent.Kind {
    assert(event.button.is_valid());

    const down = event.down;

    return switch (event.button) {
        .left => if (down) .left_down else .left_up,
        .right => if (down) .right_down else .right_up,
        .middle => if (down) .middle_down else .middle_up,
        .x1, .x2 => if (down) .x_down else .x_up,
    };
}

const testing = std.testing;

const MouseButton = MouseEvent.Button;
const MouseKind = MouseEvent.Kind;

test MouseEvent {
    const event = MouseEvent.from_button(
        .{ .button = .right, .down = true, .position = .{ .x = 10, .y = 20 } },
        .{ .injected = true, .time_ms = 99 },
    );

    try testing.expectEqual(MouseKind.right_down, event.kind);
    try testing.expectEqual(MouseButton.right, event.button().?);
    try testing.expect(event.position().?.eql(.{ .x = 10, .y = 20 }));
    try testing.expect(event.injected);
    try testing.expect(event.is_down());
}

test "the mouse kinds are stable" {
    const count = @typeInfo(MouseKind).@"enum".field_names.len;

    try testing.expectEqual(@as(u8, 0), @backingInt(MouseKind.left_down));
    try testing.expectEqual(@as(u8, 1), @backingInt(MouseKind.left_up));
    try testing.expectEqual(@as(u8, 2), @backingInt(MouseKind.right_down));
    try testing.expectEqual(@as(u8, 3), @backingInt(MouseKind.right_up));
    try testing.expectEqual(@as(u8, 4), @backingInt(MouseKind.middle_down));
    try testing.expectEqual(@as(u8, 5), @backingInt(MouseKind.middle_up));
    try testing.expectEqual(@as(u8, 6), @backingInt(MouseKind.x_down));
    try testing.expectEqual(@as(u8, 7), @backingInt(MouseKind.x_up));
    try testing.expectEqual(@as(u8, 8), @backingInt(MouseKind.wheel));
    try testing.expectEqual(@as(u8, 9), @backingInt(MouseKind.move));
    try testing.expectEqual(@as(u8, 10), @backingInt(MouseKind.other));
    try testing.expectEqual(@as(usize, kind_count), count);
}

test "every kind is valid and carries exactly one payload shape" {
    for (std.enums.values(MouseKind)) |kind| {
        try testing.expect(kind.is_valid());
        try testing.expect(kind.is_button() == (kind.carries() == .button));
    }
}

test "press and release partition the button kinds" {
    try testing.expect(MouseKind.left_down.is_down());
    try testing.expect(MouseKind.right_down.is_down());
    try testing.expect(MouseKind.middle_down.is_down());
    try testing.expect(MouseKind.x_down.is_down());
    try testing.expect(MouseKind.left_up.is_up());
    try testing.expect(MouseKind.right_up.is_up());
    try testing.expect(MouseKind.middle_up.is_up());
    try testing.expect(MouseKind.x_up.is_up());
    try testing.expect(!MouseKind.wheel.is_down());
    try testing.expect(!MouseKind.wheel.is_up());
    try testing.expect(!MouseKind.move.is_down());
    try testing.expect(!MouseKind.move.is_up());
}

test "both side buttons fold onto one kind" {
    try testing.expectEqual(MouseKind.left_down, kind_of(.{ .button = .left, .down = true }));
    try testing.expectEqual(MouseKind.left_up, kind_of(.{ .button = .left, .down = false }));
    try testing.expectEqual(MouseKind.right_down, kind_of(.{ .button = .right, .down = true }));
    try testing.expectEqual(MouseKind.middle_up, kind_of(.{ .button = .middle, .down = false }));
    try testing.expectEqual(MouseKind.x_down, kind_of(.{ .button = .x1, .down = true }));
    try testing.expectEqual(MouseKind.x_down, kind_of(.{ .button = .x2, .down = true }));
    try testing.expectEqual(MouseKind.x_up, kind_of(.{ .button = .x2, .down = false }));
}

test "a button event carries its button, kind, and stamp" {
    const event = MouseEvent.from_button(
        .{ .button = .right, .down = true, .position = .{ .x = 10, .y = 20 } },
        .{ .injected = true, .time_ms = 99 },
    );

    try testing.expect(event.is_valid());
    try testing.expect(event.is_button());
    try testing.expect(event.is_down());
    try testing.expect(!event.is_up());
    try testing.expectEqual(MouseKind.right_down, event.kind);
    try testing.expectEqual(MouseButton.right, event.button().?);
    try testing.expect(event.injected);
    try testing.expectEqual(@as(i64, 99), event.time_ms);
    try testing.expect(event.position().?.eql(.{ .x = 10, .y = 20 }));
}

test "a motion event carries signed deltas and an optional position" {
    const event = MouseEvent.from_motion(.{ .delta_x = -3, .delta_y = 7 }, .{});

    try testing.expect(event.is_valid());
    try testing.expect(!event.is_button());
    try testing.expectEqual(MouseKind.move, event.kind);
    try testing.expectEqual(@as(i32, -3), event.payload.motion.delta_x);
    try testing.expectEqual(@as(i32, 7), event.payload.motion.delta_y);
    try testing.expect(event.position() == null);
    try testing.expect(event.button() == null);
}

test "a wheel event carries signed steps on both axes" {
    const event = MouseEvent.from_wheel(.{ .steps_vertical = 2, .steps_horizontal = -1 }, .{});

    try testing.expect(event.is_valid());
    try testing.expectEqual(MouseKind.wheel, event.kind);
    try testing.expectEqual(@as(i32, 2), event.payload.wheel.steps_vertical);
    try testing.expectEqual(@as(i32, -1), event.payload.wheel.steps_horizontal);
}

test "an unclassified event carries no payload" {
    const event = MouseEvent{ .kind = .other };

    try testing.expect(event.is_valid());
    try testing.expect(!event.is_button());
    try testing.expect(event.position() == null);
    try testing.expect(event.button() == null);
}

test "is_valid rejects a payload that contradicts its kind" {
    const mismatched = MouseEvent{ .kind = .move, .payload = .{ .wheel = .{} } };

    const mislabelled = MouseEvent{
        .kind = .left_down,
        .payload = .{ .button = .{ .button = .right, .down = true } },
    };

    const stale = MouseEvent{ .kind = .move, .payload = .{ .motion = .{} }, .time_ms = -1 };

    try testing.expect(!mismatched.is_valid());
    try testing.expect(!mislabelled.is_valid());
    try testing.expect(!stale.is_valid());
}

test "the button values cover every physical button" {
    const count = @typeInfo(MouseButton).@"enum".field_names.len;

    try testing.expectEqual(@as(usize, button_count), count);

    for (std.enums.values(MouseButton)) |value| {
        try testing.expect(value.is_valid());
    }
}
