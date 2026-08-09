const std = @import("std");

const assert = std.debug.assert;

pub const BOOL = i32;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;

pub const HWND = *opaque {};
pub const HHOOK = *opaque {};
pub const HINSTANCE = *opaque {};
pub const HMONITOR = *opaque {};
pub const HDC = *opaque {};
pub const HANDLE = *opaque {};

pub const POINT = extern struct {
    x: i32,
    y: i32,
};

pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: u32,
    wParam: WPARAM,
    lParam: LPARAM,
    time: u32,
    pt: POINT,
};

pub const KBDLLHOOKSTRUCT_FLAGS = packed struct(u32) {
    EXTENDED: u1 = 0,
    LOWER_IL_INJECTED: u1 = 0,
    _reserved_2: u2 = 0,
    INJECTED: u1 = 0,
    ALTDOWN: u1 = 0,
    _reserved_6: u1 = 0,
    UP: u1 = 0,
    _: u24 = 0,
};

pub const KBDLLHOOKSTRUCT = extern struct {
    vkCode: u32,
    scanCode: u32,
    flags: KBDLLHOOKSTRUCT_FLAGS,
    time: u32,
    dwExtraInfo: usize,
};

pub const MSLLHOOKSTRUCT = extern struct {
    pt: POINT,
    mouseData: u32,
    flags: u32,
    time: u32,
    dwExtraInfo: usize,
};

pub const MONITORINFO = extern struct {
    cbSize: u32,
    rcMonitor: RECT,
    rcWork: RECT,
    dwFlags: u32,
};

pub const WINDOWPLACEMENT = extern struct {
    length: u32,
    flags: u32,
    showCmd: u32,
    ptMinPosition: POINT,
    ptMaxPosition: POINT,
    rcNormalPosition: RECT,
};

pub const WINDOWS_HOOK_ID = i32;
pub const WH_KEYBOARD_LL: WINDOWS_HOOK_ID = 13;
pub const WH_MOUSE_LL: WINDOWS_HOOK_ID = 14;

pub const HOOKPROC = *const fn (i32, WPARAM, LPARAM) callconv(.c) LRESULT;
pub const TIMERPROC = ?*const fn (?HWND, u32, usize, u32) callconv(.c) void;
pub const MONITORENUMPROC = *const fn (?HMONITOR, ?HDC, ?*RECT, LPARAM) callconv(.c) BOOL;

pub const CLIPBOARD_FORMAT = enum(u32) {
    UNICODETEXT = 13,
    _,
};

pub const CF_UNICODETEXT = CLIPBOARD_FORMAT.UNICODETEXT;

pub const WIN32_ERROR = enum(u32) {
    NO_ERROR = 0,
    _,
};

pub const GLOBAL_ALLOC_FLAGS = u32;
pub const GMEM_MOVEABLE: GLOBAL_ALLOC_FLAGS = 0x0002;

pub const SEND_MESSAGE_TIMEOUT_FLAGS = u32;
pub const SMTO_ABORTIFHUNG: SEND_MESSAGE_TIMEOUT_FLAGS = 0x0002;

pub const PEEK_MESSAGE_REMOVE_TYPE = u32;
pub const PM_REMOVE: PEEK_MESSAGE_REMOVE_TYPE = 0x0001;

pub const QUEUE_STATUS_FLAGS = u32;
pub const QS_ALLINPUT: QUEUE_STATUS_FLAGS = 0x04FF;

pub const MONITOR_FROM_FLAGS = u32;
pub const MONITOR_DEFAULTTONEAREST: MONITOR_FROM_FLAGS = 0x00000002;

pub const MONITORINFOF_PRIMARY: u32 = 0x00000001;

