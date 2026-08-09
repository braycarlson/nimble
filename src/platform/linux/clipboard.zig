const std = @import("std");

const client = @import("wayland/client.zig");
const data_control = @import("wayland/data_control.zig");
const keycode = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");
const simulate_key = @import("simulate/key.zig");
const time = @import("time.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const interface_ext = "ext_data_control_manager_v1";
pub const interface_wlr = "zwlr_data_control_manager_v1";
pub const socket_bytes_max: u16 = 108;
pub const select_count_max: u32 = 1024;
pub const settle_ms: u32 = 20;

pub const Error = data_control.Error || error{
    InvalidCount,
    SendFailed,
};

pub const text_bytes_max: u16 = data_control.text_bytes_max;

const ctrl = modifier.Set.from(.{ .ctrl = true });

var socket_path: [socket_bytes_max]u8 = @splat(0);
var socket_len: u16 = 0;
var probed: bool = false;
var available: bool = false;

comptime {
    assert(interface_ext.len > 0);
    assert(interface_wlr.len > 0);
}

pub fn configure(path: []const u8) bool {
    if (path.len == 0 or path.len >= socket_bytes_max) {
        return false;
    }

    @memcpy(socket_path[0..path.len], path);

    socket_len = @intCast(path.len);
    probed = false;
    available = false;

    assert(socket_len > 0);

    return true;
}

pub fn is_configured() bool {
    return socket_len > 0;
}

pub fn invalidate() void {
    probed = false;
    available = false;
}

pub fn is_supported() bool {
    if (probed) {
        return available;
    }

    probed = true;

    if (socket_len == 0) {
        return false;
    }

    var connection = client.connect(socket_path[0..socket_len]) catch return false;
    defer connection.close();

    connection.get_registry() catch return false;
    connection.roundtrip() catch return false;

    available = connection.has(interface_ext) or connection.has(interface_wlr);

    return available;
}

pub fn set(text: []const u8) Error!void {
    if (socket_len == 0) {
        return Error.Unsupported;
    }

    var session = data_control.Session{};

    try data_control.open(&session, socket_path[0..socket_len]);
    defer session.close();

    try data_control.set(&session, text);

    _ = data_control.serve(&session, text) catch return;
}

pub fn get(buffer: []u8) Error![]const u8 {
    assert(buffer.len > 0);

    if (socket_len == 0) {
        return Error.Unsupported;
    }

    var session = data_control.Session{};

    try data_control.open(&session, socket_path[0..socket_len]);
    defer session.close();

    const size = try data_control.get(&session, buffer);

    assert(size <= buffer.len);

    return buffer[0..size];
}

pub fn clear() Error!void {
    return set("");
}

pub fn paste() bool {
    return simulate_key.combination(&ctrl, .v);
}

pub fn copy() bool {
    return simulate_key.combination(&ctrl, .c);
}

pub fn cut() bool {
    return simulate_key.combination(&ctrl, .x);
}

pub fn select_all() bool {
    return simulate_key.combination(&ctrl, .a);
}

pub fn select_left(count: u32) Error!void {
    return select(count, .arrow_left);
}

pub fn select_right(count: u32) Error!void {
    return select(count, .arrow_right);
}

fn select(count: u32, direction: Keycode) Error!void {
    assert(count > 0);
    assert(direction == .arrow_left or direction == .arrow_right);

    if (count > select_count_max) {
        return Error.InvalidCount;
    }

    if (!simulate_key.key_down(Keycode.shift_left)) {
        return Error.SendFailed;
    }

    var index: u32 = 0;

    while (index < count) : (index += 1) {
        if (!simulate_key.press(direction)) {
            _ = simulate_key.key_up(Keycode.shift_left);

            return Error.SendFailed;
        }
    }

    assert(index == count);

    if (!simulate_key.key_up(Keycode.shift_left)) {
        return Error.SendFailed;
    }
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

pub const Clipboard = struct {
    pub fn init() Clipboard {
        return Clipboard{};
    }

    pub fn set(_: Clipboard, text: []const u8) Error!void {
        return @import("clipboard.zig").set(text);
    }

    pub fn get(_: Clipboard, buffer: []u8) Error![]const u8 {
        return @import("clipboard.zig").get(buffer);
    }

    pub fn clear(_: Clipboard) Error!void {
        return @import("clipboard.zig").clear();
    }

    pub fn paste(_: Clipboard) bool {
        return @import("clipboard.zig").paste();
    }

    pub fn copy(_: Clipboard) bool {
        return @import("clipboard.zig").copy();
    }

    pub fn cut(_: Clipboard) bool {
        return @import("clipboard.zig").cut();
    }

    pub fn select_all(_: Clipboard) bool {
        return @import("clipboard.zig").select_all();
    }

    pub fn replace(_: Clipboard, select_count: u32, text: []const u8) Error!void {
        assert(select_count > 0);
        assert(text.len > 0);

        return @import("clipboard.zig").replace(select_count, text);
    }
};

const testing = std.testing;

test "clipboard is unsupported without a configured socket" {
    socket_len = 0;
    invalidate();

    try testing.expect(!is_configured());
    try testing.expect(!is_supported());
}

test "configure refuses an empty or oversized socket path" {
    const long = "s" ** 120;

    try testing.expect(!configure(""));
    try testing.expect(!configure(long));
    try testing.expect(configure("/run/user/1000/wayland-0"));
    try testing.expect(is_configured());

    socket_len = 0;
    invalidate();
}

test "transfer reports Unsupported without a configured socket" {
    socket_len = 0;
    invalidate();

    var buffer: [8]u8 = undefined;

    try testing.expectError(Error.Unsupported, set("x"));
    try testing.expectError(Error.Unsupported, get(&buffer));
    try testing.expectError(Error.Unsupported, clear());
}

test "over-long text is refused before any protocol work" {
    socket_len = 0;
    invalidate();

    const long = "x" ** (text_bytes_max + 1);

    try testing.expectError(Error.Unsupported, set(long));
}

test "the probe result is cached after the first query" {
    socket_len = 0;
    invalidate();

    try testing.expect(!is_supported());
    try testing.expect(probed);
    try testing.expect(!is_supported());
}

test "clipboard editing declines while synthesis is closed" {
    try testing.expect(!simulate_key.is_open());
    try testing.expect(!paste());
    try testing.expect(!copy());
    try testing.expect(!cut());
    try testing.expect(!select_all());
    try testing.expectError(Error.SendFailed, select_left(1));
    try testing.expectError(Error.SendFailed, select_right(1));
}

test "selection refuses a count past its bound" {
    try testing.expectError(Error.InvalidCount, select_left(select_count_max + 1));
    try testing.expectError(Error.InvalidCount, select_right(select_count_max + 1));
}
