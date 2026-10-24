const std = @import("std");

const client = @import("wayland/client.zig");
const monitor_module = @import("../../monitor.zig");
const output = @import("wayland/output.zig");
const position_module = @import("../../position.zig");

const assert = std.debug.assert;

const Monitor = monitor_module.Monitor;
const Position = position_module.Position;

pub const socket_bytes_max: u16 = 108;

var cursor: Position = .zero;
var runtime_path: [socket_bytes_max]u8 = @splat(0);
var runtime_len: u16 = 0;
var cache: Monitor.List = .{ .monitors = undefined, .count = 0 };
var cached: bool = false;

comptime {
    assert(monitor_module.monitor_count_max > 0);
    assert(output.output_count_max <= monitor_module.monitor_count_max);
}

pub fn configure(socket_path: []const u8) bool {
    if (socket_path.len == 0) return false;
    if (socket_path.len >= runtime_path.len) return false;

    @memcpy(runtime_path[0..socket_path.len], socket_path);

    runtime_len = @intCast(socket_path.len);

    invalidate();

    assert(runtime_len > 0);

    return true;
}

pub fn is_configured() bool {
    return runtime_len > 0;
}

pub fn invalidate() void {
    cached = false;
    cache.count = 0;

    assert(cache.count == 0);
}

pub fn unconfigure() void {
    runtime_len = 0;

    invalidate();

    assert(!is_configured());
}

fn refresh() void {
    if (cached) return;
    if (runtime_len == 0) return;

    cached = true;

    var connection = client.connect(runtime_path[0..runtime_len]) catch return;
    defer connection.close();

    connection.get_registry() catch return;
    connection.roundtrip() catch return;

    var list = output.List{};

    output.enumerate(&connection, &list) catch return;

    var index: u8 = 0;

    while (index < list.count) : (index += 1) {
        const item = list.outputs[index];

        cache.push(.{
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

    assert(cache.count <= monitor_module.monitor_count_max);
}

pub fn enumerate(list: *Monitor.List) void {
    assert(list.count == 0);

    refresh();

    for (cache.monitors[0..cache.count]) |monitor| {
        list.push(monitor);
    }

    assert(list.count == cache.count);
}

pub fn get_cursor_position() Position {
    return cursor;
}

pub fn set_cursor_position(position: Position) void {
    cursor = position;

    assert(cursor.eql(position));
}

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
        .work_bottom = 1080,
        .primary = primary,
    };
}

test "monitor queries report absence until a socket is configured" {
    unconfigure();

    var list: Monitor.List = undefined;

    list.enumerate();

    try testing.expectEqual(@as(u8, 0), list.count);
    try testing.expect(list.primary() == null);
}

test "configure refuses an empty or oversized socket path" {
    const long: [120]u8 = @splat('s');

    try testing.expect(!configure(""));
    try testing.expect(!configure(&long));
    try testing.expect(configure("/run/user/1000/wayland-0"));
    try testing.expect(is_configured());

    unconfigure();
}

test "an enumeration copies the cached outputs into the caller's list" {
    unconfigure();

    cached = true;

    cache.push(monitor_at(0, true));
    cache.push(monitor_at(1920, false));

    var list: Monitor.List = undefined;

    list.enumerate();

    try testing.expectEqual(@as(u8, 2), list.count);
    try testing.expectEqual(@as(i32, 0), list.primary().?.left);
    try testing.expectEqual(@as(i32, 1920), list.at(.{ .x = 2000, .y = 10 }).?.left);
    try testing.expect(list.at(.{ .x = 5000, .y = 10 }) == null);

    unconfigure();
}

test "the cursor position follows the last synthesized move" {
    set_cursor_position(.{ .x = 40, .y = 60 });

    try testing.expect(get_cursor_position().eql(.{ .x = 40, .y = 60 }));

    set_cursor_position(.zero);
}
