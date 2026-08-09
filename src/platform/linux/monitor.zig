const std = @import("std");

const client = @import("wayland/client.zig");
const output = @import("wayland/output.zig");

const assert = std.debug.assert;

pub const max: u8 = 16;

pub const Position = struct {
    x: i32,
    y: i32,

    pub fn init(x: i32, y: i32) Position {
        return Position{ .x = x, .y = y };
    }

    pub fn zero() Position {
        return Position{ .x = 0, .y = 0 };
    }

    pub fn eql(position: Position, other: Position) bool {
        return position.x == other.x and position.y == other.y;
    }

    pub fn add(position: Position, dx: i32, dy: i32) Position {
        return Position{ .x = position.x + dx, .y = position.y + dy };
    }

    pub fn sub(position: Position, other: Position) Position {
        return Position{ .x = position.x - other.x, .y = position.y - other.y };
    }
};

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
    handle: u32,

    pub fn width(monitor: *const Monitor) i32 {
        assert(monitor.right >= monitor.left);

        return monitor.right - monitor.left;
    }

    pub fn height(monitor: *const Monitor) i32 {
        assert(monitor.bottom >= monitor.top);

        return monitor.bottom - monitor.top;
    }

    pub fn contains(monitor: *const Monitor, x: i32, y: i32) bool {
        const inside_x = x >= monitor.left and x < monitor.right;
        const inside_y = y >= monitor.top and y < monitor.bottom;

        return inside_x and inside_y;
    }

    pub fn center(monitor: *const Monitor) Position {
        return Position.init(
            monitor.left + @divFloor(monitor.width(), 2),
            monitor.top + @divFloor(monitor.height(), 2),
        );
    }
};

pub const Screen = struct {
    width: i32,
    height: i32,
    virtual_width: i32,
    virtual_height: i32,
    virtual_left: i32,
    virtual_top: i32,

    pub fn get() Screen {
        const list = get_all();

        var left: i32 = 0;
        var top: i32 = 0;
        var right: i32 = 0;
        var bottom: i32 = 0;
        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            const monitor = list.monitors[index];

            left = @min(left, monitor.left);
            top = @min(top, monitor.top);
            right = @max(right, monitor.right);
            bottom = @max(bottom, monitor.bottom);
        }

        const primary = get_primary();

        return Screen{
            .width = if (primary) |value| value.width() else right - left,
            .height = if (primary) |value| value.height() else bottom - top,
            .virtual_width = right - left,
            .virtual_height = bottom - top,
            .virtual_left = left,
            .virtual_top = top,
        };
    }

    pub fn center(screen: *const Screen) Position {
        return Position.init(@divFloor(screen.width, 2), @divFloor(screen.height, 2));
    }
};

pub const List = struct {
    monitors: [max]Monitor = undefined,
    count: u8 = 0,

    pub fn enumerate() List {
        return get_all();
    }

    pub fn get(list: *const List, index: u8) ?Monitor {
        if (index >= list.count) {
            return null;
        }

        return list.monitors[index];
    }

    pub fn get_primary(list: *const List) ?Monitor {
        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            if (list.monitors[index].primary) {
                return list.monitors[index];
            }
        }

        return null;
    }

    pub fn get_at_position(list: *const List, x: i32, y: i32) ?Monitor {
        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            if (list.monitors[index].contains(x, y)) {
                return list.monitors[index];
            }
        }

        return null;
    }
};

var cursor: Position = Position.init(0, 0);
var runtime_path: [108]u8 = @splat(0);
var runtime_len: u16 = 0;
var cache: List = .{};
var cached: bool = false;

comptime {
    assert(max > 0);
    assert(output.output_count_max <= max);
}

pub fn configure(socket_path: []const u8) bool {
    if (socket_path.len == 0 or socket_path.len >= runtime_path.len) {
        return false;
    }

    @memcpy(runtime_path[0..socket_path.len], socket_path);

    runtime_len = @intCast(socket_path.len);
    cached = false;
    cache = .{};

    assert(runtime_len > 0);

    return true;
}

pub fn is_configured() bool {
    return runtime_len > 0;
}

pub fn invalidate() void {
    cached = false;
    cache = .{};

    assert(cache.count == 0);
}

