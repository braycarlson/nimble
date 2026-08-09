const std = @import("std");

const win32 = @import("win32.zig");

const assert = std.debug.assert;

pub const max: u8 = 16;

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
    handle: win32.HMONITOR,

    pub fn width(monitor: *const Monitor) i32 {
        assert(monitor.right >= monitor.left);

        return monitor.right - monitor.left;
    }

    pub fn height(monitor: *const Monitor) i32 {
        assert(monitor.bottom >= monitor.top);

        return monitor.bottom - monitor.top;
    }

    pub fn work_width(monitor: *const Monitor) i32 {
        assert(monitor.work_right >= monitor.work_left);

        return monitor.work_right - monitor.work_left;
    }

    pub fn work_height(monitor: *const Monitor) i32 {
        assert(monitor.work_bottom >= monitor.work_top);

        return monitor.work_bottom - monitor.work_top;
    }

    pub fn center(monitor: *const Monitor) Position {
        return Position{
            .x = monitor.left + @divTrunc(monitor.width(), 2),
            .y = monitor.top + @divTrunc(monitor.height(), 2),
        };
    }

    pub fn work_center(monitor: *const Monitor) Position {
        return Position{
            .x = monitor.work_left + @divTrunc(monitor.work_width(), 2),
            .y = monitor.work_top + @divTrunc(monitor.work_height(), 2),
        };
    }

    pub fn origin(monitor: *const Monitor) Position {
        return Position{
            .x = monitor.left,
            .y = monitor.top,
        };
    }

    pub fn work_origin(monitor: *const Monitor) Position {
        return Position{
            .x = monitor.work_left,
            .y = monitor.work_top,
        };
    }

    pub fn contains(monitor: *const Monitor, x: i32, y: i32) bool {
        const in_x = x >= monitor.left and x < monitor.right;
        const in_y = y >= monitor.top and y < monitor.bottom;

        return in_x and in_y;
    }

    pub fn contains_position(monitor: *const Monitor, pos: Position) bool {
        return monitor.contains(pos.x, pos.y);
    }

    pub fn clamp(monitor: *const Monitor, x: i32, y: i32) Position {
        return Position{
            .x = @max(monitor.left, @min(x, monitor.right - 1)),
            .y = @max(monitor.top, @min(y, monitor.bottom - 1)),
        };
    }

    pub fn clamp_position(monitor: *const Monitor, pos: Position) Position {
        return monitor.clamp(pos.x, pos.y);
    }

    pub fn to_absolute(monitor: *const Monitor, x: i32, y: i32) Position {
        return Position{
            .x = monitor.left + x,
            .y = monitor.top + y,
        };
    }

    pub fn to_relative(monitor: *const Monitor, x: i32, y: i32) Position {
        return Position{
            .x = x - monitor.left,
            .y = y - monitor.top,
        };
    }
};

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
        return Position{
            .x = position.x + dx,
            .y = position.y + dy,
        };
    }

    pub fn sub(position: Position, other: Position) Position {
        return Position{
            .x = position.x - other.x,
            .y = position.y - other.y,
        };
    }

    pub fn distance(position: Position, other: Position) f64 {
        const dx: f64 = @floatFromInt(position.x - other.x);
        const dy: f64 = @floatFromInt(position.y - other.y);

        return @sqrt(dx * dx + dy * dy);
    }

    pub fn distance_squared(position: Position, other: Position) i64 {
        const dx: i64 = position.x - other.x;
        const dy: i64 = position.y - other.y;

        return dx * dx + dy * dy;
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
        const result = Screen{
            .width = win32.GetSystemMetrics(win32.SM_CXSCREEN),
            .height = win32.GetSystemMetrics(win32.SM_CYSCREEN),
            .virtual_width = win32.GetSystemMetrics(win32.SM_CXVIRTUALSCREEN),
            .virtual_height = win32.GetSystemMetrics(win32.SM_CYVIRTUALSCREEN),
            .virtual_left = win32.GetSystemMetrics(win32.SM_XVIRTUALSCREEN),
            .virtual_top = win32.GetSystemMetrics(win32.SM_YVIRTUALSCREEN),
        };

        assert(result.width >= 0);
        assert(result.height >= 0);

        return result;
    }

    pub fn center(screen: Screen) Position {
        assert(screen.width >= 0);
        assert(screen.height >= 0);

        return Position{
            .x = @divTrunc(screen.width, 2),
            .y = @divTrunc(screen.height, 2),
        };
    }

    pub fn contains(screen: Screen, x: i32, y: i32) bool {
        const in_x = x >= screen.virtual_left and x < screen.virtual_left + screen.virtual_width;
        const in_y = y >= screen.virtual_top and y < screen.virtual_top + screen.virtual_height;

        return in_x and in_y;
    }

    pub fn clamp(screen: Screen, x: i32, y: i32) Position {
        const right = screen.virtual_left + screen.virtual_width - 1;
        const bottom = screen.virtual_top + screen.virtual_height - 1;

        const clamped_x = @max(screen.virtual_left, @min(x, right));
        const clamped_y = @max(screen.virtual_top, @min(y, bottom));

        return Position{
            .x = clamped_x,
            .y = clamped_y,
        };
    }
};

