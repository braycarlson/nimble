const std = @import("std");

const key_event = @import("../../event/key.zig");
const keyboard_mod = @import("../../keyboard.zig");
const keycode_mod = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");
const mouse_event = @import("../../event/mouse.zig");
const mouse_mod = @import("../../mouse.zig");
const position_module = @import("../../position.zig");
const remote = @import("../../remote.zig");
const response_mod = @import("../../response.zig");
const runtime = @import("../../runtime.zig");
const deferred = @import("deferred.zig");
const loop = @import("loop.zig");
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

const Keyboard = keyboard_mod.KeyboardType(.{
    .binding_count_max = remote.binding_count_max,
    .chord_count_max = 32,
    .sequence_count_max = 8,
});

const Mouse = mouse_mod.MouseType(.{});

const Kind = enum(u8) {
    key,
    chord,
    sequence,
};

const Registration = struct {
    id: u32,
    hook_id: u32 = 0,
    kind: Kind,
    consume: bool,
    callback: NotifyCallback,
    context: *anyopaque,
    client: *Client,

    fn notify(registration: *const Registration, key: ?*const Key) void {
        deferred.push(.{
            .run = deliver_notify,
            .owner = registration.client,
            .generation = registration.client.generation,
            .id = registration.id,
            .key = if (key) |value| value.* else null,
        });
    }
};

const Filter = struct {
    callback: FilterCallback,
    context: *anyopaque,
    patterns: [remote.filter_patterns_max]Pattern = undefined,
    count: u8 = 0,
};

const Release = struct {
    callback: ReleaseCallback,
    context: *anyopaque,
};

const client_count_max: u8 = 8;

var keyboard: Keyboard = undefined;
var mouse: Mouse = undefined;
var connections: [client_count_max]?*Client = @splat(null);
var generation_next: u32 = 1;
var runtime_owned: bool = false;
var filter_owner: ?*Client = null;