fn refresh() void {
    if (cached or runtime_len == 0) {
        return;
    }

    cached = true;

    var connection = client.connect(runtime_path[0..runtime_len]) catch return;
    defer connection.close();

    connection.get_registry() catch return;
    connection.roundtrip() catch return;

    var list = output.List{};

    output.enumerate(&connection, &list) catch return;

    var index: u8 = 0;

    while (index < list.count and index < max) : (index += 1) {
        const item = list.outputs[index];

        cache.monitors[index] = Monitor{
            .left = item.x,
            .top = item.y,
            .right = item.x + item.width,
            .bottom = item.y + item.height,
            .work_left = item.x,
            .work_top = item.y,
            .work_right = item.x + item.width,
            .work_bottom = item.y + item.height,
            .primary = item.primary,
            .handle = item.object,
        };
    }

    cache.count = index;

    assert(cache.count <= max);
}

pub fn enumerate() List {
    return get_all();
}

pub fn get_all() List {
    refresh();

    return cache;
}

pub fn get(index: u8) ?Monitor {
    refresh();

    return cache.get(index);
}

pub fn get_primary() ?Monitor {
    refresh();

    var index: u8 = 0;

    while (index < cache.count) : (index += 1) {
        if (cache.monitors[index].primary) {
            return cache.monitors[index];
        }
    }

    return cache.get(0);
}

pub fn get_current() ?Monitor {
    return get_at(cursor.x, cursor.y) orelse get_primary();
}

pub fn get_at(x: i32, y: i32) ?Monitor {
    refresh();

    var index: u8 = 0;

    while (index < cache.count) : (index += 1) {
        const monitor = cache.monitors[index];
        const inside_x = x >= monitor.left and x < monitor.right;
        const inside_y = y >= monitor.top and y < monitor.bottom;

        if (inside_x and inside_y) {
            return monitor;
        }
    }

    return null;
}

pub fn get_count() u8 {
    refresh();

    return cache.count;
}

pub fn get_cursor_position() Position {
    return cursor;
}

pub fn set_cursor_position(position: Position) void {
    cursor = position;
}

const testing = std.testing;

test "monitor queries report absence until a socket is configured" {
    runtime_len = 0;
    invalidate();

    try testing.expectEqual(@as(u8, 0), get_count());
    try testing.expect(get_primary() == null);
    try testing.expect(get(0) == null);
    try testing.expect(get_at(0, 0) == null);
    try testing.expectEqual(@as(u8, 0), enumerate().count);
}

test "configure refuses an empty or oversized socket path" {
    const long = "s" ** 120;

    try testing.expect(!configure(""));
    try testing.expect(!configure(long));
    try testing.expect(configure("/run/user/1000/wayland-0"));
    try testing.expect(is_configured());

    runtime_len = 0;
    invalidate();
}

test "get_at selects the monitor containing a point" {
    runtime_len = 0;
    cached = true;
    cache = .{};

    cache.monitors[0] = Monitor{
        .left = 0,
        .top = 0,
        .right = 1920,
        .bottom = 1080,
        .work_left = 0,
        .work_top = 0,
        .work_right = 1920,
        .work_bottom = 1080,
        .primary = true,
        .handle = 1,
    };

    cache.monitors[1] = Monitor{
        .left = 1920,
        .top = 0,
        .right = 3840,
        .bottom = 1080,
        .work_left = 1920,
        .work_top = 0,
        .work_right = 3840,
        .work_bottom = 1080,
        .primary = false,
        .handle = 2,
    };

    cache.count = 2;

    try testing.expectEqual(@as(u32, 1), get_at(10, 10).?.handle);
    try testing.expectEqual(@as(u32, 2), get_at(2000, 10).?.handle);
    try testing.expect(get_at(5000, 10) == null);
    try testing.expectEqual(@as(u32, 1), get_primary().?.handle);

    const screen = Screen.get();

    try testing.expectEqual(@as(i32, 3840), screen.virtual_width);
    try testing.expectEqual(@as(i32, 1920), screen.width);

    invalidate();
}

test "geometry helpers still compute over explicit values" {
    const monitor = Monitor{
        .left = 0,
        .top = 0,
        .right = 1920,
        .bottom = 1080,
        .work_left = 0,
        .work_top = 0,
        .work_right = 1920,
        .work_bottom = 1080,
        .primary = true,
        .handle = 1,
    };

    try testing.expectEqual(@as(i32, 1920), monitor.width());
    try testing.expectEqual(@as(i32, 1080), monitor.height());
    try testing.expectEqual(@as(i32, 960), monitor.center().x);
}
