const std = @import("std");

const assert = std.debug.assert;

pub const kind_count: u8 = 11;
pub const kind_max: u8 = 10;
pub const button_count: u8 = 5;
pub const button_max: u8 = 4;

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
        const value = @intFromEnum(kind);

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

    pub fn from_button(button: Button, down: bool) Kind {
        assert(button.is_valid());

        return switch (button) {
            .left => if (down) .left_down else .left_up,
            .right => if (down) .right_down else .right_up,
            .middle => if (down) .middle_down else .middle_up,
            .x1, .x2 => if (down) .x_down else .x_up,
        };
    }
};

pub const Button = enum(u8) {
    left = 0,
    right = 1,
    middle = 2,
    x1 = 3,
    x2 = 4,

    pub fn is_valid(button: Button) bool {
        return @intFromEnum(button) <= button_max;
    }
};

pub const Position = struct {
    x: i32,
    y: i32,

    pub fn init(x: i32, y: i32) Position {
        return Position{ .x = x, .y = y };
    }

    pub fn eql(position: Position, other: Position) bool {
        return position.x == other.x and position.y == other.y;
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

pub const Mouse = struct {
    kind: Kind,
    payload: Payload = .none,
    injected: bool = false,
    time_ms: i64 = 0,

    pub fn from_button(event: ButtonEvent, stamp: Stamp) Mouse {
        assert(event.button.is_valid());
        assert(stamp.is_valid());

        const result = Mouse{
            .kind = Kind.from_button(event.button, event.down),
            .payload = .{ .button = event },
            .injected = stamp.injected,
            .time_ms = stamp.time_ms,
        };

        assert(result.is_valid());

        return result;
    }

    pub fn from_motion(event: Motion, stamp: Stamp) Mouse {
        assert(stamp.is_valid());

        const result = Mouse{
            .kind = .move,
            .payload = .{ .motion = event },
            .injected = stamp.injected,
            .time_ms = stamp.time_ms,
        };

        assert(result.is_valid());

        return result;
    }

    pub fn from_wheel(event: Wheel, stamp: Stamp) Mouse {
        assert(stamp.is_valid());

        const result = Mouse{
            .kind = .wheel,
            .payload = .{ .wheel = event },
            .injected = stamp.injected,
            .time_ms = stamp.time_ms,
        };

        assert(result.is_valid());

        return result;
    }

    pub fn is_valid(mouse: *const Mouse) bool {
        if (!mouse.kind.is_valid()) {
            return false;
        }

        if (mouse.time_ms < 0) {
            return false;
        }

        if (mouse.kind.carries() != mouse.payload) {
            return false;
        }

        return switch (mouse.payload) {
            .none, .motion, .wheel => true,
            .button => |event| Kind.from_button(event.button, event.down) == mouse.kind,
        };
    }

    pub fn is_button(mouse: *const Mouse) bool {
        assert(mouse.is_valid());

        return mouse.kind.is_button();
    }

    pub fn is_down(mouse: *const Mouse) bool {
        assert(mouse.is_valid());

        return mouse.kind.is_down();
    }

    pub fn is_up(mouse: *const Mouse) bool {
        assert(mouse.is_valid());

        return mouse.kind.is_up();
    }

    pub fn position(mouse: *const Mouse) ?Position {
        assert(mouse.is_valid());

        return mouse.payload.position();
    }

    pub fn button(mouse: *const Mouse) ?Button {
        assert(mouse.is_valid());

        return switch (mouse.payload) {
            .button => |event| event.button,
            else => null,
        };
    }
};

const testing = std.testing;

test "the mouse kinds are stable" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(Kind.left_down));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(Kind.left_up));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(Kind.right_down));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(Kind.right_up));
    try testing.expectEqual(@as(u8, 4), @intFromEnum(Kind.middle_down));
    try testing.expectEqual(@as(u8, 5), @intFromEnum(Kind.middle_up));
    try testing.expectEqual(@as(u8, 6), @intFromEnum(Kind.x_down));
    try testing.expectEqual(@as(u8, 7), @intFromEnum(Kind.x_up));
    try testing.expectEqual(@as(u8, 8), @intFromEnum(Kind.wheel));
    try testing.expectEqual(@as(u8, 9), @intFromEnum(Kind.move));
    try testing.expectEqual(@as(u8, 10), @intFromEnum(Kind.other));
    try testing.expectEqual(@as(usize, kind_count), @typeInfo(Kind).@"enum".fields.len);
}