pub const List = struct {
    monitors: [max]Monitor = undefined,
    count: u8 = 0,

    pub fn enumerate() List {
        var result = List{};

        _ = win32.EnumDisplayMonitors(null, null, enum_callback, @bitCast(@intFromPtr(&result)));

        assert(result.count <= max);

        return result;
    }

    fn enum_callback(
        hmonitor: ?win32.HMONITOR,
        _: ?win32.HDC,
        _: ?*win32.RECT,
        lparam: win32.LPARAM,
    ) callconv(.c) win32.BOOL {
        const list: *List = @ptrFromInt(@as(usize, @bitCast(lparam)));

        if (list.count >= max) {
            return 0;
        }

        const monitor = hmonitor orelse return 1;

        var info: win32.MONITORINFO = std.mem.zeroes(win32.MONITORINFO);
        info.cbSize = @sizeOf(win32.MONITORINFO);

        if (win32.GetMonitorInfoW(monitor, &info) == 0) {
            return 1;
        }

        const slot = list.count;

        list.monitors[slot] = Monitor{
            .left = info.rcMonitor.left,
            .top = info.rcMonitor.top,
            .right = info.rcMonitor.right,
            .bottom = info.rcMonitor.bottom,
            .work_left = info.rcWork.left,
            .work_top = info.rcWork.top,
            .work_right = info.rcWork.right,
            .work_bottom = info.rcWork.bottom,
            .primary = (info.dwFlags & win32.MONITORINFOF_PRIMARY) != 0,
            .handle = monitor,
        };

        list.count += 1;

        return 1;
    }

    pub fn get(list: *const List, index: u8) ?Monitor {
        assert(list.count <= max);

        if (index >= list.count) {
            return null;
        }

        assert(index < max);

        return list.monitors[index];
    }

    pub fn get_primary(list: *const List) ?Monitor {
        var i: u8 = 0;

        while (i < list.count) : (i += 1) {
            if (list.monitors[i].primary) {
                return list.monitors[i];
            }
        }

        return null;
    }

    pub fn get_at_position(list: *const List, x: i32, y: i32) ?Monitor {
        assert(list.count <= max);

        var i: u8 = 0;

        while (i < list.count) : (i += 1) {
            if (list.monitors[i].contains(x, y)) {
                return list.monitors[i];
            }
        }

        return null;
    }

    pub fn get_at_cursor(list: *const List) ?Monitor {
        const pos = get_cursor_position();

        return list.get_at_position(pos.x, pos.y);
    }

    pub fn is_empty(list: *const List) bool {
        return list.count == 0;
    }
};

pub fn get_cursor_position() Position {
    var point: win32.POINT = std.mem.zeroes(win32.POINT);

    if (win32.GetCursorPos(&point) == 0) {
        return Position.zero();
    }

    return Position{
        .x = point.x,
        .y = point.y,
    };
}

pub fn get_all() List {
    return List.enumerate();
}

pub fn get(index: u8) ?Monitor {
    const list = List.enumerate();

    return list.get(index);
}

pub fn get_primary() ?Monitor {
    const list = List.enumerate();

    return list.get_primary();
}

pub fn get_current() ?Monitor {
    const list = List.enumerate();

    return list.get_at_cursor();
}

pub fn get_at(x: i32, y: i32) ?Monitor {
    const list = List.enumerate();

    return list.get_at_position(x, y);
}

pub fn get_count() u8 {
    const list = List.enumerate();

    return list.count;
}

pub fn enumerate() List {
    return get_all();
}
