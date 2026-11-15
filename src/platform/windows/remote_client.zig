const std = @import("std");

const Deferred = @import("deferred.zig");
const key_event = @import("../../event.zig").key;
const keycode_module = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");
const mouse_event = @import("../../event.zig").mouse;
const position_module = @import("../../position.zig");
const remote = @import("../../remote.zig");
const response_module = @import("../../response.zig");
const RuntimeType = @import("../../runtime.zig").RuntimeType;
const Windows = @import("../windows.zig");

const assert = std.debug.assert;

const BindOptions = remote.BindOptions;
const Blocked = remote.Blocked;
const ButtonAction = remote.ButtonAction;
const CapacityError = remote.CapacityError;
const Key = key_event.Key;
const KeyAction = remote.KeyAction;
const Keycode = keycode_module.Keycode;
const MouseEvent = mouse_event.MouseEvent;
const Pattern = remote.Pattern;
const PlatformError = remote.PlatformError;
const Position = position_module.Position;
const RequestError = remote.RequestError;
const Response = response_module.Response;
const Scroll = remote.Scroll;

connected: bool = false,
generation: u32 = 0,
id_next: u32 = 1,
registrations: [remote.binding_count_max]?Registration = @splat(null),
filter: ?Filter = null,
release: ?Release = null,
runtime: Runtime = undefined,
keyboard: Keyboard = undefined,
mouse: Mouse = undefined,

const RemoteClient = @This();

pub const NotifyCallback = *const fn (context: *anyopaque, key: ?*const Key) void;
pub const FilterCallback = *const fn (context: *anyopaque, key: *const Key) Response;
pub const ReleaseCallback = *const fn (context: *anyopaque) void;

const Runtime = RuntimeType(Windows);

const Keyboard = Runtime.KeyboardType(.{
    .binding_count_max = remote.binding_count_max,
    .chord_count_max = 32,
    .sequence_count_max = 8,
});

