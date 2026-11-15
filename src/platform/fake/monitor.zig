const std = @import("std");

const monitor_module = @import("../../monitor.zig");
const position_module = @import("../../position.zig");

const assert = std.debug.assert;

const MonitorList = monitor_module.Monitor.List;
const Position = position_module.Position;

cursor: Position = .zero,

const Monitor = @This();

const height_default: i32 = 1080;
const width_default: i32 = 1920;

comptime {
    assert(width_default > 0);
    assert(height_default > 0);
}

pub fn enumerate(list: *MonitorList) void {
    assert(list.count == 0);

    list.push(build(0, true));
    list.push(build(width_default, false));

    assert(list.count == 2);
}

fn build(offset_x: i32, primary: bool) monitor_module.Monitor {
    assert(offset_x >= 0);

    return .{
        .left = offset_x,
        .top = 0,
        .right = offset_x + width_default,
        .bottom = height_default,
        .work_left = offset_x,
        .work_top = 0,
        .work_right = offset_x + width_default,
        .work_bottom = height_default,
        .primary = primary,
    };
}

pub fn get_cursor_position(monitor: *const Monitor) Position {
    return monitor.cursor;
}

pub fn set_cursor_position(monitor: *Monitor, position: Position) void {
    monitor.cursor = position;

    assert(monitor.cursor.eql(position));
}

const testing = std.testing;

test "the fake desktop has a primary monitor beside a second one" {
    var list: MonitorList = .{ .monitors = undefined, .count = 0 };

    enumerate(&list);

    try testing.expectEqual(@as(u8, 2), list.count);
    try testing.expect(list.monitors[0].primary);
    try testing.expect(!list.monitors[1].primary);

    var monitor: Monitor = .{};

    monitor.set_cursor_position(.{ .x = 40, .y = 30 });

    try testing.expect(monitor.get_cursor_position().eql(.{ .x = 40, .y = 30 }));
}
