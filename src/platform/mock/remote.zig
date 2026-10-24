const std = @import("std");

const key_event = @import("../../event/key.zig");
const keycode_mod = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");
const mouse_event = @import("../../event/mouse.zig");
const position_module = @import("../../position.zig");
const record = @import("record.zig");
const remote = @import("../../remote.zig");
const response_mod = @import("../../response.zig");
const simulate = @import("simulate.zig");

const assert = std.debug.assert;

const BindOptions = remote.Client.BindOptions;
const Blocked = remote.Client.Blocked;
const ButtonAction = remote.Client.ButtonAction;
const CapacityError = remote.CapacityError;
const Key = key_event.Key;
const KeyAction = remote.Client.KeyAction;
const Keycode = keycode_mod.Keycode;
const MouseEvent = mouse_event.MouseEvent;
const Pattern = remote.Client.Pattern;
const PlatformError = remote.PlatformError;
const Position = position_module.Position;
const RequestError = remote.RequestError;
const Response = response_mod.Response;
const Scroll = remote.Client.Scroll;

pub const NotifyCallback = *const fn (context: *anyopaque, key: ?*const Key) void;
pub const FilterCallback = *const fn (context: *anyopaque, key: *const Key) Response;
pub const ReleaseCallback = *const fn (context: *anyopaque) void;

const Registration = struct {
    id: u32,
    callback: NotifyCallback,
    context: *anyopaque,
};

const Filter = struct {
    callback: FilterCallback,
    context: *anyopaque,
};

const Release = struct {
    callback: ReleaseCallback,
    context: *anyopaque,
};

