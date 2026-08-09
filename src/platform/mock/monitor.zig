const std = @import("std");

const assert = std.debug.assert;

pub const max: u8 = 16;
pub const width_default: i32 = 1920;
pub const height_default: i32 = 1080;

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

    pub fn center(monitor: *const Monitor) Position {
        const x = monitor.left + @divFloor(monitor.width(), 2);
        const y = monitor.top + @divFloor(monitor.height(), 2);

        return Position.init(x, y);
    }

    pub fn contains(monitor: *const Monitor, x: i32, y: i32) bool {
        const inside_x = x >= monitor.left and x < monitor.right;
        const inside_y = y >= monitor.top and y < monitor.bottom;

        return inside_x and inside_y;
    }
};

pub const Position = struct {
    x: i32,
    y: i32,

    pub fn zero() Position {
        return Position{ .x = 0, .y = 0 };
    }

    pub fn eql(position: Position, other: Position) bool {
        return position.x == other.x and position.y == other.y;
    }

    pub fn init(x: i32, y: i32) Position {
        return Position{ .x = x, .y = y };
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
        return Screen{
            .width = width_default,
            .height = height_default,
            .virtual_width = width_default * 2,
            .virtual_height = height_default,
            .virtual_left = 0,
            .virtual_top = 0,
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

        assert(index < max);

        return list.monitors[index];
    }
};

var cursor: Position = Position.init(0, 0);

comptime {
    assert(max > 0);
    assert(width_default > 0);
    assert(height_default > 0);
}

pub fn enumerate() List {
    return get_all();
}

pub fn get_all() List {
    var list = List{};

    list.monitors[0] = build(0, true);
    list.monitors[1] = build(width_default, false);
    list.count = 2;

    assert(list.count <= max);

    return list;
}

fn build(offset_x: i32, primary: bool) Monitor {
    assert(offset_x >= 0);

    return Monitor{
        .left = offset_x,
        .top = 0,
        .right = offset_x + width_default,
        .bottom = height_default,
        .work_left = offset_x,
        .work_top = 0,
        .work_right = offset_x + width_default,
        .work_bottom = height_default,
        .primary = primary,
        .handle = @intCast(offset_x + 1),
    };
}

pub fn get(index: u8) ?Monitor {
    const list = get_all();

    return list.get(index);
}

pub fn get_primary() ?Monitor {
    return get(0);
}

pub fn get_count() u8 {
    const list = get_all();

    assert(list.count <= max);

    return list.count;
}

pub fn get_at(x: i32, y: i32) ?Monitor {
    const list = get_all();
    var index: u8 = 0;

    while (index < list.count) : (index += 1) {
        const monitor = list.monitors[index];

        if (monitor.contains(x, y)) {
            return monitor;
        }
    }

    return null;
}

pub fn get_current() ?Monitor {
    return get_at(cursor.x, cursor.y) orelse get_primary();
}

pub fn get_cursor_position() Position {
    return cursor;
}

pub fn set_cursor_position(position: Position) void {
    cursor = position;

    assert(cursor.x == position.x);
    assert(cursor.y == position.y);
}

pub fn reset() void {
    cursor = Position.init(0, 0);

    assert(cursor.x == 0);
    assert(cursor.y == 0);
}
