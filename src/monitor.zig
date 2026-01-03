const std = @import("std");

const w32 = @import("win32").everything;

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
    handle: w32.HMONITOR,

    pub fn width(self: *const Monitor) i32 {
        std.debug.assert(self.right >= self.left);

        return self.right - self.left;
    }

    pub fn height(self: *const Monitor) i32 {
        std.debug.assert(self.bottom >= self.top);

        return self.bottom - self.top;
    }

    pub fn work_width(self: *const Monitor) i32 {
        std.debug.assert(self.work_right >= self.work_left);

        return self.work_right - self.work_left;
    }

    pub fn work_height(self: *const Monitor) i32 {
        std.debug.assert(self.work_bottom >= self.work_top);

        return self.work_bottom - self.work_top;
    }

    pub fn center(self: *const Monitor) Position {
        return Position{
            .x = self.left + @divTrunc(self.width(), 2),
            .y = self.top + @divTrunc(self.height(), 2),
        };
    }

    pub fn work_center(self: *const Monitor) Position {
        return Position{
            .x = self.work_left + @divTrunc(self.work_width(), 2),
            .y = self.work_top + @divTrunc(self.work_height(), 2),
        };
    }

    pub fn origin(self: *const Monitor) Position {
        return Position{
            .x = self.left,
            .y = self.top,
        };
    }

    pub fn work_origin(self: *const Monitor) Position {
        return Position{
            .x = self.work_left,
            .y = self.work_top,
        };
    }

    pub fn contains(self: *const Monitor, x: i32, y: i32) bool {
        const in_x = x >= self.left and x < self.right;
        const in_y = y >= self.top and y < self.bottom;

        return in_x and in_y;
    }

    pub fn contains_position(self: *const Monitor, pos: Position) bool {
        return self.contains(pos.x, pos.y);
    }

    pub fn clamp(self: *const Monitor, x: i32, y: i32) Position {
        return Position{
            .x = @max(self.left, @min(x, self.right - 1)),
            .y = @max(self.top, @min(y, self.bottom - 1)),
        };
    }

    pub fn clamp_position(self: *const Monitor, pos: Position) Position {
        return self.clamp(pos.x, pos.y);
    }

    pub fn to_absolute(self: *const Monitor, x: i32, y: i32) Position {
        return Position{
            .x = self.left + x,
            .y = self.top + y,
        };
    }

    pub fn to_relative(self: *const Monitor, x: i32, y: i32) Position {
        return Position{
            .x = x - self.left,
            .y = y - self.top,
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

    pub fn eql(self: Position, other: Position) bool {
        return self.x == other.x and self.y == other.y;
    }

    pub fn add(self: Position, dx: i32, dy: i32) Position {
        return Position{
            .x = self.x + dx,
            .y = self.y + dy,
        };
    }

    pub fn sub(self: Position, other: Position) Position {
        return Position{
            .x = self.x - other.x,
            .y = self.y - other.y,
        };
    }

    pub fn distance(self: Position, other: Position) f64 {
        const dx: f64 = @floatFromInt(self.x - other.x);
        const dy: f64 = @floatFromInt(self.y - other.y);

        return @sqrt(dx * dx + dy * dy);
    }

    pub fn distance_squared(self: Position, other: Position) i64 {
        const dx: i64 = self.x - other.x;
        const dy: i64 = self.y - other.y;

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
            .width = w32.GetSystemMetrics(w32.SM_CXSCREEN),
            .height = w32.GetSystemMetrics(w32.SM_CYSCREEN),
            .virtual_width = w32.GetSystemMetrics(w32.SM_CXVIRTUALSCREEN),
            .virtual_height = w32.GetSystemMetrics(w32.SM_CYVIRTUALSCREEN),
            .virtual_left = w32.GetSystemMetrics(w32.SM_XVIRTUALSCREEN),
            .virtual_top = w32.GetSystemMetrics(w32.SM_YVIRTUALSCREEN),
        };

        std.debug.assert(result.width >= 0);
        std.debug.assert(result.height >= 0);

        return result;
    }

    pub fn center(self: Screen) Position {
        std.debug.assert(self.width >= 0);
        std.debug.assert(self.height >= 0);

        return Position{
            .x = @divTrunc(self.width, 2),
            .y = @divTrunc(self.height, 2),
        };
    }

    pub fn contains(self: Screen, x: i32, y: i32) bool {
        const in_x = x >= self.virtual_left and x < self.virtual_left + self.virtual_width;
        const in_y = y >= self.virtual_top and y < self.virtual_top + self.virtual_height;

        return in_x and in_y;
    }

    pub fn clamp(self: Screen, x: i32, y: i32) Position {
        const clamped_x = @max(self.virtual_left, @min(x, self.virtual_left + self.virtual_width - 1));
        const clamped_y = @max(self.virtual_top, @min(y, self.virtual_top + self.virtual_height - 1));

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

        _ = w32.EnumDisplayMonitors(null, null, enum_callback, @bitCast(@intFromPtr(&result)));

        std.debug.assert(result.count <= max);

        return result;
    }

    fn enum_callback(
        hmonitor: ?w32.HMONITOR,
        _: ?w32.HDC,
        _: ?*w32.RECT,
        lparam: w32.LPARAM,
    ) callconv(.c) w32.BOOL {
        const list: *List = @ptrFromInt(@as(usize, @intCast(lparam)));

        if (list.count >= max) {
            return 0;
        }

        const monitor = hmonitor orelse return 1;

        var info: w32.MONITORINFO = std.mem.zeroes(w32.MONITORINFO);
        info.cbSize = @sizeOf(w32.MONITORINFO);

        if (w32.GetMonitorInfoW(monitor, &info) == 0) {
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
            .primary = (info.dwFlags & w32.MONITORINFOF_PRIMARY) != 0,
            .handle = monitor,
        };

        list.count += 1;

        return 1;
    }

    pub fn get(self: *const List, index: u8) ?*const Monitor {
        if (index >= self.count) {
            return null;
        }

        std.debug.assert(index < max);

        return &self.monitors[index];
    }

    pub fn get_primary(self: *const List) ?*const Monitor {
        var i: u8 = 0;

        while (i < self.count) : (i += 1) {
            if (self.monitors[i].primary) {
                return &self.monitors[i];
            }
        }

        return null;
    }

    pub fn get_at_position(self: *const List, x: i32, y: i32) ?*const Monitor {
        var i: u8 = 0;

        while (i < self.count) : (i += 1) {
            if (self.monitors[i].contains(x, y)) {
                return &self.monitors[i];
            }
        }

        return null;
    }

    pub fn get_at_cursor(self: *const List) ?*const Monitor {
        const pos = get_cursor_position();

        return self.get_at_position(pos.x, pos.y);
    }

    pub fn is_empty(self: *const List) bool {
        return self.count == 0;
    }
};

pub fn get_cursor_position() Position {
    var point: w32.POINT = std.mem.zeroes(w32.POINT);

    if (w32.GetCursorPos(&point) == 0) {
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
    const monitor = list.get(index) orelse return null;

    return monitor.*;
}

pub fn get_primary() ?Monitor {
    const list = List.enumerate();
    const monitor = list.get_primary() orelse return null;

    return monitor.*;
}

pub fn get_current() ?Monitor {
    const list = List.enumerate();
    const monitor = list.get_at_cursor() orelse return null;

    return monitor.*;
}

pub fn get_at(x: i32, y: i32) ?Monitor {
    const list = List.enumerate();
    const monitor = list.get_at_position(x, y) orelse return null;

    return monitor.*;
}

pub fn get_count() u8 {
    const list = List.enumerate();

    return list.count;
}