pub const SYSTEM_METRICS_INDEX = i32;
pub const SM_CXSCREEN: SYSTEM_METRICS_INDEX = 0;
pub const SM_CYSCREEN: SYSTEM_METRICS_INDEX = 1;
pub const SM_XVIRTUALSCREEN: SYSTEM_METRICS_INDEX = 76;
pub const SM_YVIRTUALSCREEN: SYSTEM_METRICS_INDEX = 77;
pub const SM_CXVIRTUALSCREEN: SYSTEM_METRICS_INDEX = 78;
pub const SM_CYVIRTUALSCREEN: SYSTEM_METRICS_INDEX = 79;

pub const SW_SHOWMINIMIZED: u32 = 2;
pub const SW_SHOWMAXIMIZED: u32 = 3;

pub const WM_KEYDOWN: u32 = 0x0100;
pub const WM_KEYUP: u32 = 0x0101;
pub const WM_CHAR: u32 = 0x0102;
pub const WM_SYSKEYDOWN: u32 = 0x0104;
pub const WM_QUIT: u32 = 0x0012;
pub const WM_MOUSEMOVE: u32 = 0x0200;
pub const WM_LBUTTONDOWN: u32 = 0x0201;
pub const WM_LBUTTONUP: u32 = 0x0202;
pub const WM_RBUTTONDOWN: u32 = 0x0204;
pub const WM_RBUTTONUP: u32 = 0x0205;
pub const WM_MBUTTONDOWN: u32 = 0x0207;
pub const WM_MBUTTONUP: u32 = 0x0208;
pub const WM_MOUSEWHEEL: u32 = 0x020A;
pub const WM_XBUTTONDOWN: u32 = 0x020B;
pub const WM_XBUTTONUP: u32 = 0x020C;
pub const WM_MOUSEHWHEEL: u32 = 0x020E;

pub const WHEEL_DELTA: i32 = 120;
pub const XBUTTON1: u16 = 0x0001;
pub const XBUTTON2: u16 = 0x0002;

pub const LLMHF_INJECTED: u32 = 0x00000001;

comptime {
    assert(@sizeOf(POINT) == 8);
    assert(@sizeOf(RECT) == 16);
    assert(@sizeOf(KBDLLHOOKSTRUCT_FLAGS) == 4);
    assert(@sizeOf(MONITORINFO) == 40);
    assert(@offsetOf(MONITORINFO, "rcWork") == 20);
    assert(@offsetOf(WINDOWPLACEMENT, "showCmd") == 8);
    assert(WH_KEYBOARD_LL == 13);
    assert(WH_MOUSE_LL == 14);
    assert(LLMHF_INJECTED == 0x00000001);
}

pub const SRWLOCK = extern struct {
    ptr: ?*anyopaque,
};

pub const srwlock_init: SRWLOCK = .{ .ptr = null };

pub extern "kernel32" fn AcquireSRWLockExclusive(lock: *SRWLOCK) callconv(.c) void;
pub extern "kernel32" fn ReleaseSRWLockExclusive(lock: *SRWLOCK) callconv(.c) void;
pub extern "kernel32" fn TryAcquireSRWLockExclusive(lock: *SRWLOCK) callconv(.c) u8;

pub extern "user32" fn SetWindowsHookExW(
    idHook: i32,
    lpfn: HOOKPROC,
    hmod: ?HINSTANCE,
    dwThreadId: u32,
) callconv(.c) ?HHOOK;

pub extern "user32" fn UnhookWindowsHookEx(hhk: HHOOK) callconv(.c) BOOL;

pub extern "user32" fn CallNextHookEx(
    hhk: ?HHOOK,
    nCode: i32,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.c) LRESULT;

pub extern "kernel32" fn GetModuleHandleW(lpModuleName: ?[*:0]const u16) callconv(.c) ?HINSTANCE;
pub extern "kernel32" fn GetTickCount64() callconv(.c) u64;
pub extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.c) void;
pub extern "kernel32" fn GetLastError() callconv(.c) WIN32_ERROR;
pub extern "kernel32" fn SetLastError(dwErrCode: WIN32_ERROR) callconv(.c) void;
pub extern "kernel32" fn GlobalAlloc(
    uFlags: GLOBAL_ALLOC_FLAGS,
    dwBytes: usize,
) callconv(.c) isize;
pub extern "kernel32" fn GlobalFree(hMem: isize) callconv(.c) isize;
pub extern "kernel32" fn GlobalLock(hMem: isize) callconv(.c) ?*anyopaque;
pub extern "kernel32" fn GlobalUnlock(hMem: isize) callconv(.c) BOOL;