pub const Client = struct {
    connected: bool = false,
    generation: u32 = 0,
    id_next: u32 = 1,
    registrations: [remote.binding_count_max]?Registration = @splat(null),
    filter: ?Filter = null,
    release: ?Release = null,

    pub fn is_connected(client: *const Client) bool {
        return client.connected;
    }

    pub fn connect(client: *Client) PlatformError!void {
        assert(!client.is_connected());

        const slot = connection_free() orelse return error.ConnectFailed;

        if (connection_count() == 0) try open_hooks();

        connections[slot] = client;
        client.connected = true;
        client.generation = generation_next;
        generation_next +%= 1;

        assert(client.is_connected());
        assert(connection_count() >= 1);
    }

    pub fn disconnect(client: *Client) void {
        if (!client.connected) return;

        client.clear_bindings();

        if (filter_owner == client) {
            keyboard.clear_key_callback();
            filter_owner = null;
        }

        for (&connections) |*slot| {
            if (slot.* == client) slot.* = null;
        }

        client.* = .{};

        if (connection_count() == 0) close_hooks();

        assert(!client.is_connected());
    }

    pub fn bind_key(
        client: *Client,
        key: Keycode,
        modifiers: modifier.Set,
        options: BindOptions,
        callback: NotifyCallback,
        context: *anyopaque,
    ) (CapacityError || PlatformError || RequestError)!u32 {
        const registration = try client.allocate(.key, options, callback, context);

        registration.hook_id = keyboard.registry.register(
            key,
            modifiers,
            on_key,
            registration,
            .{ .block_exempt = options.exempt },
        ) catch |err| {
            client.forget(registration);

            return switch (err) {
                error.BindingsExhausted => error.RegistrationsExhausted,
                error.BindingDuplicate => error.BindingDuplicate,
                error.HandleUnknown => unreachable,
            };
        };

        return registration.id;
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

        const registration = try client.allocate(.chord, options, callback, context);

        registration.hook_id = keyboard.chord_registry.register(
            keys,
            on_chord,
            registration,
            .{},
        ) catch |err| {
            client.forget(registration);

            return switch (err) {
                error.ChordsExhausted => error.RegistrationsExhausted,
                error.ChordInvalid => error.ChordInvalid,
                error.HandleUnknown, error.TimeoutInvalid => unreachable,
            };
        };

        return registration.id;
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

        const registration = try client.allocate(.sequence, options, callback, context);

        registration.hook_id = keyboard.sequence_registry.register(
            text,
            on_sequence,
            registration,
            .{ .block_exempt = options.exempt },
        ) catch |err| {
            client.forget(registration);

            return switch (err) {
                error.SequencesExhausted => error.RegistrationsExhausted,
                error.SequenceTooLong => error.SequenceTooLong,
                error.CharacterInvalid => error.CharacterInvalid,
                error.SequenceEmpty => error.SequenceEmpty,
                error.HandleUnknown => unreachable,
            };
        };

        return registration.id;
    }

    pub fn unbind(client: *Client, id: u32) (PlatformError || RequestError)!void {
        assert(id >= 1);

        if (!client.connected) return error.ClientDisconnected;

        for (&client.registrations) |*slot| {
            if (slot.*) |*registration| {
                if (registration.id != id) continue;

                release(registration);
                slot.* = null;

                return;
            }
        }

        return error.HandleUnknown;
    }

    pub fn set_blocked(client: *Client, blocked: Blocked) (PlatformError || RequestError)!void {
        if (!client.connected) return error.ClientDisconnected;

        keyboard.source.reinstall();
        mouse.source.reinstall();

        if (blocked.keyboard) keyboard.block() else keyboard.unblock();
        if (blocked.mouse) mouse.block() else mouse.unblock();
    }

    pub fn set_filter(
        client: *Client,
        patterns: []const Pattern,
        callback: FilterCallback,
        context: *anyopaque,
    ) (PlatformError || RequestError)!void {
        assert(patterns.len <= remote.filter_patterns_max);

        if (!client.connected) return error.ClientDisconnected;

        var filter = Filter{
            .callback = callback,
            .context = context,
            .count = @intCast(patterns.len),
        };

        @memcpy(filter.patterns[0..patterns.len], patterns);

        client.filter = filter;
        filter_owner = client;

        keyboard.set_key_callback(Client, client, on_filter);
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

        _ = simulate.text.send_with_delay(text, delay_ms) catch |err| return switch (err) {
            error.DelayInvalid => error.DelayInvalid,
            error.SendFailed => error.SendFailed,
            error.TextInvalid => error.TextInvalid,
            error.TextTooLong => unreachable,
        };
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

        const vertical = scroll_axis(
            scroll.vertical,
            simulate.mouse.scroll_up,
            simulate.mouse.scroll_down,
        );

        const horizontal = scroll_axis(
            scroll.horizontal,
            simulate.mouse.scroll_right,
            simulate.mouse.scroll_left,
        );

        if (!vertical) return error.SendFailed;
        if (!horizontal) return error.SendFailed;
    }

    fn allocate(
        client: *Client,
        kind: Kind,
        options: BindOptions,
        callback: NotifyCallback,
        context: *anyopaque,
    ) (CapacityError || RequestError)!*Registration {
        if (!client.connected) return error.ClientDisconnected;

        for (&client.registrations) |*slot| {
            if (slot.* != null) continue;

            const id = client.id_next;

            slot.* = .{
                .id = id,
                .kind = kind,
                .consume = options.consume,
                .callback = callback,
                .context = context,
                .client = client,
            };

            client.id_next += 1;

            assert(id >= 1);

            return &slot.*.?;
        }

        return error.RegistrationsExhausted;
    }

    fn find(client: *const Client, id: u32) ?*const Registration {
        assert(id >= 1);

        for (&client.registrations) |*slot| {
            if (slot.*) |*registration| {
                if (registration.id == id) return registration;
            }
        }

        return null;
    }

    fn forget(client: *Client, registration: *const Registration) void {
        for (&client.registrations) |*slot| {
            const current = slot.* orelse continue;

            if (current.id == registration.id) slot.* = null;
        }
    }

    fn clear_bindings(client: *Client) void {
        for (&client.registrations) |*slot| {
            if (slot.*) |*registration| release(registration);

            slot.* = null;
        }
    }
};

