const std = @import("std");

const platform = @import("platform.zig");
const position_module = @import("position.zig");

const assert = std.debug.assert;

const Position = position_module.Position;

pub const monitor_count_max: u8 = 16;

pub const Monitor = struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
    work_left: i32,
    work_top: i32,
    work_right: i32,
    work_bottom: i32,
    primary: bool,

    pub const List = struct {
        monitors: [monitor_count_max]Monitor,
        count: u8,

        pub fn enumerate(list: *List) void {
            list.count = 0;

            platform.backend.monitor.enumerate(list);

            assert(list.count <= monitor_count_max);
        }

        pub fn get(list: *const List, index: u8) ?Monitor {
            assert(list.count <= monitor_count_max);

            if (index >= list.count) {
                return null;
            }

            return list.monitors[index];
        }

        pub fn primary(list: *const List) ?Monitor {
            assert(list.count <= monitor_count_max);

            for (list.monitors[0..list.count]) |monitor| {
                if (monitor.primary) {
                    return monitor;
                }
            }

            return list.get(0);
        }

        pub fn at(list: *const List, position: Position) ?Monitor {
            assert(list.count <= monitor_count_max);

            for (list.monitors[0..list.count]) |monitor| {
                if (monitor.contains(position)) {
                    return monitor;
                }
            }

            return null;
        }

        pub fn push(list: *List, monitor: Monitor) void {
            assert(monitor.right >= monitor.left);
            assert(monitor.bottom >= monitor.top);

            if (list.count >= monitor_count_max) {
                return;
            }

            list.monitors[list.count] = monitor;
            list.count += 1;

            assert(list.count <= monitor_count_max);
        }
    };

    pub fn width(monitor: *const Monitor) i32 {
        assert(monitor.right >= monitor.left);

        return monitor.right - monitor.left;
    }

    pub fn height(monitor: *const Monitor) i32 {
        assert(monitor.bottom >= monitor.top);

        return monitor.bottom - monitor.top;
    }

    pub fn center(monitor: *const Monitor) Position {
        const result: Position = .{
            .x = monitor.left + @divFloor(monitor.width(), 2),
            .y = monitor.top + @divFloor(monitor.height(), 2),
        };

        assert(result.x >= monitor.left);
        assert(result.y >= monitor.top);

        return result;
    }

    pub fn contains(monitor: *const Monitor, position: Position) bool {
        const inside_x = position.x >= monitor.left and position.x < monitor.right;
        const inside_y = position.y >= monitor.top and position.y < monitor.bottom;

        return inside_x and inside_y;
    }
};

const testing = std.testing;

fn monitor_at(left: i32, primary: bool) Monitor {
    return .{
        .left = left,
        .top = 0,
        .right = left + 1920,
        .bottom = 1080,
        .work_left = left,
        .work_top = 0,
        .work_right = left + 1920,
        .work_bottom = 1040,
        .primary = primary,
    };
}

test Monitor {
    const monitor = monitor_at(1920, false);

    try testing.expectEqual(@as(i32, 1920), monitor.width());
    try testing.expectEqual(@as(i32, 1080), monitor.height());
    try testing.expect(monitor.center().eql(.{ .x = 2880, .y = 540 }));
    try testing.expect(monitor.contains(.{ .x = 1920, .y = 0 }));
    try testing.expect(!monitor.contains(.{ .x = 3840, .y = 0 }));
}

test "a list finds the primary monitor and the monitor under a point" {
    var list: Monitor.List = undefined;

    list.count = 0;

    list.push(monitor_at(0, false));
    list.push(monitor_at(1920, true));

    try testing.expectEqual(@as(u8, 2), list.count);
    try testing.expectEqual(@as(i32, 1920), list.primary().?.left);
    try testing.expectEqual(@as(i32, 0), list.at(.{ .x = 10, .y = 10 }).?.left);
    try testing.expect(list.at(.{ .x = 5000, .y = 10 }) == null);
    try testing.expect(list.get(2) == null);
}

test "a list without a primary falls back to the first monitor" {
    var list: Monitor.List = undefined;

    list.count = 0;

    list.push(monitor_at(0, false));

    try testing.expectEqual(@as(i32, 0), list.primary().?.left);
}

test "a full list drops the monitors past its bound" {
    var list: Monitor.List = undefined;

    list.count = 0;

    for (0..monitor_count_max + 2) |index| {
        list.push(monitor_at(@intCast(index * 1920), false));
    }

    try testing.expectEqual(monitor_count_max, list.count);
}