pub extern "user32" fn GetAsyncKeyState(vKey: i32) callconv(.c) i16;
pub extern "user32" fn MapVirtualKeyW(uCode: u32, uMapType: u32) callconv(.c) u32;
pub extern "user32" fn SendInput(
    cInputs: u32,
    pInputs: *const anyopaque,
    cbSize: i32,
) callconv(.c) u32;

pub extern "user32" fn GetForegroundWindow() callconv(.c) ?HWND;
pub extern "user32" fn GetWindowThreadProcessId(
    hWnd: HWND,
    lpdwProcessId: ?*u32,
) callconv(.c) u32;
pub extern "user32" fn GetClassNameW(
    hWnd: HWND,
    lpClassName: [*]u16,
    nMaxCount: i32,
) callconv(.c) i32;
pub extern "user32" fn GetWindowTextW(
    hWnd: HWND,
    lpString: [*]u16,
    nMaxCount: i32,
) callconv(.c) i32;
pub extern "user32" fn GetWindowRect(hWnd: HWND, lpRect: *RECT) callconv(.c) BOOL;
pub extern "user32" fn GetClientRect(hWnd: HWND, lpRect: *RECT) callconv(.c) BOOL;
pub extern "user32" fn IsWindowVisible(hWnd: HWND) callconv(.c) BOOL;
pub extern "user32" fn IsWindowEnabled(hWnd: HWND) callconv(.c) BOOL;

pub extern "user32" fn GetWindowPlacement(
    hWnd: HWND,
    lpwndpl: *WINDOWPLACEMENT,
) callconv(.c) BOOL;

pub extern "user32" fn MonitorFromWindow(
    hwnd: HWND,
    dwFlags: MONITOR_FROM_FLAGS,
) callconv(.c) ?HMONITOR;

pub extern "user32" fn GetMonitorInfoW(hMonitor: HMONITOR, lpmi: *MONITORINFO) callconv(.c) BOOL;

pub extern "user32" fn EnumDisplayMonitors(
    hdc: ?HDC,
    lprcClip: ?*const RECT,
    lpfnEnum: MONITORENUMPROC,
    dwData: LPARAM,
) callconv(.c) BOOL;

pub extern "user32" fn GetSystemMetrics(nIndex: SYSTEM_METRICS_INDEX) callconv(.c) i32;
pub extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(.c) BOOL;

pub extern "user32" fn SetTimer(
    hWnd: ?HWND,
    nIDEvent: usize,
    uElapse: u32,
    lpTimerFunc: TIMERPROC,
) callconv(.c) usize;

pub extern "user32" fn KillTimer(hWnd: ?HWND, uIDEvent: usize) callconv(.c) BOOL;

pub extern "user32" fn GetMessageW(
    lpMsg: *MSG,
    hWnd: ?HWND,
    wMsgFilterMin: u32,
    wMsgFilterMax: u32,
) callconv(.c) BOOL;

pub extern "user32" fn PeekMessageW(
    lpMsg: *MSG,
    hWnd: ?HWND,
    wMsgFilterMin: u32,
    wMsgFilterMax: u32,
    wRemoveMsg: PEEK_MESSAGE_REMOVE_TYPE,
) callconv(.c) BOOL;

pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.c) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.c) LRESULT;
pub extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.c) void;

pub extern "user32" fn MsgWaitForMultipleObjects(
    nCount: u32,
    pHandles: ?*const anyopaque,
    fWaitAll: BOOL,
    dwMilliseconds: u32,
    dwWakeMask: QUEUE_STATUS_FLAGS,
) callconv(.c) u32;

