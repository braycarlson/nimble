const std = @import("std");

const key_event = @import("../../event/key.zig");
const keyboard_mod = @import("../../keyboard.zig");
const keycode_mod = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");
const mouse_mod = @import("../../mouse.zig");
const pattern_mod = @import("../../builder/pattern.zig");
const response_mod = @import("../../response.zig");
const runtime = @import("../../runtime.zig");
const simulate = @import("simulate.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Keycode = keycode_mod.Keycode;
const Button = simulate.mouse.Button;
const Response = response_mod.Response;

pub const binding_count_max: u16 = 64;
pub const filter_patterns_max: u8 = 32;
pub const text_bytes_max: u16 = 1024;

pub const Error = error{
    BindFailed,
    ConnectFailed,
    NotConnected,
    TableFull,
};

pub const NotifyCallback = *const fn (context: ?*anyopaque, key: ?*const Key) void;
pub const FilterCallback = *const fn (context: ?*anyopaque, key: *const Key) Response;
pub const ReleaseCallback = *const fn (context: ?*anyopaque) void;

pub const BindOptions = struct {
    consume: bool = true,
    exempt: bool = false,
};

pub const Pattern = extern struct {
    key: u8 = 0,
    modifiers: u8 = 0,
    match_any_modifiers: u8 = 0,
    match_any_key: u8 = 0,
};

pub const KeyAction = enum(u8) {
    down = 0,
    up = 1,
    press = 2,
    suppress = 3,
    dummy = 4,

    pub fn is_valid(action: KeyAction) bool {
        return @intFromEnum(action) <= @intFromEnum(KeyAction.dummy);
    }
};

const Keyboard = keyboard_mod.KeyboardHookType(.{ .capacity = binding_count_max });
const Mouse = mouse_mod.MouseHookType(.{});

const Kind = enum(u8) {
    key = 0,
    chord = 1,
    sequence = 2,
};

const Registration = struct {
    used: bool = false,
    id: u32 = 0,
    hook_id: u32 = 0,
    kind: Kind = .key,
    consume: bool = true,
    callback: ?NotifyCallback = null,
    context: ?*anyopaque = null,

    fn notify(registration: *const Registration, key: ?*const Key) void {
        const callback = registration.callback orelse return;

        callback(registration.context, key);
    }
};

var keyboard: Keyboard = undefined;
var mouse: Mouse = undefined;
var clients: u8 = 0;
var runtime_owned: bool = false;

fn release_runtime() void {
    if (!runtime_owned) {
        return;
    }

    runtime.close();

    runtime_owned = false;

    assert(!runtime_owned);
}

comptime {
    assert(binding_count_max > 0);
    assert(filter_patterns_max > 0);
    assert(text_bytes_max > 0);
    assert(@typeInfo(KeyAction).@"enum".fields.len == 5);
}

pub const Client = struct {
    connected: bool = false,
    id_next: u32 = 1,
    registrations: [binding_count_max]Registration = @splat(.{}),
    filter_callback: ?FilterCallback = null,
    filter_context: ?*anyopaque = null,
    filter_patterns: [filter_patterns_max]Pattern = @splat(.{}),
    filter_count: u8 = 0,
    release_callback: ?ReleaseCallback = null,
    release_context: ?*anyopaque = null,

    pub fn is_connected(client: *const Client) bool {
        return client.connected;
    }

    pub fn connect(client: *Client) Error!void {
        assert(!client.is_connected());

        if (clients == 0) {
            if (!runtime.is_open()) {
                runtime.open(.{ .mode = .grab }) catch {
                    return Error.ConnectFailed;
                };

                runtime_owned = true;
            }

            errdefer release_runtime();

            keyboard = Keyboard.init();
            mouse = Mouse.init();

            keyboard.start() catch {
                return Error.ConnectFailed;
            };

            mouse.start() catch {
                keyboard.stop();

                return Error.ConnectFailed;
            };
        }

        clients += 1;
        client.connected = true;

        assert(client.is_connected());
    }

    pub fn disconnect(client: *Client) void {
        if (!client.connected) {
            return;
        }

        client.clear_bindings();

        client.filter_callback = null;
        client.filter_context = null;
        client.filter_count = 0;
        client.release_callback = null;
        client.release_context = null;
        client.connected = false;

        assert(clients > 0);

        clients -= 1;

        if (clients == 0) {
            keyboard.clear_key_callback();
            keyboard.deinit();
            mouse.deinit();

            release_runtime();
        }

        assert(!client.is_connected());
    }

    pub fn bind_key(
        client: *Client,
        key: Keycode,
        modifiers: modifier.Set,
        options: BindOptions,
        callback: ?NotifyCallback,
        context: ?*anyopaque,
    ) Error!u32 {
        const slot = try client.allocate(.key, options, callback, context);
        const registration = &client.registrations[slot];

        registration.hook_id = keyboard.registry.register(
            key,
            modifiers,
            on_key,
            registration,
            .{ .block_exempt = options.exempt },
        ) catch {
            registration.* = .{};

            return Error.BindFailed;
        };

        return registration.id;
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
        const slot = try client.allocate(.chord, options, callback, context);
        const registration = &client.registrations[slot];

        registration.hook_id = keyboard.chord_registry.register(
            keys,
            on_chord,
            registration,
            .{},
        ) catch {
            registration.* = .{};

            return Error.BindFailed;
        };

        return registration.id;
    }

    pub fn bind_sequence(
        client: *Client,
        characters: []const u8,
        options: BindOptions,
        callback: ?NotifyCallback,
        context: ?*anyopaque,
    ) Error!u32 {
        const slot = try client.allocate(.sequence, options, callback, context);
        const registration = &client.registrations[slot];

        registration.hook_id = keyboard.sequence_registry.register(
            characters,
            on_sequence,
            registration,
            .{ .block_exempt = options.exempt },
        ) catch {
            registration.* = .{};

            return Error.BindFailed;
        };

        return registration.id;
    }

    pub fn unbind(client: *Client, id: u32) void {
        var slot: u16 = 0;

        while (slot < binding_count_max) : (slot += 1) {
            const registration = &client.registrations[slot];

            if (!registration.used or registration.id != id) continue;

            release(registration);

            registration.* = .{};

            return;
        }
    }

    pub fn set_blocked(client: *Client, keyboard_blocked: bool, mouse_blocked: bool) void {
        if (!client.connected) {
            return;
        }

        keyboard.set_blocked(keyboard_blocked);
        mouse.set_blocked(mouse_blocked);
    }

    pub fn set_filter(
        client: *Client,
        patterns: []const Pattern,
        callback: ?FilterCallback,
        context: ?*anyopaque,
    ) Error!void {
        if (patterns.len > filter_patterns_max) {
            return Error.BindFailed;
        }

        if (!client.connected) {
            return Error.NotConnected;
        }

        client.filter_callback = callback;
        client.filter_context = context;
        client.filter_count = @intCast(patterns.len);

        for (patterns, 0..) |pattern, position| {
            client.filter_patterns[position] = pattern;
        }

        if (callback == null) {
            keyboard.clear_key_callback();

            return;
        }

        keyboard.set_key_callback(on_filter, client);
    }

    pub fn set_release_callback(
        client: *Client,
        callback: ?ReleaseCallback,
        context: ?*anyopaque,
    ) void {
        client.release_callback = callback;
        client.release_context = context;
    }

    pub fn simulate_key(client: *Client, key: Keycode, action: KeyAction) void {
        if (!client.connected) {
            return;
        }

        _ = switch (action) {
            .down => keyboard.key_down(key),
            .up, .suppress => keyboard.key_up(key),
            .press => keyboard.press(key),
            .dummy => keyboard.press(.silent),
        };
    }

    pub fn simulate_combination(client: *Client, modifiers: modifier.Set, key: Keycode) void {
        if (!client.connected) {
            return;
        }

        _ = keyboard.send_chord(key, modifiers);
    }

    pub fn simulate_text(client: *Client, text: []const u8, delay_ms: u16) void {
        if (!client.connected or text.len > text_bytes_max) {
            return;
        }

        var typer = keyboard.typer();

        _ = typer.send_with_delay(text, delay_ms) catch {
            return;
        };
    }

    pub fn simulate_button(client: *Client, button: u8, down: bool, click: bool) void {
        if (!client.connected) {
            return;
        }

        const target = to_button(button) orelse return;

        if (click) {
            _ = mouse.click(target);

            return;
        }

        _ = if (down) mouse.button_down(target) else mouse.button_up(target);
    }

    pub fn simulate_move(client: *Client, delta_x: i32, delta_y: i32) void {
        if (!client.connected) {
            return;
        }

        _ = mouse.move_relative(delta_x, delta_y);
    }

    pub fn simulate_scroll(client: *Client, vertical: i32, horizontal: i32) void {
        if (!client.connected) {
            return;
        }

        scroll_axis(vertical, Mouse.scroll_up, Mouse.scroll_down);
        scroll_axis(horizontal, Mouse.scroll_right, Mouse.scroll_left);
    }

    fn allocate(
        client: *Client,
        kind: Kind,
        options: BindOptions,
        callback: ?NotifyCallback,
        context: ?*anyopaque,
    ) Error!u16 {
        if (!client.connected) {
            return Error.NotConnected;
        }

        var slot: u16 = 0;

        while (slot < binding_count_max) : (slot += 1) {
            if (client.registrations[slot].used) continue;

            client.registrations[slot] = .{
                .used = true,
                .id = client.id_next,
                .kind = kind,
                .consume = options.consume,
                .callback = callback,
                .context = context,
            };

            client.id_next += 1;

            return slot;
        }

        return Error.TableFull;
    }

    fn clear_bindings(client: *Client) void {
        var slot: u16 = 0;

        while (slot < binding_count_max) : (slot += 1) {
            const registration = &client.registrations[slot];

            if (!registration.used) continue;

            release(registration);

            registration.* = .{};
        }
    }
};

fn release(registration: *const Registration) void {
    switch (registration.kind) {
        .key => keyboard.registry.unregister(registration.hook_id) catch return,
        .chord => keyboard.chord_registry.unregister(registration.hook_id) catch return,
        .sequence => keyboard.sequence_registry.unregister(registration.hook_id) catch return,
    }
}

fn on_key(context: *anyopaque, key: *const Key) Response {
    const registration: *Registration = @ptrCast(@alignCast(context));

    registration.notify(key);

    return if (registration.consume) .consume else .pass;
}

fn on_chord(context: *anyopaque) Response {
    const registration: *Registration = @ptrCast(@alignCast(context));

    registration.notify(null);

    return if (registration.consume) .consume else .pass;
}

fn on_sequence(context: *anyopaque) void {
    const registration: *Registration = @ptrCast(@alignCast(context));

    registration.notify(null);
}

fn on_filter(context: *anyopaque, key: *const Key) ?Response {
    const client: *Client = @ptrCast(@alignCast(context));
    const callback = client.filter_callback orelse return null;

    if (!matches_filter(client, key)) {
        return null;
    }

    return callback(client.filter_context, key);
}

fn matches_filter(client: *const Client, key: *const Key) bool {
    var index: u8 = 0;

    while (index < client.filter_count) : (index += 1) {
        const pattern = client.filter_patterns[index];

        if (pattern.match_any_key == 0 and pattern.key != @intFromEnum(key.value)) continue;
        if (pattern.match_any_modifiers == 0 and pattern.modifiers != key.modifiers.flags) continue;

        return true;
    }

    return false;
}

fn to_button(button: u8) ?Button {
    return switch (button) {
        0 => .left,
        1 => .right,
        2 => .middle,
        3 => .x1,
        4 => .x2,
        else => null,
    };
}

fn scroll_axis(
    amount: i32,
    forward: *const fn (*Mouse, u32) bool,
    backward: *const fn (*Mouse, u32) bool,
) void {
    if (amount == 0) {
        return;
    }

    const clicks: u32 = @intCast(@abs(amount));

    _ = if (amount > 0) forward(&mouse, clicks) else backward(&mouse, clicks);
}

const testing = std.testing;

test "every client method compiles against the in-process hook" {
    _ = &Client.is_connected;
    _ = &Client.connect;
    _ = &Client.disconnect;
    _ = &Client.bind_key;
    _ = &Client.bind_chord;
    _ = &Client.bind_sequence;
    _ = &Client.unbind;
    _ = &Client.set_blocked;
    _ = &Client.set_filter;
    _ = &Client.set_release_callback;
    _ = &Client.simulate_key;
    _ = &Client.simulate_combination;
    _ = &Client.simulate_text;
    _ = &Client.simulate_button;
    _ = &Client.simulate_move;
    _ = &Client.simulate_scroll;
    _ = &bind_pattern_probe;

    try testing.expect(@sizeOf(Client) > 0);
}

fn bind_pattern_probe(client: *Client) Error!u32 {
    return client.bind_pattern("Ctrl+Alt+M", .{}, null, null);
}

test "a fresh client is disconnected and holds no bindings" {
    const client = Client{};

    try testing.expect(!client.is_connected());
    try testing.expectEqual(@as(u32, 1), client.id_next);
    try testing.expectEqual(@as(u8, 0), client.filter_count);
}

test "a filter pattern matches on key, on modifiers, and on wildcards" {
    var client = Client{};

    client.filter_count = 2;
    client.filter_patterns[0] = .{ .key = @intFromEnum(Keycode.a), .modifiers = 0 };
    client.filter_patterns[1] = .{ .key = 0, .modifiers = 0, .match_any_key = 1 };

    const exact = Key{ .value = .a, .down = true };

    try testing.expect(matches_filter(&client, &exact));

    client.filter_count = 1;

    const other = Key{ .value = .b, .down = true };

    try testing.expect(!matches_filter(&client, &other));
}

test "every simulate button maps onto a mouse button" {
    try testing.expectEqual(Button.left, to_button(0).?);
    try testing.expectEqual(Button.right, to_button(1).?);
    try testing.expectEqual(Button.middle, to_button(2).?);
    try testing.expect(to_button(5) == null);
}
