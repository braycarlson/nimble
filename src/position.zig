const std = @import("std");

pub const Position = struct {
    x: i32,
    y: i32,

    pub const zero: Position = .{ .x = 0, .y = 0 };

    pub fn eql(position: Position, other: Position) bool {
        return position.x == other.x and position.y == other.y;
    }
};

const testing = std.testing;

test Position {
    const origin: Position = .zero;
    const corner: Position = .{ .x = 1920, .y = 1080 };

    try testing.expect(origin.eql(.{ .x = 0, .y = 0 }));
    try testing.expect(corner.eql(.{ .x = 1920, .y = 1080 }));
    try testing.expect(!corner.eql(origin));
    try testing.expect(!corner.eql(.{ .x = 1080, .y = 1920 }));
}
