const std = @import("std");

const data_control = @import("wayland.zig").data_control;
const keycode = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");
const simulate_key = @import("simulate.zig").key;
const time = @import("time.zig");
const uinput = @import("uinput.zig");

const assert = std.debug.assert;

const Device = uinput.Device;
const Keycode = keycode.Keycode;

socket_path: [socket_bytes_max]u8 = @splat(0),
socket_len: u16 = 0,

const Clipboard = @This();

const socket_bytes_max: u16 = 108;
const select_count_max: u32 = 1024;
const settle_ms: u32 = 20;

pub const Error = error{
    ClipboardUnavailable,
    CountInvalid,
    SendFailed,
    TextTooLong,
    TransferFailed,
};

pub const text_bytes_max: u16 = data_control.text_bytes_max;

const ctrl = modifier.Set.from(.{ .ctrl = true });

pub fn configure(clipboard: *Clipboard, path: []const u8) bool {
    if (path.len == 0) return false;
    if (path.len >= socket_bytes_max) return false;

    @memcpy(clipboard.socket_path[0..path.len], path);

    clipboard.socket_len = @intCast(path.len);

    assert(clipboard.socket_len > 0);

    return true;
}

pub fn is_configured(clipboard: *const Clipboard) bool {
    return clipboard.socket_len > 0;
}

pub fn unconfigure(clipboard: *Clipboard) void {
    clipboard.socket_len = 0;

    assert(!clipboard.is_configured());
}

pub fn set(clipboard: *const Clipboard, text: []const u8) Error!void {
    assert(text.len > 0);

    if (clipboard.socket_len == 0) {
        return Error.ClipboardUnavailable;
    }

    const socket = clipboard.socket_path[0..clipboard.socket_len];

    var session = data_control.Session{};

    data_control.open(&session, socket) catch |err| return error_of(err);
    defer session.close();

    data_control.set(&session, text) catch |err| return error_of(err);

    _ = data_control.serve(&session, text) catch return;
}

fn error_of(err: data_control.Error) Error {
    return switch (err) {
        error.TextTooLong => error.TextTooLong,
        error.ProtocolError, error.TransferFailed, error.WriteFailed => error.TransferFailed,
        error.ConnectFailed,
        error.NoDisplay,
        error.NoSeat,
        error.SocketFailed,
        error.TooManyGlobals,
        error.Unsupported,
        => error.ClipboardUnavailable,
    };
}

pub fn paste(out: *Device) bool {
    return simulate_key.combination(out, &ctrl, .v);
}

pub fn replace(
    clipboard: *const Clipboard,
    out: *Device,
    select_count: u32,
    text: []const u8,
) Error!void {
    assert(select_count > 0);
    assert(text.len > 0);

    try select_left(out, select_count);

    time.sleep_ms(settle_ms);

    try clipboard.set(text);

    time.sleep_ms(settle_ms);

    if (!paste(out)) {
        return Error.SendFailed;
    }
}

fn select_left(out: *Device, count: u32) Error!void {
    assert(count > 0);

    if (count > select_count_max) {
        return Error.CountInvalid;
    }

    if (!simulate_key.key_down(out, Keycode.shift_left)) {
        return Error.SendFailed;
    }

    var index: u32 = 0;

    while (index < count) : (index += 1) {
        if (!simulate_key.press(out, .arrow_left)) {
            _ = simulate_key.key_up(out, Keycode.shift_left);

            return Error.SendFailed;
        }
    }

    assert(index == count);

    if (!simulate_key.key_up(out, Keycode.shift_left)) {
        return Error.SendFailed;
    }
}

const testing = std.testing;

test "configure refuses an empty or oversized socket path" {
    var clipboard: Clipboard = .{};

    const long: [120]u8 = @splat('s');

    try testing.expect(!clipboard.configure(""));
    try testing.expect(!clipboard.configure(&long));
    try testing.expect(clipboard.configure("/run/user/1000/wayland-0"));
    try testing.expect(clipboard.is_configured());

    clipboard.unconfigure();

    try testing.expect(!clipboard.is_configured());
}

test "setting reports the clipboard unavailable without a configured socket" {
    const clipboard: Clipboard = .{};

    const long: [text_bytes_max + 1]u8 = @splat('x');
    const short_refused = clipboard.set("x");
    const long_refused = clipboard.set(&long);

    try testing.expectError(Error.ClipboardUnavailable, short_refused);
    try testing.expectError(Error.ClipboardUnavailable, long_refused);
}

test "clipboard editing declines while synthesis is closed" {
    const clipboard: Clipboard = .{};

    var out = Device{};

    try testing.expect(!simulate_key.is_open(&out));
    try testing.expect(!paste(&out));
    try testing.expectError(Error.SendFailed, select_left(&out, 1));
    try testing.expectError(Error.SendFailed, clipboard.replace(&out, 1, "x"));
}

test "selection refuses a count past its bound" {
    const clipboard: Clipboard = .{};

    var out = Device{};

    try testing.expectError(Error.CountInvalid, select_left(&out, select_count_max + 1));
    try testing.expectError(Error.CountInvalid, clipboard.replace(&out, select_count_max + 1, "x"));
}
