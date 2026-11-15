const std = @import("std");

const client = @import("wayland.zig").client;
const monitor_module = @import("../../monitor.zig");
const output = @import("wayland.zig").output;
const position_module = @import("../../position.zig");

const assert = std.debug.assert;

const MonitorList = monitor_module.Monitor.List;
const Position = position_module.Position;

cursor: Position = .zero,
runtime_path: [socket_bytes_max]u8 = @splat(0),
runtime_len: u16 = 0,
cache: MonitorList = .{ .monitors = undefined, .count = 0 },
cached: bool = false,

const Monitor = @This();

pub const socket_bytes_max: u16 = 108;

comptime {
    assert(monitor_module.count_max > 0);
    assert(output.count_max <= monitor_module.count_max);
}

pub fn configure(monitor: *Monitor, socket_path: []const u8) bool {
    if (socket_path.len == 0) return false;
    if (socket_path.len >= monitor.runtime_path.len) return false;

    @memcpy(monitor.runtime_path[0..socket_path.len], socket_path);

    monitor.runtime_len = @intCast(socket_path.len);

    monitor.invalidate();

    assert(monitor.runtime_len > 0);

    return true;
}

pub fn is_configured(monitor: *const Monitor) bool {
    return monitor.runtime_len > 0;
}

pub fn invalidate(monitor: *Monitor) void {
    monitor.cached = false;
    monitor.cache.count = 0;

    assert(monitor.cache.count == 0);
}

pub fn unconfigure(monitor: *Monitor) void {
    monitor.runtime_len = 0;

    monitor.invalidate();

    assert(!monitor.is_configured());
}

fn refresh(monitor: *Monitor) void {
    if (monitor.cached) return;
    if (monitor.runtime_len == 0) return;

    monitor.cached = true;

    var connection = client.connect(monitor.runtime_path[0..monitor.runtime_len]) catch return;
    defer connection.close();

    connection.get_registry() catch return;
    connection.roundtrip() catch return;

    var list = output.List{};

    output.enumerate(&connection, &list) catch return;

    var index: u8 = 0;

    while (index < list.count) : (index += 1) {
        const item = list.outputs[index];

        monitor.cache.push(.{
            .left = item.x,
            .top = item.y,
            .right = item.x + item.width,
            .bottom = item.y + item.height,
            .work_left = item.x,
            .work_top = item.y,
            .work_right = item.x + item.width,
            .work_bottom = item.y + item.height,
            .primary = item.primary,
        });
    }

    assert(monitor.cache.count <= monitor_module.count_max);
}

pub fn enumerate(monitor: *Monitor, list: *MonitorList) void {
    assert(list.count == 0);

    monitor.refresh();

    for (monitor.cache.monitors[0..monitor.cache.count]) |item| {
        list.push(item);
    }

    assert(list.count == monitor.cache.count);
}

pub fn get_cursor_position(monitor: *const Monitor) Position {
    return monitor.cursor;
}

pub fn set_cursor_position(monitor: *Monitor, position: Position) void {
    monitor.cursor = position;

    assert(monitor.cursor.eql(position));
}

const testing = std.testing;

fn monitor_at(left: i32, primary: bool) monitor_module.Monitor {
    return .{
        .left = left,
        .top = 0,
        .right = left + 1920,
        .bottom = 1080,
        .work_left = left,
        .work_top = 0,
        .work_right = left + 1920,
        .work_bottom = 1080,
        .primary = primary,
    };
}

test "monitor queries report absence until a socket is configured" {
    var monitor: Monitor = .{};

    monitor.unconfigure();

    var list: MonitorList = .{ .monitors = undefined, .count = 0 };

    monitor.enumerate(&list);

    try testing.expectEqual(@as(u8, 0), list.count);
    try testing.expect(list.primary() == null);
}

test "configure refuses an empty or oversized socket path" {
    var monitor: Monitor = .{};

    const long: [120]u8 = @splat('s');

    try testing.expect(!monitor.configure(""));
    try testing.expect(!monitor.configure(&long));
    try testing.expect(monitor.configure("/run/user/1000/wayland-0"));
    try testing.expect(monitor.is_configured());

    monitor.unconfigure();
}

test "an enumeration copies the cached outputs into the caller's list" {
    var monitor: Monitor = .{};

    monitor.unconfigure();

    monitor.cached = true;

    monitor.cache.push(monitor_at(0, true));
    monitor.cache.push(monitor_at(1920, false));

    var list: MonitorList = .{ .monitors = undefined, .count = 0 };

    monitor.enumerate(&list);

    try testing.expectEqual(@as(u8, 2), list.count);
    try testing.expectEqual(@as(i32, 0), list.primary().?.left);
    try testing.expectEqual(@as(i32, 1920), list.at(.{ .x = 2000, .y = 10 }).?.left);
    try testing.expect(list.at(.{ .x = 5000, .y = 10 }) == null);

    monitor.unconfigure();
}

test "the cursor position follows the last synthesized move" {
    var monitor: Monitor = .{};

    monitor.set_cursor_position(.{ .x = 40, .y = 60 });

    try testing.expect(monitor.get_cursor_position().eql(.{ .x = 40, .y = 60 }));

    monitor.set_cursor_position(.zero);
}