test "every kind is valid and carries exactly one payload shape" {
    inline for (@typeInfo(Kind).@"enum".fields) |field| {
        const kind: Kind = @enumFromInt(field.value);

        try testing.expect(kind.is_valid());
        try testing.expect(kind.is_button() == (kind.carries() == .button));
    }
}

test "press and release partition the button kinds" {
    try testing.expect(Kind.left_down.is_down());
    try testing.expect(Kind.right_down.is_down());
    try testing.expect(Kind.middle_down.is_down());
    try testing.expect(Kind.x_down.is_down());
    try testing.expect(Kind.left_up.is_up());
    try testing.expect(Kind.right_up.is_up());
    try testing.expect(Kind.middle_up.is_up());
    try testing.expect(Kind.x_up.is_up());
    try testing.expect(!Kind.wheel.is_down());
    try testing.expect(!Kind.wheel.is_up());
    try testing.expect(!Kind.move.is_down());
    try testing.expect(!Kind.move.is_up());
}

test "both side buttons fold onto one kind" {
    try testing.expectEqual(Kind.left_down, Kind.from_button(.left, true));
    try testing.expectEqual(Kind.left_up, Kind.from_button(.left, false));
    try testing.expectEqual(Kind.right_down, Kind.from_button(.right, true));
    try testing.expectEqual(Kind.middle_up, Kind.from_button(.middle, false));
    try testing.expectEqual(Kind.x_down, Kind.from_button(.x1, true));
    try testing.expectEqual(Kind.x_down, Kind.from_button(.x2, true));
    try testing.expectEqual(Kind.x_up, Kind.from_button(.x2, false));
}

test "a button event carries its button, kind, and stamp" {
    const event = Mouse.from_button(
        .{ .button = .right, .down = true, .position = Position.init(10, 20) },
        .{ .injected = true, .time_ms = 99 },
    );

    try testing.expect(event.is_valid());
    try testing.expect(event.is_button());
    try testing.expect(event.is_down());
    try testing.expect(!event.is_up());
    try testing.expectEqual(Kind.right_down, event.kind);
    try testing.expectEqual(Button.right, event.button().?);
    try testing.expect(event.injected);
    try testing.expectEqual(@as(i64, 99), event.time_ms);
    try testing.expect(event.position().?.eql(Position.init(10, 20)));
}

test "a motion event carries signed deltas and an optional position" {
    const event = Mouse.from_motion(.{ .delta_x = -3, .delta_y = 7 }, .{});

    try testing.expect(event.is_valid());
    try testing.expect(!event.is_button());
    try testing.expectEqual(Kind.move, event.kind);
    try testing.expectEqual(@as(i32, -3), event.payload.motion.delta_x);
    try testing.expectEqual(@as(i32, 7), event.payload.motion.delta_y);
    try testing.expect(event.position() == null);
    try testing.expect(event.button() == null);
}

test "a wheel event carries signed steps on both axes" {
    const event = Mouse.from_wheel(.{ .steps_vertical = 2, .steps_horizontal = -1 }, .{});

    try testing.expect(event.is_valid());
    try testing.expectEqual(Kind.wheel, event.kind);
    try testing.expectEqual(@as(i32, 2), event.payload.wheel.steps_vertical);
    try testing.expectEqual(@as(i32, -1), event.payload.wheel.steps_horizontal);
}

test "an unclassified event carries no payload" {
    const event = Mouse{ .kind = .other };

    try testing.expect(event.is_valid());
    try testing.expect(!event.is_button());
    try testing.expect(event.position() == null);
    try testing.expect(event.button() == null);
}

test "is_valid rejects a payload that contradicts its kind" {
    const mismatched = Mouse{ .kind = .move, .payload = .{ .wheel = .{} } };

    const mislabelled = Mouse{
        .kind = .left_down,
        .payload = .{ .button = .{ .button = .right, .down = true } },
    };

    const stale = Mouse{ .kind = .move, .payload = .{ .motion = .{} }, .time_ms = -1 };

    try testing.expect(!mismatched.is_valid());
    try testing.expect(!mislabelled.is_valid());
    try testing.expect(!stale.is_valid());
}

test "a position compares by value" {
    try testing.expect(Position.init(1, 2).eql(Position.init(1, 2)));
    try testing.expect(!Position.init(1, 2).eql(Position.init(2, 1)));
}

test "the button values cover every physical button" {
    try testing.expectEqual(@as(usize, button_count), @typeInfo(Button).@"enum".fields.len);

    inline for (@typeInfo(Button).@"enum".fields) |field| {
        const button: Button = @enumFromInt(field.value);

        try testing.expect(button.is_valid());
    }
}