pub extern "user32" fn PostMessageW(
    hWnd: ?HWND,
    Msg: u32,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.c) BOOL;

pub extern "user32" fn PostThreadMessageW(
    idThread: u32,
    Msg: u32,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.c) BOOL;

pub extern "user32" fn SendMessageTimeoutW(
    hWnd: HWND,
    Msg: u32,
    wParam: WPARAM,
    lParam: LPARAM,
    fuFlags: SEND_MESSAGE_TIMEOUT_FLAGS,
    uTimeout: u32,
    lpdwResult: ?*usize,
) callconv(.c) LRESULT;

pub extern "user32" fn OpenClipboard(hWndNewOwner: ?HWND) callconv(.c) BOOL;
pub extern "user32" fn CloseClipboard() callconv(.c) BOOL;
pub extern "user32" fn EmptyClipboard() callconv(.c) BOOL;
pub extern "user32" fn CountClipboardFormats() callconv(.c) i32;
pub extern "user32" fn GetClipboardData(uFormat: u32) callconv(.c) ?*anyopaque;

pub extern "user32" fn SetClipboardData(
    uFormat: u32,
    hMem: ?*anyopaque,
) callconv(.c) ?*anyopaque;

const testing = std.testing;

test "handle sized types match the Win32 ABI" {
    try testing.expectEqual(@sizeOf(usize), @sizeOf(WPARAM));
    try testing.expectEqual(@sizeOf(isize), @sizeOf(LPARAM));
    try testing.expectEqual(@sizeOf(isize), @sizeOf(LRESULT));
    try testing.expectEqual(@as(usize, 4), @sizeOf(BOOL));
}

test "hook structures match the documented layout" {
    try testing.expectEqual(@as(usize, 0), @offsetOf(KBDLLHOOKSTRUCT, "vkCode"));
    try testing.expectEqual(@as(usize, 4), @offsetOf(KBDLLHOOKSTRUCT, "scanCode"));
    try testing.expectEqual(@as(usize, 8), @offsetOf(KBDLLHOOKSTRUCT, "flags"));
    try testing.expectEqual(@as(usize, 12), @offsetOf(KBDLLHOOKSTRUCT, "time"));
    try testing.expectEqual(@as(usize, 0), @offsetOf(MSLLHOOKSTRUCT, "pt"));
    try testing.expectEqual(@as(usize, 8), @offsetOf(MSLLHOOKSTRUCT, "mouseData"));
}

test "hook flag bits sit where Windows documents them" {
    const extended = KBDLLHOOKSTRUCT_FLAGS{ .EXTENDED = 1 };
    const lower = KBDLLHOOKSTRUCT_FLAGS{ .LOWER_IL_INJECTED = 1 };
    const injected = KBDLLHOOKSTRUCT_FLAGS{ .INJECTED = 1 };
    const altdown = KBDLLHOOKSTRUCT_FLAGS{ .ALTDOWN = 1 };
    const up = KBDLLHOOKSTRUCT_FLAGS{ .UP = 1 };

    try testing.expectEqual(@as(u32, 0x01), @as(u32, @bitCast(extended)));
    try testing.expectEqual(@as(u32, 0x02), @as(u32, @bitCast(lower)));
    try testing.expectEqual(@as(u32, 0x10), @as(u32, @bitCast(injected)));
    try testing.expectEqual(@as(u32, 0x20), @as(u32, @bitCast(altdown)));
    try testing.expectEqual(@as(u32, 0x80), @as(u32, @bitCast(up)));
}

test "window message constants match the Windows headers" {
    try testing.expectEqual(@as(u32, 0x0100), WM_KEYDOWN);
    try testing.expectEqual(@as(u32, 0x0104), WM_SYSKEYDOWN);
    try testing.expectEqual(@as(u32, 0x0201), WM_LBUTTONDOWN);
    try testing.expectEqual(@as(u32, 0x020A), WM_MOUSEWHEEL);
    try testing.expectEqual(@as(u32, 13), @intFromEnum(CF_UNICODETEXT));
}
