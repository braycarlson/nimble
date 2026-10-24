const std = @import("std");

const data_control = @import("wayland/data_control.zig");
const keycode = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");
const simulate_key = @import("simulate/key.zig");
const time = @import("time.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

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

var socket_path: [socket_bytes_max]u8 = @splat(0);
var socket_len: u16 = 0;

pub fn configure(path: []const u8) bool {
    if (path.len == 0) return false;
    if (path.len >= socket_bytes_max) return false;

    @memcpy(socket_path[0..path.len], path);

    socket_len = @intCast(path.len);

    assert(socket_len > 0);

    return true;
}

pub fn is_configured() bool {
    return socket_len > 0;
}

pub fn unconfigure() void {
    socket_len = 0;

    assert(!is_configured());
}

pub fn set(text: []const u8) Error!void {
    if (socket_len == 0) {
        return Error.ClipboardUnavailable;
    }

    var session = data_control.Session{};

    data_control.open(&session, socket_path[0..socket_len]) catch |err| return error_of(err);
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

pub fn paste() bool {
    return simulate_key.combination(&ctrl, .v);
}

pub fn replace(select_count: u32, text: []const u8) Error!void {
    assert(select_count > 0);
    assert(text.len > 0);

    try select_left(select_count);

    time.sleep_ms(settle_ms);

    try set(text);

    time.sleep_ms(settle_ms);

    if (!paste()) {
        return Error.SendFailed;
    }
}

fn select_left(count: u32) Error!void {
    assert(count > 0);

    if (count > select_count_max) {
        return Error.CountInvalid;
    }

    if (!simulate_key.key_down(Keycode.shift_left)) {
        return Error.SendFailed;
    }

    var index: u32 = 0;

    while (index < count) : (index += 1) {
        if (!simulate_key.press(.arrow_left)) {
            _ = simulate_key.key_up(Keycode.shift_left);

            return Error.SendFailed;
        }
    }

    assert(index == count);

    if (!simulate_key.key_up(Keycode.shift_left)) {
        return Error.SendFailed;
    }
}

const testing = std.testing;

test "configure refuses an empty or oversized socket path" {
    const long: [120]u8 = @splat('s');

    try testing.expect(!configure(""));
    try testing.expect(!configure(&long));
    try testing.expect(configure("/run/user/1000/wayland-0"));
    try testing.expect(is_configured());

    unconfigure();

    try testing.expect(!is_configured());
}

test "setting reports the clipboard unavailable without a configured socket" {
    unconfigure();

    const long: [text_bytes_max + 1]u8 = @splat('x');
    const short_refused = set("x");
    const long_refused = set(&long);

    try testing.expectError(Error.ClipboardUnavailable, short_refused);
    try testing.expectError(Error.ClipboardUnavailable, long_refused);
}

test "clipboard editing declines while synthesis is closed" {
    try testing.expect(!simulate_key.is_open());
    try testing.expect(!paste());
    try testing.expectError(Error.SendFailed, select_left(1));
    try testing.expectError(Error.SendFailed, replace(1, "x"));
}

test "selection refuses a count past its bound" {
    try testing.expectError(Error.CountInvalid, select_left(select_count_max + 1));
    try testing.expectError(Error.CountInvalid, replace(select_count_max + 1, "x"));
}
