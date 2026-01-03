const std = @import("std");

const w32 = @import("win32").everything;

const keycode = @import("../keycode.zig");

pub const WM_CHAR: u32 = 0x0102;
pub const WM_KEYDOWN: u32 = 0x0100;
pub const WM_KEYUP: u32 = 0x0101;

const lparam_repeat_count: u32 = 1;
const lparam_scan_keycode_mask: u32 = 0xFF;
const lparam_scan_keycode_shift: u5 = 16;
const lparam_extended_flag: u5 = 24;
const lparam_previous_state: u5 = 30;
const lparam_transition_state: u5 = 31;

pub fn make_lparam(scan_keycode: u32, extended: bool, key_up: bool) w32.LPARAM {
    var lparam: u32 = lparam_repeat_count;

    lparam |= (scan_keycode & lparam_scan_keycode_mask) << lparam_scan_keycode_shift;

    if (extended) {
        lparam |= 1 << lparam_extended_flag;
    }

    if (key_up) {
        lparam |= 1 << lparam_previous_state;
        lparam |= 1 << lparam_transition_state;
    }

    return @intCast(lparam);
}

pub fn is_extended_key(vk: u8) bool {
    return switch (vk) {
        keycode.insert, keycode.delete, keycode.home, keycode.end => true,
        keycode.prior, keycode.next => true,
        keycode.left, keycode.right, keycode.up, keycode.down => true,
        keycode.numlock, keycode.divide => true,
        keycode.rctrl, keycode.rmenu => true,
        else => false,
    };
}

pub fn is_key_down(vk: u8) bool {
    return w32.GetAsyncKeyState(@intCast(vk)) < 0;
}

pub fn send_key(hwnd: w32.HWND, vk: u8, down: bool) void {
    std.debug.assert(vk >= keycode.value_min);
    std.debug.assert(vk <= keycode.value_max);

    const scan_keycode = w32.MapVirtualKeyW(vk, 0);
    const extended = is_extended_key(vk);
    const msg: u32 = if (down) WM_KEYDOWN else WM_KEYUP;
    const lparam = make_lparam(scan_keycode, extended, !down);

    _ = w32.SendMessageW(hwnd, msg, vk, lparam);
}

pub fn send_key_down(hwnd: w32.HWND, vk: u8) void {
    send_key(hwnd, vk, true);
}

pub fn send_key_up(hwnd: w32.HWND, vk: u8) void {
    send_key(hwnd, vk, false);
}

pub fn send_key_press(hwnd: w32.HWND, vk: u8) void {
    send_key(hwnd, vk, true);
    send_key(hwnd, vk, false);
}

pub fn send_char(hwnd: w32.HWND, char: u16) void {
    _ = w32.SendMessageW(hwnd, WM_CHAR, char, 0);
}

pub fn post_key(hwnd: w32.HWND, vk: u8, down: bool) void {
    std.debug.assert(vk >= keycode.value_min);
    std.debug.assert(vk <= keycode.value_max);

    const scan_keycode = w32.MapVirtualKeyW(vk, 0);
    const extended = is_extended_key(vk);
    const msg: u32 = if (down) WM_KEYDOWN else WM_KEYUP;
    const lparam = make_lparam(scan_keycode, extended, !down);

    _ = w32.PostMessageW(hwnd, msg, vk, lparam);
}

pub fn post_key_down(hwnd: w32.HWND, vk: u8) void {
    post_key(hwnd, vk, true);
}

pub fn post_key_up(hwnd: w32.HWND, vk: u8) void {
    post_key(hwnd, vk, false);
}

pub fn post_key_press(hwnd: w32.HWND, vk: u8) void {
    post_key(hwnd, vk, true);
    post_key(hwnd, vk, false);
}

pub fn post_char(hwnd: w32.HWND, char: u8) void {
    _ = w32.PostMessageW(hwnd, WM_CHAR, char, 1);
}

pub fn release_modifiers(hwnd: w32.HWND) void {
    if (is_key_down(keycode.lctrl)) send_key(hwnd, keycode.lctrl, false);
    if (is_key_down(keycode.rctrl)) send_key(hwnd, keycode.rctrl, false);
    if (is_key_down(keycode.lshift)) send_key(hwnd, keycode.lshift, false);
    if (is_key_down(keycode.rshift)) send_key(hwnd, keycode.rshift, false);
    if (is_key_down(keycode.lmenu)) send_key(hwnd, keycode.lmenu, false);
    if (is_key_down(keycode.rmenu)) send_key(hwnd, keycode.rmenu, false);
    if (is_key_down(keycode.lwin)) send_key(hwnd, keycode.lwin, false);
    if (is_key_down(keycode.rwin)) send_key(hwnd, keycode.rwin, false);
}