pub const Client = struct {
    connected: bool = false,
    registrations: [remote.binding_count_max]?Registration = @splat(null),
    id_next: u32 = 1,
    blocked: Blocked = .{},
    filter: ?Filter = null,
    release: ?Release = null,

    pub fn is_connected(client: *const Client) bool {
        return client.connected;
    }

    pub fn connect(client: *Client) PlatformError!void {
        assert(!client.connected);

        client.connected = true;
    }

    pub fn disconnect(client: *Client) void {
        client.* = .{};

        assert(!client.connected);
    }

    pub fn bind_key(
        client: *Client,
        key: Keycode,
        modifiers: modifier.Set,
        options: BindOptions,
        callback: NotifyCallback,
        context: *anyopaque,
    ) (CapacityError || PlatformError || RequestError)!u32 {
        _ = key;
        _ = modifiers;
        _ = options;

        return client.allocate(callback, context);
    }

    pub fn bind_chord(
        client: *Client,
        keys: []const Keycode,
        options: BindOptions,
        callback: NotifyCallback,
        context: *anyopaque,
    ) (CapacityError || PlatformError || RequestError)!u32 {
        assert(keys.len >= 2);
        assert(keys.len <= remote.chord_keys_max);

        _ = options;

        return client.allocate(callback, context);
    }

    pub fn bind_sequence(
        client: *Client,
        text: []const u8,
        options: BindOptions,
        callback: NotifyCallback,
        context: *anyopaque,
    ) (CapacityError || PlatformError || RequestError)!u32 {
        assert(text.len >= 1);
        assert(text.len <= remote.sequence_bytes_max);

        _ = options;

        return client.allocate(callback, context);
    }

    pub fn unbind(client: *Client, id: u32) (PlatformError || RequestError)!void {
        assert(id >= 1);

        if (!client.connected) return error.ClientDisconnected;

        for (&client.registrations) |*registration| {
            const current = registration.* orelse continue;
            if (current.id != id) continue;

            registration.* = null;

            return;
        }

        return error.HandleUnknown;
    }

    pub fn set_blocked(client: *Client, blocked: Blocked) (PlatformError || RequestError)!void {
        if (!client.connected) return error.ClientDisconnected;

        client.blocked = blocked;
    }

    pub fn set_filter(
        client: *Client,
        patterns: []const Pattern,
        callback: FilterCallback,
        context: *anyopaque,
    ) (PlatformError || RequestError)!void {
        assert(patterns.len <= remote.filter_patterns_max);

        if (!client.connected) return error.ClientDisconnected;

        client.filter = .{ .callback = callback, .context = context };
    }

    pub fn set_release_callback(
        client: *Client,
        callback: ReleaseCallback,
        context: *anyopaque,
    ) void {
        client.release = .{ .callback = callback, .context = context };
    }

    pub fn simulate_key(
        client: *Client,
        key: Keycode,
        action: KeyAction,
    ) (PlatformError || RequestError)!void {
        if (!client.connected) return error.ClientDisconnected;

        const sent = switch (action) {
            .down => simulate.key.key_down(key),
            .up => simulate.key.key_up(key),
            .press => simulate.key.press(key),
            .suppress => simulate.key.suppress(key),
            .dummy => simulate.key.dummy(),
        };

        if (!sent) return error.SendFailed;
    }

    pub fn simulate_combination(
        client: *Client,
        modifiers: modifier.Set,
        key: Keycode,
    ) (PlatformError || RequestError)!void {
        if (!client.connected) return error.ClientDisconnected;
        if (!simulate.key.combination(&modifiers, key)) return error.SendFailed;
    }

    pub fn simulate_text(
        client: *Client,
        text: []const u8,
        delay_ms: u16,
    ) (PlatformError || RequestError)!void {
        assert(text.len <= remote.text_bytes_max);
        assert(delay_ms <= remote.delay_ms_max);

        if (!client.connected) return error.ClientDisconnected;

        record.push_text(.text_send, text);
    }

    pub fn simulate_button(
        client: *Client,
        button: MouseEvent.Button,
        action: ButtonAction,
    ) (PlatformError || RequestError)!void {
        if (!client.connected) return error.ClientDisconnected;

        const sent = switch (action) {
            .down => simulate.mouse.button_down(button),
            .up => simulate.mouse.button_up(button),
            .click => simulate.mouse.click(button),
        };

        if (!sent) return error.SendFailed;
    }

    pub fn simulate_move(client: *Client, offset: Position) (PlatformError || RequestError)!void {
        if (!client.connected) return error.ClientDisconnected;
        if (!simulate.mouse.move_relative(offset)) return error.SendFailed;
    }

    pub fn simulate_scroll(client: *Client, scroll: Scroll) (PlatformError || RequestError)!void {
        assert(remote.scroll_valid(scroll));

        if (!client.connected) return error.ClientDisconnected;

        record.push(.{ .kind = .mouse_scroll, .amount = scroll.vertical, .x = scroll.horizontal });
    }

    fn allocate(
        client: *Client,
        callback: NotifyCallback,
        context: *anyopaque,
    ) (CapacityError || RequestError)!u32 {
        if (!client.connected) return error.ClientDisconnected;

        for (&client.registrations) |*registration| {
            if (registration.* != null) continue;

            const id = client.id_next;

            registration.* = .{ .id = id, .callback = callback, .context = context };
            client.id_next += 1;

            assert(id >= 1);

            return id;
        }

        return error.RegistrationsExhausted;
    }
};

const testing = std.testing;

test "the mock client routes synthesis through the mock record" {
    record.reset();

    var client = Client{};

    try testing.expectError(error.ClientDisconnected, client.simulate_move(.zero));

    try client.connect();
    try client.simulate_move(.{ .x = 4, .y = 5 });

    try testing.expectEqual(@as(u16, 1), record.count_of(.mouse_move));

    client.disconnect();

    try testing.expect(!client.is_connected());

    record.reset();
}

test "the mock client hands out and forgets registrations" {
    var client = Client{};
    var context: u8 = 0;

    try client.connect();
    defer client.disconnect();

    const id = try client.bind_key(.a, .{}, .{}, ignore_notify, &context);

    try client.unbind(id);
    try testing.expectError(error.HandleUnknown, client.unbind(id));
}

fn ignore_notify(_: *anyopaque, _: ?*const Key) void {}
