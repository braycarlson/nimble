const std = @import("std");

const key_event = @import("../../event/key.zig");
const keycode_mod = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");
const pattern_mod = @import("../../builder/pattern.zig");
const record = @import("record.zig");
const response_mod = @import("../../response.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Keycode = keycode_mod.Keycode;
const Response = response_mod.Response;

pub const Error = error{
    BindFailed,
    ConnectFailed,
    NotConnected,
    TableFull,
};

pub const NotifyCallback = *const fn (context: ?*anyopaque, key: ?*const Key) void;
pub const FilterCallback = *const fn (context: ?*anyopaque, key: *const Key) Response;
pub const ReleaseCallback = *const fn (context: ?*anyopaque) void;

pub const KeyAction = enum(u8) {
    down = 0,
    up = 1,
    press = 2,
    suppress = 3,
    dummy = 4,
};

pub const BindOptions = struct {
    consume: bool = true,
    exempt: bool = false,
};

pub const Pattern = struct {
    key: u8 = 0,
    modifiers: u8 = 0,
    match_any_modifiers: u8 = 0,
    match_any_key: u8 = 0,
};

pub const Client = struct {
    connected: bool = false,
    id_next: u32 = 1,

    pub fn is_connected(client: *const Client) bool {
        return client.connected;
    }

    pub fn connect(client: *Client) Error!void {
        client.connected = true;
    }

    pub fn disconnect(client: *Client) void {
        client.connected = false;
    }

    pub fn bind_key(
        client: *Client,
        key: Keycode,
        modifiers: modifier.Set,
        options: BindOptions,
        callback: ?NotifyCallback,
        context: ?*anyopaque,
    ) Error!u32 {
        _ = key;
        _ = modifiers;
        _ = options;
        _ = callback;
        _ = context;

        return client.next_id();
    }

    pub fn bind_pattern(
        client: *Client,
        comptime pattern: []const u8,
        options: BindOptions,
        callback: ?NotifyCallback,
        context: ?*anyopaque,
    ) Error!u32 {
        const parsed = comptime pattern_mod.parse(pattern);

        return client.bind_key(parsed.key, parsed.modifiers, options, callback, context);
    }

    pub fn bind_chord(
        client: *Client,
        keys: []const Keycode,
        options: BindOptions,
        callback: ?NotifyCallback,
        context: ?*anyopaque,
    ) Error!u32 {
        _ = keys;
        _ = options;
        _ = callback;
        _ = context;

        return client.next_id();
    }

    pub fn bind_sequence(
        client: *Client,
        characters: []const u8,
        options: BindOptions,
        callback: ?NotifyCallback,
        context: ?*anyopaque,
    ) Error!u32 {
        _ = characters;
        _ = options;
        _ = callback;
        _ = context;

        return client.next_id();
    }

    pub fn unbind(client: *Client, id: u32) void {
        _ = client;
        _ = id;
    }

    pub fn set_blocked(client: *Client, keyboard: bool, mouse: bool) void {
        _ = client;
        _ = keyboard;
        _ = mouse;
    }

    pub fn set_filter(
        client: *Client,
        patterns: []const Pattern,
        callback: ?FilterCallback,
        context: ?*anyopaque,
    ) Error!void {
        _ = client;
        _ = patterns;
        _ = callback;
        _ = context;
    }

    pub fn set_release_callback(
        client: *Client,
        callback: ?ReleaseCallback,
        context: ?*anyopaque,
    ) void {
        _ = client;
        _ = callback;
        _ = context;
    }

    pub fn simulate_key(client: *Client, key: Keycode, action: KeyAction) void {
        _ = client;

        const kind: record.Kind = switch (action) {
            .down => .key_down,
            .up => .key_up,
            .press => .key_press,
            .suppress => .key_up,
            .dummy => .key_dummy,
        };

        record.push(.{ .kind = kind, .code = key });
    }

    pub fn simulate_combination(client: *Client, modifiers: modifier.Set, key: Keycode) void {
        _ = client;

        record.push(.{ .kind = .key_combination, .code = key, .modifiers = modifiers });
    }

    pub fn simulate_text(client: *Client, text: []const u8, delay_ms: u16) void {
        _ = client;
        _ = delay_ms;

        record.push_text(.text_send, text);
    }

    pub fn simulate_button(client: *Client, button: u8, down: bool, click: bool) void {
        _ = client;

        const kind: record.Kind = if (down or click) .mouse_down else .mouse_up;

        record.push(.{ .kind = kind, .button = button, .down = down });
    }

    pub fn simulate_move(client: *Client, delta_x: i32, delta_y: i32) void {
        _ = client;

        record.push(.{ .kind = .mouse_move, .x = delta_x, .y = delta_y });
    }

    pub fn simulate_scroll(client: *Client, vertical: i32, horizontal: i32) void {
        _ = client;

        record.push(.{ .kind = .mouse_scroll, .amount = vertical, .x = horizontal });
    }

    fn next_id(client: *Client) u32 {
        const id = client.id_next;

        client.id_next += 1;

        assert(id >= 1);

        return id;
    }
};

const testing = std.testing;

test "the mock client records the simulate calls routed through it" {
    record.reset();

    var client = Client{};

    try client.connect();

    try testing.expect(client.is_connected());

    client.simulate_move(4, 5);

    try testing.expectEqual(@as(u16, 1), record.count_of(.mouse_move));

    client.disconnect();

    try testing.expect(!client.is_connected());

    record.reset();
}
