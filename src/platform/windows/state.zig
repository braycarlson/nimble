const std = @import("std");

const win32 = @import("win32.zig");

const core = @import("../../keycode.zig");
const mapping = @import("keycode.zig");

const assert = std.debug.assert;

const Keycode = core.Keycode;

pub const Snapshot = struct {};

pub fn capture() Snapshot {
    return Snapshot{};
}

pub fn is_key_down_at(snapshot: *const Snapshot, code: Keycode) bool {
    _ = snapshot;

    return is_key_down(code);
}

pub fn is_key_down(code: Keycode) bool {
    const virtual_key = mapping.to_native(code) orelse return false;

    assert(virtual_key >= mapping.value_min);
    assert(virtual_key <= mapping.value_max);

    const state = win32.GetAsyncKeyState(@intCast(virtual_key));

    return state < 0;
}
