const std = @import("std");

const win32 = @import("../win32.zig");

const keycode = @import("../../../keycode.zig");
const mapping = @import("../keycode.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

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
    assert(scan_keycode <= lparam_scan_keycode_mask);

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

pub fn is_extended_key(code: Keycode) bool {
    return switch (code) {
        .insert, .delete, .home, .end => true,
        .page_up, .page_down => true,
        .arrow_left, .arrow_right, .arrow_up, .arrow_down => true,
        .num_lock, .numpad_divide => true,
        .control_right, .alt_right => true,
        else => false,
    };
}

pub fn is_key_down(code: Keycode) bool {
    const vk = mapping.to_native(code) orelse return false;

    return win32.GetAsyncKeyState(@intCast(vk)) < 0;
}

pub fn send_key(hwnd: win32.HWND, code: Keycode, down: bool) bool {
    const vk = mapping.to_native(code) orelse return false;

    const scan_keycode = win32.MapVirtualKeyW(vk, 0);
    const extended = is_extended_key(code);
    const message: u32 = if (down) WM_KEYDOWN else WM_KEYUP;
    const lparam = make_lparam(scan_keycode, extended, !down);

    const result = win32.SendMessageTimeoutW(
        hwnd,
        message,
        vk,
        lparam,
        win32.SMTO_ABORTIFHUNG,
        send_timeout_ms,
        null,
    );

    return result != 0;
}

pub fn send_key_down(hwnd: win32.HWND, code: Keycode) bool {
    return send_key(hwnd, code, true);
}

pub fn send_key_up(hwnd: win32.HWND, code: Keycode) bool {
    return send_key(hwnd, code, false);
}

pub fn send_key_press(hwnd: win32.HWND, code: Keycode) bool {
    const down_sent = send_key(hwnd, code, true);
    const up_sent = send_key(hwnd, code, false);

    return down_sent and up_sent;
}

pub fn send_char(hwnd: win32.HWND, char: u16) bool {
    assert(char != 0);

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

pub fn post_key(hwnd: win32.HWND, code: Keycode, down: bool) bool {
    const vk = mapping.to_native(code) orelse return false;

    const scan_keycode = win32.MapVirtualKeyW(vk, 0);
    const extended = is_extended_key(code);
    const message: u32 = if (down) WM_KEYDOWN else WM_KEYUP;
    const lparam = make_lparam(scan_keycode, extended, !down);

    return win32.PostMessageW(hwnd, message, vk, lparam) != 0;
}

pub fn post_key_down(hwnd: win32.HWND, code: Keycode) bool {
    return post_key(hwnd, code, true);
}

pub fn post_key_up(hwnd: win32.HWND, code: Keycode) bool {
    return post_key(hwnd, code, false);
}

pub fn post_key_press(hwnd: win32.HWND, code: Keycode) bool {
    const down_sent = post_key(hwnd, code, true);
    const up_sent = post_key(hwnd, code, false);

    return down_sent and up_sent;
}

pub fn post_char(hwnd: win32.HWND, char: u16) bool {
    return win32.PostMessageW(hwnd, WM_CHAR, char, 0) != 0;
}

pub fn release_modifiers(hwnd: win32.HWND) bool {
    var released = true;

    if (is_key_down(.control_left)) released = send_key(hwnd, .control_left, false) and released;
    if (is_key_down(.control_right)) released = send_key(hwnd, .control_right, false) and released;
    if (is_key_down(.shift_left)) released = send_key(hwnd, .shift_left, false) and released;
    if (is_key_down(.shift_right)) released = send_key(hwnd, .shift_right, false) and released;
    if (is_key_down(.alt_left)) released = send_key(hwnd, .alt_left, false) and released;
    if (is_key_down(.alt_right)) released = send_key(hwnd, .alt_right, false) and released;
    if (is_key_down(.super_left)) released = send_key(hwnd, .super_left, false) and released;
    if (is_key_down(.super_right)) released = send_key(hwnd, .super_right, false) and released;

    return released;
}

const testing = std.testing;

test "a message parameter packs a plain key" {
    const lparam = make_lparam(0x1E, false, false);

    try testing.expectEqual(@as(isize, 0x001E0001), lparam);
}

test "a message parameter packs an extended key" {
    const lparam = make_lparam(0, true, false);

    try testing.expectEqual(@as(isize, 0x01000001), lparam);
}

test "a message parameter packs a key release" {
    const lparam = make_lparam(0xFF, false, true);

    try testing.expectEqual(@as(isize, 0xC0FF0001), lparam);
}

test "an extended key reports as extended" {
    try testing.expect(is_extended_key(.arrow_left));
    try testing.expect(is_extended_key(.control_right));
    try testing.expect(!is_extended_key(.a));
}

test "the send timeout stays within its bound" {
    try testing.expect(send_timeout_ms >= 1);
    try testing.expect(send_timeout_ms <= 10000);
}

test {
    testing.refAllDecls(@This());
}
