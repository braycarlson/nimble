const std = @import("std");

const w32 = @import("win32").everything;

pub const buffer_max: u16 = 256;

pub const GUITHREADINFO = extern struct {
    cbSize: u32,
    flags: u32,
    hwndActive: ?w32.HWND,
    hwndFocus: ?w32.HWND,
    hwndCapture: ?w32.HWND,
    hwndMenuOwner: ?w32.HWND,
    hwndMoveSize: ?w32.HWND,
    hwndCaret: ?w32.HWND,
    rcCaret: w32.RECT,
};

pub extern "user32" fn GetGUIThreadInfo(idThread: u32, pgui: *GUITHREADINFO) callconv(.c) w32.BOOL;

pub fn get_foreground() ?w32.HWND {
    return w32.GetForegroundWindow();
}

pub fn get_focused() ?w32.HWND {
    const foreground = w32.GetForegroundWindow() orelse return null;

    var process_id: u32 = 0;
    const thread_id = w32.GetWindowThreadProcessId(foreground, &process_id);

    if (thread_id == 0) {
        return foreground;
    }

    var gui_info: GUITHREADINFO = std.mem.zeroes(GUITHREADINFO);
    gui_info.cbSize = @sizeOf(GUITHREADINFO);

    if (GetGUIThreadInfo(thread_id, &gui_info) != 0) {
        if (gui_info.hwndFocus) |focus| {
            return focus;
        }
    }

    return foreground;
}

pub fn get_thread_id(hwnd: w32.HWND) u32 {
    var process_id: u32 = 0;
    return w32.GetWindowThreadProcessId(hwnd, &process_id);
}

pub fn get_process_id(hwnd: w32.HWND) u32 {
    var process_id: u32 = 0;
    _ = w32.GetWindowThreadProcessId(hwnd, &process_id);
    return process_id;
}

pub fn is_fullscreen(hwnd: w32.HWND) bool {
    var rect: w32.RECT = std.mem.zeroes(w32.RECT);

    if (w32.GetWindowRect(hwnd, &rect) == 0) {
        return false;
    }

    const monitor = w32.MonitorFromWindow(hwnd, w32.MONITOR_DEFAULTTONEAREST) orelse return false;

    var info: w32.MONITORINFO = std.mem.zeroes(w32.MONITORINFO);
    info.cbSize = @sizeOf(w32.MONITORINFO);

    if (w32.GetMonitorInfoW(monitor, &info) == 0) {
        return false;
    }

    const mon = info.rcMonitor;

    const match_left = rect.left == mon.left;
    const match_top = rect.top == mon.top;
    const match_right = rect.right == mon.right;
    const match_bottom = rect.bottom == mon.bottom;

    return match_left and match_top and match_right and match_bottom;
}

pub fn is_maximized(hwnd: w32.HWND) bool {
    var placement: w32.WINDOWPLACEMENT = std.mem.zeroes(w32.WINDOWPLACEMENT);
    placement.length = @sizeOf(w32.WINDOWPLACEMENT);

    if (w32.GetWindowPlacement(hwnd, &placement) == 0) {
        return false;
    }

    return placement.showCmd == w32.SW_SHOWMAXIMIZED;
}

pub fn is_minimized(hwnd: w32.HWND) bool {
    var placement: w32.WINDOWPLACEMENT = std.mem.zeroes(w32.WINDOWPLACEMENT);
    placement.length = @sizeOf(w32.WINDOWPLACEMENT);

    if (w32.GetWindowPlacement(hwnd, &placement) == 0) {
        return false;
    }

    return placement.showCmd == w32.SW_SHOWMINIMIZED;
}

pub fn is_visible(hwnd: w32.HWND) bool {
    return w32.IsWindowVisible(hwnd) != 0;
}

pub fn is_enabled(hwnd: w32.HWND) bool {
    return w32.IsWindowEnabled(hwnd) != 0;
}

pub fn get_class(hwnd: w32.HWND, buffer: []u8) ?[]const u8 {
    std.debug.assert(buffer.len > 0);
    std.debug.assert(buffer.len <= buffer_max);

    const len = w32.GetClassNameA(hwnd, @ptrCast(buffer.ptr), @intCast(buffer.len));

    if (len == 0) {
        return null;
    }

    return buffer[0..@intCast(len)];
}

pub fn get_title(hwnd: w32.HWND, buffer: []u8) ?[]const u8 {
    std.debug.assert(buffer.len > 0);
    std.debug.assert(buffer.len <= buffer_max);

    const len = w32.GetWindowTextA(hwnd, @ptrCast(buffer.ptr), @intCast(buffer.len));

    if (len == 0) {
        return null;
    }

    return buffer[0..@intCast(len)];
}

pub fn get_rect(hwnd: w32.HWND) ?w32.RECT {
    var rect: w32.RECT = std.mem.zeroes(w32.RECT);

    if (w32.GetWindowRect(hwnd, &rect) == 0) {
        return null;
    }

    return rect;
}

pub fn get_client_rect(hwnd: w32.HWND) ?w32.RECT {
    var rect: w32.RECT = std.mem.zeroes(w32.RECT);

    if (w32.GetClientRect(hwnd, &rect) == 0) {
        return null;
    }

    return rect;
}

pub fn class_matches(hwnd: w32.HWND, target: []const u8) bool {
    var buffer: [buffer_max]u8 = undefined;

    const class = get_class(hwnd, &buffer) orelse return false;

    return std.mem.indexOf(u8, class, target) != null;
}

pub fn title_matches(hwnd: w32.HWND, target: []const u8) bool {
    var buffer: [buffer_max]u8 = undefined;

    const title = get_title(hwnd, &buffer) orelse return false;

    return std.mem.indexOf(u8, title, target) != null;
}