const Mouse = Runtime.MouseType(.{});

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
    client: *RemoteClient,

    fn notify(registration: *const Registration, key: ?*const Key) void {
        if (key) |value| assert(value.is_valid());
        if (registration.kind == .key) assert(key != null);
        if (registration.kind != .key) assert(key == null);

        const client = registration.client;

        client.runtime.platform.deferred.push(.{
            .run = deliver_notify,
            .owner = client,
            .generation = client.generation,
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

pub fn is_connected(client: *const RemoteClient) bool {
    return client.connected;
}

pub fn connect(client: *RemoteClient) PlatformError!void {
    assert(!client.is_connected());

    client.runtime.init(.{ .mode = .grab }) catch return error.ConnectFailed;
    errdefer client.runtime.deinit();

    client.keyboard.init(&client.runtime, .{}) catch return error.ConnectFailed;
    errdefer client.keyboard.deinit();

    client.mouse.init(&client.runtime, .{});
    errdefer client.mouse.deinit();

    client.keyboard.start() catch return error.ConnectFailed;
    errdefer client.keyboard.stop();

    client.mouse.start() catch return error.ConnectFailed;

    client.runtime.set_release_callback(RemoteClient, client, on_released);

    client.connected = true;
    client.generation +%= 1;

    assert(client.is_connected());
    assert(client.runtime.mode() == .grab);
}

pub fn disconnect(client: *RemoteClient) void {
    if (!client.connected) return;

    client.clear_bindings();
    client.runtime.clear_release_callback();
    client.keyboard.deinit();
    client.mouse.deinit();
    client.runtime.deinit();

    const generation = client.generation;

    client.* = .{ .generation = generation };

    assert(!client.is_connected());
}

pub fn poll(client: *RemoteClient, timeout_ms: u32) void {
    assert(timeout_ms <= std.math.maxInt(i32));

    if (!client.connected) return;

    _ = client.runtime.poll(timeout_ms);
}

pub fn bind_key(
    client: *RemoteClient,
    key: Keycode,
    modifiers: modifier.Set,
    options: BindOptions,
    callback: NotifyCallback,
    context: *anyopaque,
) (CapacityError || PlatformError || RequestError)!u32 {
    const registration = try client.allocate(.key, options, callback, context);

    registration.hook_id = client.keyboard.registry.register(
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
    client: *RemoteClient,
    keys: []const Keycode,
    options: BindOptions,
    callback: NotifyCallback,
    context: *anyopaque,
) (CapacityError || PlatformError || RequestError)!u32 {
    assert(keys.len >= 2);
    assert(keys.len <= remote.chord_keys_max);

    const registration = try client.allocate(.chord, options, callback, context);

    registration.hook_id = client.keyboard.chord_registry.register(
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
    client: *RemoteClient,
    text: []const u8,
    options: BindOptions,
    callback: NotifyCallback,
    context: *anyopaque,
) (CapacityError || PlatformError || RequestError)!u32 {
    assert(text.len >= 1);
    assert(text.len <= remote.sequence_bytes_max);

    const registration = try client.allocate(.sequence, options, callback, context);

    registration.hook_id = client.keyboard.sequence_registry.register(
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

pub fn unbind(client: *RemoteClient, id: u32) (PlatformError || RequestError)!void {
    assert(id >= 1);

    if (!client.connected) return error.ClientDisconnected;

    for (&client.registrations) |*slot| {
        if (slot.*) |*registration| {
            if (registration.id != id) continue;

            client.release_registration(registration);
            slot.* = null;

            return;
        }
    }

    return error.HandleUnknown;
}

pub fn set_blocked(client: *RemoteClient, blocked: Blocked) (PlatformError || RequestError)!void {
    if (!client.connected) return error.ClientDisconnected;

    client.runtime.platform.keyboard.reinstall();
    client.runtime.platform.mouse.reinstall();

    if (blocked.keyboard) client.keyboard.block() else client.keyboard.unblock();
    if (blocked.mouse) client.mouse.block() else client.mouse.unblock();
}

pub fn set_filter(
    client: *RemoteClient,
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

    client.keyboard.set_key_callback(RemoteClient, client, on_filter);
}

pub fn set_release_callback(
    client: *RemoteClient,
    callback: ReleaseCallback,
    context: *anyopaque,
) void {
    client.release = .{ .callback = callback, .context = context };

    assert(client.release != null);
}

pub fn simulate_key(
    client: *RemoteClient,
    key: Keycode,
    action: KeyAction,
) (PlatformError || RequestError)!void {
    if (!client.connected) return error.ClientDisconnected;

    const backend = &client.runtime.platform;

    const sent = switch (action) {
        .down => backend.key_down(key),
        .up => backend.key_up(key),
        .press => backend.key_press(key),
        .suppress => backend.key_suppress(key),
        .dummy => backend.key_dummy(),
    };

    if (!sent) return error.SendFailed;
}

pub fn simulate_combination(
    client: *RemoteClient,
    modifiers: modifier.Set,
    key: Keycode,
) (PlatformError || RequestError)!void {
    if (!client.connected) return error.ClientDisconnected;
    if (!client.runtime.platform.key_combination(&modifiers, key)) return error.SendFailed;
}

pub fn simulate_text(
    client: *RemoteClient,
    text: []const u8,
    delay_ms: u16,
) (PlatformError || RequestError)!void {
    assert(text.len <= remote.text_bytes_max);
    assert(delay_ms <= remote.delay_ms_max);

    if (!client.connected) return error.ClientDisconnected;

    const backend = &client.runtime.platform;

    _ = backend.text_send_with_delay(text, delay_ms) catch |err| return switch (err) {
        error.DelayInvalid => error.DelayInvalid,
        error.SendFailed => error.SendFailed,
        error.TextInvalid => error.TextInvalid,
        error.TextTooLong => unreachable,
    };
}

pub fn simulate_button(
    client: *RemoteClient,
    button: MouseEvent.Button,
    action: ButtonAction,
) (PlatformError || RequestError)!void {
    if (!client.connected) return error.ClientDisconnected;

    const backend = &client.runtime.platform;

    const sent = switch (action) {
        .down => backend.mouse_button_down(button),
        .up => backend.mouse_button_up(button),
        .click => backend.mouse_click(button),
    };

    if (!sent) return error.SendFailed;
}

pub fn simulate_move(client: *RemoteClient, offset: Position) (PlatformError || RequestError)!void {
    if (!client.connected) return error.ClientDisconnected;
    if (!client.runtime.platform.mouse_move_relative(offset)) return error.SendFailed;
}

pub fn simulate_scroll(client: *RemoteClient, scroll: Scroll) (PlatformError || RequestError)!void {
    assert(remote.scroll_valid(scroll));

    if (!client.connected) return error.ClientDisconnected;

    const backend = &client.runtime.platform;

    if (!scroll_vertical(backend, scroll.vertical)) return error.SendFailed;
    if (!scroll_horizontal(backend, scroll.horizontal)) return error.SendFailed;
}

fn allocate(
    client: *RemoteClient,
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

fn find(client: *const RemoteClient, id: u32) ?*const Registration {
    assert(id >= 1);

    for (&client.registrations) |*slot| {
        if (slot.*) |*registration| {
            if (registration.id == id) return registration;
        }
    }

    return null;
}

fn forget(client: *RemoteClient, registration: *const Registration) void {
    for (&client.registrations) |*slot| {
        const current = slot.* orelse continue;

        if (current.id == registration.id) slot.* = null;
    }
}

fn clear_bindings(client: *RemoteClient) void {
    for (&client.registrations) |*slot| {
        if (slot.*) |*registration| client.release_registration(registration);

        slot.* = null;
    }
}

fn release_registration(client: *RemoteClient, registration: *const Registration) void {
    const id = registration.hook_id;

    switch (registration.kind) {
        .key => client.keyboard.registry.unregister(id) catch |err| switch (err) {
            error.BindingDuplicate, error.HandleUnknown => unreachable,
        },
        .chord => client.keyboard.chord_registry.unregister(id) catch |err| switch (err) {
            error.ChordInvalid, error.HandleUnknown, error.TimeoutInvalid => unreachable,
        },
        .sequence => client.keyboard.sequence_registry.unregister(id) catch |err| switch (err) {
            error.CharacterInvalid, error.HandleUnknown, error.SequenceEmpty => unreachable,
        },
    }
}

fn on_released(client: *RemoteClient) void {
    const handler = client.release orelse return;

    if (!client.runtime.platform.loop.is_loop_thread()) {
        handler.callback(handler.context);

        return;
    }

    client.runtime.platform.deferred.push(.{
        .run = deliver_release,
        .owner = client,
        .generation = client.generation,
    });
}

fn deliver_notify(entry: *const Deferred.Entry) void {
    const client = live_client(entry) orelse return;
    const registration = client.find(entry.id) orelse return;
    const key = if (entry.key) |*value| value else null;

    registration.callback(registration.context, key);
}

fn deliver_release(entry: *const Deferred.Entry) void {
    const client = live_client(entry) orelse return;
    const handler = client.release orelse return;

    handler.callback(handler.context);
}

fn live_client(entry: *const Deferred.Entry) ?*RemoteClient {
    const client: *RemoteClient = @ptrCast(@alignCast(entry.owner));

    if (!client.connected) return null;
    if (client.generation != entry.generation) return null;
    return client;
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

fn on_filter(client: *RemoteClient, key: *const Key) Response {
    const filter = client.filter orelse return .pass;

    for (filter.patterns[0..filter.count]) |*pattern| {
        if (remote.pattern_matches(pattern, key)) return filter.callback(filter.context, key);
    }

    return .pass;
}

fn scroll_vertical(backend: *Windows, amount: i32) bool {
    if (amount == 0) return true;

    const clicks: u32 = @intCast(@abs(amount));

    if (amount > 0) return backend.mouse_scroll_up(clicks);
    return backend.mouse_scroll_down(clicks);
}

fn scroll_horizontal(backend: *Windows, amount: i32) bool {
    if (amount == 0) return true;

    const clicks: u32 = @intCast(@abs(amount));

    if (amount > 0) return backend.mouse_scroll_right(clicks);
    return backend.mouse_scroll_left(clicks);
}
