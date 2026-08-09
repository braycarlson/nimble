const std = @import("std");

const keycode = @import("../../../keycode.zig");
const record = @import("../record.zig");
const window = @import("../window.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const send_timeout_ms: u32 = 1000;

comptime {
    assert(send_timeout_ms > 0);
}

pub fn send_key(handle: window.Handle, code: Keycode, down: bool) bool {
    assert(handle != window.handle_none);

    record.push(.{ .kind = .message_key, .code = code, .down = down });

    return true;
}

pub fn send_key_down(handle: window.Handle, code: Keycode) bool {
    return send_key(handle, code, true);
}

pub fn send_key_up(handle: window.Handle, code: Keycode) bool {
    return send_key(handle, code, false);
}

pub fn send_key_press(handle: window.Handle, code: Keycode) bool {
    const down = send_key(handle, code, true);
    const up = send_key(handle, code, false);

    return down and up;
}

pub fn send_char(handle: window.Handle, character: u16) bool {
    assert(handle != window.handle_none);

    record.push(.{ .kind = .message_char, .amount = character });

    return true;
}

pub fn post_key(handle: window.Handle, code: Keycode, down: bool) bool {
    return send_key(handle, code, down);
}

pub fn post_key_down(handle: window.Handle, code: Keycode) bool {
    return send_key(handle, code, true);
}

pub fn post_key_up(handle: window.Handle, code: Keycode) bool {
    return send_key(handle, code, false);
}

pub fn post_key_press(handle: window.Handle, code: Keycode) bool {
    return send_key_press(handle, code);
}

pub fn post_char(handle: window.Handle, character: u16) bool {
    return send_char(handle, character);
}

pub fn release_modifiers(handle: window.Handle) bool {
    assert(handle != window.handle_none);

    const codes = [_]Keycode{
        .control_left,
        .control_right,
        .alt_left,
        .alt_right,
        .shift_left,
        .shift_right,
        .super_left,
        .super_right,
    };

    for (codes) |code| {
        _ = send_key(handle, code, false);
    }

    return true;
}
