const std = @import("std");

const monitor_module = @import("../../monitor.zig");
const position_module = @import("../../position.zig");
const win32 = @import("win32.zig");

const assert = std.debug.assert;

const Monitor = monitor_module.Monitor;
const Position = position_module.Position;

pub fn enumerate(list: *Monitor.List) void {
    assert(list.count == 0);

    _ = win32.EnumDisplayMonitors(null, null, enumerate_callback, @bitCast(@intFromPtr(list)));

    assert(list.count <= monitor_module.monitor_count_max);
}

fn enumerate_callback(
    hmonitor: ?win32.HMONITOR,
    _: ?win32.HDC,
    _: ?*win32.RECT,
    lparam: win32.LPARAM,
) callconv(.c) win32.BOOL {
    const list: *Monitor.List = @ptrFromInt(@as(usize, @bitCast(lparam)));

    if (list.count >= monitor_module.monitor_count_max) {
        return 0;
    }

    const handle = hmonitor orelse return 1;

    var info: win32.MONITORINFO = std.mem.zeroes(win32.MONITORINFO);

    info.cbSize = @sizeOf(win32.MONITORINFO);

    if (win32.GetMonitorInfoW(handle, &info) == 0) {
        return 1;
    }

    list.push(.{
        .left = info.rcMonitor.left,
        .top = info.rcMonitor.top,
        .right = info.rcMonitor.right,
        .bottom = info.rcMonitor.bottom,
        .work_left = info.rcWork.left,
        .work_top = info.rcWork.top,
        .work_right = info.rcWork.right,
        .work_bottom = info.rcWork.bottom,
        .primary = (info.dwFlags & win32.MONITORINFOF_PRIMARY) != 0,
    });

    return 1;
}

pub fn get_cursor_position() Position {
    var point: win32.POINT = std.mem.zeroes(win32.POINT);

    if (win32.GetCursorPos(&point) == 0) {
        return .zero;
    }

    return .{ .x = point.x, .y = point.y };
}
