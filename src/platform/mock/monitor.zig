const std = @import("std");

const monitor_module = @import("../../monitor.zig");
const position_module = @import("../../position.zig");

const assert = std.debug.assert;

const Monitor = monitor_module.Monitor;
const Position = position_module.Position;

const width_default: i32 = 1920;
const height_default: i32 = 1080;

var cursor: Position = .zero;

comptime {
    assert(width_default > 0);
    assert(height_default > 0);
}

pub fn enumerate(list: *Monitor.List) void {
    assert(list.count == 0);

    list.push(build(0, true));
    list.push(build(width_default, false));

    assert(list.count == 2);
}

fn build(offset_x: i32, primary: bool) Monitor {
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

pub fn get_cursor_position() Position {
    return cursor;
}

pub fn set_cursor_position(position: Position) void {
    cursor = position;

    assert(cursor.eql(position));
}

pub fn reset() void {
    cursor = .zero;

    assert(cursor.eql(.zero));
}
