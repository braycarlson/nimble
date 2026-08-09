const std = @import("std");

const win32 = @import("win32.zig");

const assert = std.debug.assert;

pub const buffer_max: u16 = 256;

pub const GUITHREADINFO = extern struct {
    cbSize: u32,
    flags: u32,
    hwndActive: ?win32.HWND,
    hwndFocus: ?win32.HWND,
    hwndCapture: ?win32.HWND,
    hwndMenuOwner: ?win32.HWND,
    hwndMoveSize: ?win32.HWND,
    hwndCaret: ?win32.HWND,
    rcCaret: win32.RECT,
};

pub extern "user32" fn GetGUIThreadInfo(
    idThread: u32,
    pgui: *GUITHREADINFO,
) callconv(.c) win32.BOOL;

pub fn get_foreground() ?win32.HWND {
    return win32.GetForegroundWindow();
}

pub fn get_focused() ?win32.HWND {
    const active = win32.GetForegroundWindow() orelse return null;

    var process_id: u32 = 0;
    const thread_id = win32.GetWindowThreadProcessId(active, &process_id);

    if (thread_id == 0) {
        return active;
    }

    var gui_info: GUITHREADINFO = std.mem.zeroes(GUITHREADINFO);
    gui_info.cbSize = @sizeOf(GUITHREADINFO);

    if (GetGUIThreadInfo(thread_id, &gui_info) != 0) {
        if (gui_info.hwndFocus) |focus| {
            return focus;
        }
    }

    return active;
}

pub fn get_thread_id(hwnd: win32.HWND) u32 {
    var process_id: u32 = 0;

    return win32.GetWindowThreadProcessId(hwnd, &process_id);
}

pub fn get_process_id(hwnd: win32.HWND) u32 {
    var process_id: u32 = 0;
    _ = win32.GetWindowThreadProcessId(hwnd, &process_id);
    return process_id;
}

pub fn is_fullscreen(hwnd: win32.HWND) bool {
    var rect: win32.RECT = std.mem.zeroes(win32.RECT);

    if (win32.GetWindowRect(hwnd, &rect) == 0) {
        return false;
    }

    const monitor = win32.MonitorFromWindow(hwnd, win32.MONITOR_DEFAULTTONEAREST) orelse
        return false;

    var info: win32.MONITORINFO = std.mem.zeroes(win32.MONITORINFO);
    info.cbSize = @sizeOf(win32.MONITORINFO);

    if (win32.GetMonitorInfoW(monitor, &info) == 0) {
        return false;
    }

    const mon = info.rcMonitor;

    const match_left = rect.left == mon.left;
    const match_top = rect.top == mon.top;
    const match_right = rect.right == mon.right;
    const match_bottom = rect.bottom == mon.bottom;

    return match_left and match_top and match_right and match_bottom;
}

pub fn is_maximized(hwnd: win32.HWND) bool {
    var placement: win32.WINDOWPLACEMENT = std.mem.zeroes(win32.WINDOWPLACEMENT);
    placement.length = @sizeOf(win32.WINDOWPLACEMENT);

    if (win32.GetWindowPlacement(hwnd, &placement) == 0) {
        return false;
    }

    return placement.showCmd == win32.SW_SHOWMAXIMIZED;
}

pub fn is_minimized(hwnd: win32.HWND) bool {
    var placement: win32.WINDOWPLACEMENT = std.mem.zeroes(win32.WINDOWPLACEMENT);
    placement.length = @sizeOf(win32.WINDOWPLACEMENT);

    if (win32.GetWindowPlacement(hwnd, &placement) == 0) {
        return false;
    }

    return placement.showCmd == win32.SW_SHOWMINIMIZED;
}

pub fn is_visible(hwnd: win32.HWND) bool {
    return win32.IsWindowVisible(hwnd) != 0;
}

pub fn is_enabled(hwnd: win32.HWND) bool {
    return win32.IsWindowEnabled(hwnd) != 0;
}

fn utf16_to_utf8(source: []const u16, target: []u8) ?[]const u8 {
    assert(source.len <= buffer_max);
    assert(target.len > 0);

    var iterator = std.unicode.Utf16LeIterator.init(source);
    var written: usize = 0;

    while (iterator.nextCodepoint() catch return null) |codepoint| {
        var encoded: [4]u8 = undefined;

        const size = std.unicode.utf8Encode(codepoint, &encoded) catch return null;

        if (written + size > target.len) {
            break;
        }

        @memcpy(target[written .. written + size], encoded[0..size]);

        written += size;
    }

    assert(written <= target.len);

    return target[0..written];
}

pub fn get_class(hwnd: win32.HWND, buffer: []u8) ?[]const u8 {
    assert(buffer.len > 0);
    assert(buffer.len <= buffer_max);

    var utf16: [buffer_max:0]u16 = undefined;

    const len = win32.GetClassNameW(hwnd, &utf16, buffer_max);

    assert(len < buffer_max);

    if (len <= 0) {
        return null;
    }

    return utf16_to_utf8(utf16[0..@intCast(len)], buffer);
}

pub fn get_title(hwnd: win32.HWND, buffer: []u8) ?[]const u8 {
    assert(buffer.len > 0);
    assert(buffer.len <= buffer_max);

    var utf16: [buffer_max:0]u16 = undefined;

    win32.SetLastError(.NO_ERROR);

    const len = win32.GetWindowTextW(hwnd, &utf16, buffer_max);

    assert(len < buffer_max);

    if (len < 0) {
        return null;
    }

    if (len == 0) {
        if (win32.GetLastError() != .NO_ERROR) {
            return null;
        }

        return buffer[0..0];
    }

    return utf16_to_utf8(utf16[0..@intCast(len)], buffer);
}

pub fn get_rect(hwnd: win32.HWND) ?win32.RECT {
    var rect: win32.RECT = std.mem.zeroes(win32.RECT);

    if (win32.GetWindowRect(hwnd, &rect) == 0) {
        return null;
    }

    return rect;
}

pub fn get_client_rect(hwnd: win32.HWND) ?win32.RECT {
    var rect: win32.RECT = std.mem.zeroes(win32.RECT);

    if (win32.GetClientRect(hwnd, &rect) == 0) {
        return null;
    }

    return rect;
}

pub fn class_matches(hwnd: win32.HWND, target: []const u8) bool {
    var buffer: [buffer_max]u8 = undefined;

    const class = get_class(hwnd, &buffer) orelse return false;

    return std.mem.indexOf(u8, class, target) != null;
}

pub fn title_matches(hwnd: win32.HWND, target: []const u8) bool {
    var buffer: [buffer_max]u8 = undefined;

    const title = get_title(hwnd, &buffer) orelse return false;

    return std.mem.indexOf(u8, title, target) != null;
}

pub const Handle = win32.HWND;

pub fn foreground() ?Handle {
    return get_foreground();
}
