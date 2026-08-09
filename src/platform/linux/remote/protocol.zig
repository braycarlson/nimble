const std = @import("std");

const keycode = @import("../../../keycode.zig");
const modifier = @import("../../../modifier.zig");
const response_mod = @import("../../../response.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;
const Response = response_mod.Response;

pub const version: u16 = 1;
pub const socket_name = "nimble.sock";
pub const lock_name = "nimbled.lock";
pub const path_bytes_max: u16 = 128;
pub const payload_bytes_max: u16 = 512;
pub const sequence_keys_max: u8 = 8;
pub const chord_keys_max: u8 = 8;
pub const filter_patterns_max: u8 = 16;
pub const text_bytes_max: u16 = 256;
pub const verdict_timeout_ms: u32 = 10;

pub const Tag = enum(u16) {
    hello = 1,
    hello_ok = 2,
    bind_key = 3,
    bind_chord = 4,
    bind_sequence = 5,
    unbind = 6,
    bound = 7,
    reject = 8,
    set_blocked = 9,
    claim_filter = 10,
    key_query = 11,
    verdict = 12,
    notify = 13,
    released = 14,
    simulate_key = 15,
    simulate_combination = 16,
    simulate_text = 17,
    simulate_button = 18,
    simulate_move = 19,
    simulate_scroll = 20,

    pub fn is_valid(tag: Tag) bool {
        const value = @intFromEnum(tag);

        return value >= 1 and value <= 20;
    }
};

pub const KeyAction = enum(u8) {
    down = 0,
    up = 1,
    press = 2,
    suppress = 3,
    dummy = 4,

    pub fn is_valid(action: KeyAction) bool {
        return @intFromEnum(action) <= 4;
    }
};

pub const Header = extern struct {
    tag: u16,
    size: u16,

    pub fn of(tag: Tag, comptime Payload: type) Header {
        return Header{ .tag = @intFromEnum(tag), .size = @sizeOf(Payload) };
    }
};

pub const Hello = extern struct {
    version: u16,
    reserved: u16 = 0,
};

pub const Pattern = extern struct {
    key: u8 = 0,
    modifiers: u8 = 0,
    match_any_modifiers: u8 = 0,
    match_any_key: u8 = 0,
};

pub const BindKey = extern struct {
    id: u32,
    key: u8,
    modifiers: u8,
    consume: u8,
    exempt: u8,
};

pub const BindChord = extern struct {
    id: u32,
    count: u8,
    consume: u8,
    exempt: u8,
    reserved: u8 = 0,
    keys: [chord_keys_max]Pattern,
};

pub const BindSequence = extern struct {
    id: u32,
    count: u8,
    consume: u8,
    exempt: u8,
    reserved: u8 = 0,
    keys: [sequence_keys_max]Pattern,
};

pub const Unbind = extern struct {
    id: u32,
};

pub const Bound = extern struct {
    id: u32,
};

pub const Reject = extern struct {
    id: u32,
    code: u32,
};

pub const SetBlocked = extern struct {
    keyboard: u8,
    mouse: u8,
    reserved: u16 = 0,
};

pub const ClaimFilter = extern struct {
    count: u8,
    reserved: u8 = 0,
    reserved_more: u16 = 0,
    patterns: [filter_patterns_max]Pattern,
};

pub const KeyQuery = extern struct {
    serial: u32,
    key: u8,
    modifiers: u8,
    down: u8,
    injected: u8,
};

pub const Verdict = extern struct {
    serial: u32,
    response: u8,
    reserved: u8 = 0,
    reserved_more: u16 = 0,
};

pub const Notify = extern struct {
    id: u32,
    key: u8,
    modifiers: u8,
    down: u8,
    reserved: u8 = 0,
    time_ms: i64,
};

pub const Released = extern struct {
    reserved: u32 = 0,
};

pub const SimulateKey = extern struct {
    key: u8,
    action: u8,
    reserved: u16 = 0,
};

pub const SimulateCombination = extern struct {
    key: u8,
    modifiers: u8,
    reserved: u16 = 0,
};

pub const SimulateText = extern struct {
    length: u16,
    delay_ms: u16,
    bytes: [text_bytes_max]u8,
};

pub const SimulateButton = extern struct {
    button: u8,
    down: u8,
    click: u8,
    reserved: u8 = 0,
};

pub const SimulateMove = extern struct {
    delta_x: i32,
    delta_y: i32,
};

pub const SimulateScroll = extern struct {
    vertical: i32,
    horizontal: i32,
};

comptime {
    assert(@sizeOf(Header) == 4);
    assert(@sizeOf(Hello) == 4);
    assert(@sizeOf(Pattern) == 4);
    assert(@sizeOf(BindKey) == 8);
    assert(@sizeOf(BindChord) == 8 + chord_keys_max * 4);
    assert(@sizeOf(BindSequence) == 8 + sequence_keys_max * 4);
    assert(@sizeOf(ClaimFilter) == 4 + filter_patterns_max * 4);
    assert(@sizeOf(KeyQuery) == 8);
    assert(@sizeOf(Verdict) == 8);
    assert(@sizeOf(Notify) == 16);
    assert(@sizeOf(SimulateText) == 4 + text_bytes_max);
    assert(@sizeOf(SimulateText) + @sizeOf(Header) <= payload_bytes_max);
    assert(verdict_timeout_ms > 0);
}

pub fn keycode_of(raw: u8) ?Keycode {
    return std.enums.fromInt(Keycode, raw);
}

pub fn modifiers_of(raw: u8) ?modifier.Set {
    if (raw > modifier.flag_all) {
        return null;
    }

    return modifier.Set{ .flags = @intCast(raw) };
}

pub fn response_of(raw: u8) ?Response {
    return std.enums.fromInt(Response, raw);
}

pub fn socket_path(buffer: *[path_bytes_max]u8) ?[:0]const u8 {
    return runtime_path(buffer, socket_name);
}

pub fn lock_path(buffer: *[path_bytes_max]u8) ?[:0]const u8 {
    return runtime_path(buffer, lock_name);
}

fn runtime_path(buffer: *[path_bytes_max]u8, comptime name: []const u8) ?[:0]const u8 {
    const uid = std.os.linux.getuid();
    const room = buffer[0 .. path_bytes_max - 1];

    const written = std.fmt.bufPrint(room, "/run/user/{d}/" ++ name, .{uid}) catch {
        return null;
    };

    assert(written.len < path_bytes_max);

    buffer[written.len] = 0;

    return buffer[0..written.len :0];
}

const testing = std.testing;

test "every tag round trips through its integer value" {
    try testing.expect(Tag.hello.is_valid());
    try testing.expect(Tag.simulate_scroll.is_valid());
    try testing.expectEqual(@as(u16, 1), @intFromEnum(Tag.hello));
    try testing.expectEqual(@as(u16, 20), @intFromEnum(Tag.simulate_scroll));
}

test "wire decoding rejects out of range values" {
    try testing.expect(keycode_of(255) == null);
    try testing.expect(modifiers_of(255) == null);
    try testing.expect(response_of(9) == null);
    try testing.expect(keycode_of(@intFromEnum(Keycode.a)) == Keycode.a);
    try testing.expect(response_of(1) == Response.consume);
}

test "the socket path is bounded and user scoped" {
    var buffer: [path_bytes_max]u8 = @splat(0);
    const path = socket_path(&buffer) orelse return error.PathUnavailable;

    try testing.expect(std.mem.startsWith(u8, path, "/run/user/"));
    try testing.expect(std.mem.endsWith(u8, path, socket_name));
}
