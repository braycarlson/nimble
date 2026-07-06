const std = @import("std");

const win32 = @import("win32").everything;

const keycode = @import("../keycode.zig");

pub const WM_CHAR: u32 = 0x0102;
pub const WM_KEYDOWN: u32 = 0x0100;
pub const WM_KEYUP: u32 = 0x0101;

pub const send_timeout_ms: u32 = 1000;

const lparam_repeat_count: u32 = 1;
const lparam_scan_keycode_mask: u32 = 0xFF;
const lparam_scan_keycode_shift: u5 = 16;
const lparam_extended_flag: u5 = 24;
const lparam_previous_state: u5 = 30;
const lparam_transition_state: u5 = 31;

pub fn make_lparam(scan_keycode: u32, extended: bool, key_up: bool) win32.LPARAM {
    std.debug.assert(scan_keycode <= lparam_scan_keycode_mask);

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
    std.debug.assert(vk >= keycode.value_min);
    std.debug.assert(vk <= keycode.value_max);

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
    std.debug.assert(vk >= keycode.value_min);
    std.debug.assert(vk <= keycode.value_max);

    return win32.GetAsyncKeyState(@intCast(vk)) < 0;
}

pub fn send_key(hwnd: win32.HWND, vk: u8, down: bool) bool {
    std.debug.assert(vk >= keycode.value_min);
    std.debug.assert(vk <= keycode.value_max);

    const scan_keycode = win32.MapVirtualKeyW(vk, 0);
    const extended = is_extended_key(vk);
    const msg: u32 = if (down) WM_KEYDOWN else WM_KEYUP;
    const lparam = make_lparam(scan_keycode, extended, !down);

    const result = win32.SendMessageTimeoutW(
        hwnd,
        msg,
        vk,
        lparam,
        win32.SMTO_ABORTIFHUNG,
        send_timeout_ms,
        null,
    );

    return result != 0;
}

pub fn send_key_down(hwnd: win32.HWND, vk: u8) bool {
    return send_key(hwnd, vk, true);
}

pub fn send_key_up(hwnd: win32.HWND, vk: u8) bool {
    return send_key(hwnd, vk, false);
}

pub fn send_key_press(hwnd: win32.HWND, vk: u8) bool {
    const down_sent = send_key(hwnd, vk, true);
    const up_sent = send_key(hwnd, vk, false);

    return down_sent and up_sent;
}

pub fn send_char(hwnd: win32.HWND, char: u16) bool {
    std.debug.assert(char != 0);

    const result = win32.SendMessageTimeoutW(
        hwnd,
        WM_CHAR,
        char,
        0,
        win32.SMTO_ABORTIFHUNG,
        send_timeout_ms,
        null,
    );

    return result != 0;
}

pub fn post_key(hwnd: win32.HWND, vk: u8, down: bool) bool {
    std.debug.assert(vk >= keycode.value_min);
    std.debug.assert(vk <= keycode.value_max);

    const scan_keycode = win32.MapVirtualKeyW(vk, 0);
    const extended = is_extended_key(vk);
    const msg: u32 = if (down) WM_KEYDOWN else WM_KEYUP;
    const lparam = make_lparam(scan_keycode, extended, !down);

    return win32.PostMessageW(hwnd, msg, vk, lparam) != 0;
}

pub fn post_key_down(hwnd: win32.HWND, vk: u8) bool {
    return post_key(hwnd, vk, true);
}

pub fn post_key_up(hwnd: win32.HWND, vk: u8) bool {
    return post_key(hwnd, vk, false);
}

pub fn post_key_press(hwnd: win32.HWND, vk: u8) bool {
    const down_sent = post_key(hwnd, vk, true);
    const up_sent = post_key(hwnd, vk, false);

    return down_sent and up_sent;
}

pub fn post_char(hwnd: win32.HWND, char: u16) bool {
    return win32.PostMessageW(hwnd, WM_CHAR, char, 0) != 0;
}

pub fn release_modifiers(hwnd: win32.HWND) bool {
    var released = true;

    if (is_key_down(keycode.lctrl)) released = send_key(hwnd, keycode.lctrl, false) and released;
    if (is_key_down(keycode.rctrl)) released = send_key(hwnd, keycode.rctrl, false) and released;
    if (is_key_down(keycode.lshift)) released = send_key(hwnd, keycode.lshift, false) and released;
    if (is_key_down(keycode.rshift)) released = send_key(hwnd, keycode.rshift, false) and released;
    if (is_key_down(keycode.lmenu)) released = send_key(hwnd, keycode.lmenu, false) and released;
    if (is_key_down(keycode.rmenu)) released = send_key(hwnd, keycode.rmenu, false) and released;
    if (is_key_down(keycode.lwin)) released = send_key(hwnd, keycode.lwin, false) and released;
    if (is_key_down(keycode.rwin)) released = send_key(hwnd, keycode.rwin, false) and released;

    return released;
}