fn open_hooks() PlatformError!void {
    assert(connection_count() == 0);

    if (!runtime.is_open()) {
        runtime.open(.{ .mode = .grab }) catch return error.ConnectFailed;

        runtime_owned = true;
    }

    errdefer release_runtime();

    keyboard.init(.{}) catch return error.ConnectFailed;
    errdefer keyboard.deinit();

    mouse.init(.{});

    keyboard.start() catch return error.ConnectFailed;
    errdefer keyboard.stop();

    mouse.start() catch return error.ConnectFailed;

    if (runtime_owned) runtime.set_release_callback(on_released);
}

fn close_hooks() void {
    assert(connection_count() == 0);

    keyboard.deinit();
    mouse.deinit();

    release_runtime();
}

fn release_runtime() void {
    if (!runtime_owned) return;

    runtime.set_release_callback(null);
    runtime.close();

    runtime_owned = false;
}

fn connection_count() u8 {
    var count: u8 = 0;

    for (connections) |slot| {
        if (slot != null) count += 1;
    }

    assert(count <= client_count_max);

    return count;
}

fn connection_free() ?usize {
    for (connections, 0..) |slot, index| {
        if (slot == null) return index;
    }

    return null;
}

fn on_released() void {
    for (connections) |slot| {
        const client = slot orelse continue;
        const handler = client.release orelse continue;

        if (!loop.is_loop_thread()) {
            handler.callback(handler.context);

            continue;
        }

        deferred.push(.{
            .run = deliver_release,
            .owner = client,
            .generation = client.generation,
        });
    }
}

fn deliver_notify(entry: *const deferred.Entry) void {
    const client = live_client(entry) orelse return;
    const registration = client.find(entry.id) orelse return;
    const key = if (entry.key) |*value| value else null;

    registration.callback(registration.context, key);
}

fn deliver_release(entry: *const deferred.Entry) void {
    const client = live_client(entry) orelse return;
    const handler = client.release orelse return;

    handler.callback(handler.context);
}

fn live_client(entry: *const deferred.Entry) ?*Client {
    for (connections) |slot| {
        const client = slot orelse continue;
        if (@as(*anyopaque, client) != entry.owner) continue;
        if (client.generation != entry.generation) return null;
        return client;
    }

    return null;
}

fn release(registration: *const Registration) void {
    const id = registration.hook_id;

    switch (registration.kind) {
        .key => keyboard.registry.unregister(id) catch |err| switch (err) {
            error.BindingDuplicate, error.HandleUnknown => unreachable,
        },
        .chord => keyboard.chord_registry.unregister(id) catch |err| switch (err) {
            error.ChordInvalid, error.HandleUnknown, error.TimeoutInvalid => unreachable,
        },
        .sequence => keyboard.sequence_registry.unregister(id) catch |err| switch (err) {
            error.CharacterInvalid, error.HandleUnknown, error.SequenceEmpty => unreachable,
        },
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

fn on_filter(client: *Client, key: *const Key) Response {
    const filter = client.filter orelse return .pass;

    for (filter.patterns[0..filter.count]) |*pattern| {
        if (remote.pattern_matches(pattern, key)) return filter.callback(filter.context, key);
    }

    return .pass;
}

fn scroll_axis(
    amount: i32,
    forward: *const fn (u32) bool,
    backward: *const fn (u32) bool,
) bool {
    if (amount == 0) return true;

    const clicks: u32 = @intCast(@abs(amount));
    return if (amount > 0) forward(clicks) else backward(clicks);
}
