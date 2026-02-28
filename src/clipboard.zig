const std = @import("std");

const w32 = @import("win32").everything;

const simulate_key = @import("simulate/key.zig");
const keycode = @import("keycode.zig");
const modifier = @import("modifier.zig");

pub const Error = error{
    AllocFailed,
    EmptyClipboard,
    GetFailed,
    LockFailed,
    OpenFailed,
    SetFailed,
};

pub fn set(text: []const u8) Error!void {
    std.debug.assert(text.len > 0);

    if (w32.OpenClipboard(null) == 0) {
        return Error.OpenFailed;
    }

    defer _ = w32.CloseClipboard();

    _ = w32.EmptyClipboard();

    const handle = w32.GlobalAlloc(w32.GMEM_MOVEABLE, text.len + 1);

    if (handle == 0) {
        return Error.AllocFailed;
    }

    const ptr = w32.GlobalLock(handle);

    if (ptr == null) {
        _ = w32.GlobalFree(handle);
        return Error.LockFailed;
    }

    const dest: [*]u8 = @ptrCast(ptr);

    @memcpy(dest[0..text.len], text);

    dest[text.len] = 0;

    _ = w32.GlobalUnlock(handle);

    const result = w32.SetClipboardData(
        @intFromEnum(w32.CF_TEXT),
        @ptrFromInt(@as(usize, @intCast(handle))),
    );

    if (result == null) {
        return Error.SetFailed;
    }
}

pub fn get(buffer: []u8) Error![]const u8 {
    std.debug.assert(buffer.len > 0);

    if (w32.OpenClipboard(null) == 0) {
        return Error.OpenFailed;
    }

    defer _ = w32.CloseClipboard();

    const handle = w32.GetClipboardData(@intFromEnum(w32.CF_TEXT));

    if (handle == null) {
        return Error.EmptyClipboard;
    }

    const handle_int: isize = @intCast(@intFromPtr(handle));
    const ptr = w32.GlobalLock(handle_int);

    if (ptr == null) {
        return Error.LockFailed;
    }

    defer _ = w32.GlobalUnlock(handle_int);

    const src: [*]const u8 = @ptrCast(ptr);

    var len: usize = 0;

    while (len < buffer.len and src[len] != 0) : (len += 1) {}

    @memcpy(buffer[0..len], src[0..len]);

    return buffer[0..len];
}

pub fn paste() bool {
    return simulate_key.combination(&modifier.Set.from(.{ .ctrl = true }), 'V');
}

pub fn copy() bool {
    return simulate_key.combination(&modifier.Set.from(.{ .ctrl = true }), 'C');
}

pub fn cut() bool {
    return simulate_key.combination(&modifier.Set.from(.{ .ctrl = true }), 'X');
}

pub fn select_all() bool {
    return simulate_key.combination(&modifier.Set.from(.{ .ctrl = true }), 'A');
}

pub fn select_left(count: u32) void {
    std.debug.assert(count > 0);

    _ = simulate_key.key_down(keycode.lshift);

    var i: u32 = 0;

    while (i < count) : (i += 1) {
        _ = simulate_key.press(keycode.left);
    }

    _ = simulate_key.key_up(keycode.lshift);
}

pub fn select_right(count: u32) void {
    std.debug.assert(count > 0);

    _ = simulate_key.key_down(keycode.lshift);

    var i: u32 = 0;

    while (i < count) : (i += 1) {
        _ = simulate_key.press(keycode.right);
    }

    _ = simulate_key.key_up(keycode.lshift);
}

pub fn replace(select_count: u32, text: []const u8) Error!void {
    std.debug.assert(select_count > 0);
    std.debug.assert(text.len > 0);

    select_left(select_count);

    try set(text);

    _ = paste();
}
