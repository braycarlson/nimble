const std = @import("std");

const key_event = @import("../../event.zig").key;
const keycode_module = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");
const mouse_event = @import("../../event.zig").mouse;
const position_module = @import("../../position.zig");
const record_module = @import("record.zig");
const remote = @import("../../remote.zig");
const response_module = @import("../../response.zig");

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
const RecordType = record_module.RecordType;
const RequestError = remote.RequestError;
const Response = response_module.Response;
const Scroll = remote.Scroll;

connected: bool = false,
registrations: [remote.binding_count_max]?Registration = @splat(null),
id_next: u32 = 1,
blocked: Blocked = .{},
filter: ?Filter = null,
release: ?Release = null,
record: Record = .{},

const RemoteClient = @This();

pub const NotifyCallback = *const fn (context: *anyopaque, key: ?*const Key) void;
pub const FilterCallback = *const fn (context: *anyopaque, key: *const Key) Response;
pub const ReleaseCallback = *const fn (context: *anyopaque) void;

const Record = RecordType(record_count_max);

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

const record_count_max: u16 = 64;

pub fn is_connected(client: *const RemoteClient) bool {
    return client.connected;
}

pub fn connect(client: *RemoteClient) PlatformError!void {
    assert(!client.connected);

    client.connected = true;

    assert(client.is_connected());
}

pub fn disconnect(client: *RemoteClient) void {
    client.* = .{};

    assert(!client.connected);
}

pub fn poll(client: *RemoteClient, timeout_ms: u32) void {
    assert(timeout_ms <= std.math.maxInt(i32));
    assert(client.record.len() <= record_count_max);
}

pub fn bind_key(
    client: *RemoteClient,
    key: Keycode,
    modifiers: modifier.Set,
    options: BindOptions,
    callback: NotifyCallback,
    context: *anyopaque,
) (CapacityError || PlatformError || RequestError)!u32 {
    assert(modifiers.flags <= modifier.flag_all);

    _ = key;
    _ = options;

    return client.allocate(callback, context);
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

    _ = options;

    return client.allocate(callback, context);
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

    _ = options;

    return client.allocate(callback, context);
}

pub fn unbind(client: *RemoteClient, id: u32) (PlatformError || RequestError)!void {
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

pub fn set_blocked(client: *RemoteClient, blocked: Blocked) (PlatformError || RequestError)!void {
    if (!client.connected) return error.ClientDisconnected;

    client.blocked = blocked;
}

pub fn set_filter(
    client: *RemoteClient,
    patterns: []const Pattern,
    callback: FilterCallback,
    context: *anyopaque,
) (PlatformError || RequestError)!void {
    assert(patterns.len <= remote.filter_patterns_max);

    if (!client.connected) return error.ClientDisconnected;

    client.filter = .{ .callback = callback, .context = context };
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

    const kind: record_module.Kind = switch (action) {
        .down => .key_down,
        .up => .key_up,
        .press => .key_press,
        .suppress => .key_up,
        .dummy => .key_dummy,
    };

    client.record.push(.{ .kind = kind, .code = key, .down = action == .down });
}

pub fn simulate_combination(
    client: *RemoteClient,
    modifiers: modifier.Set,
    key: Keycode,
) (PlatformError || RequestError)!void {
    assert(modifiers.flags <= modifier.flag_all);

    if (!client.connected) return error.ClientDisconnected;

    client.record.push(.{ .kind = .key_combination, .code = key, .modifiers = modifiers });
}

pub fn simulate_text(
    client: *RemoteClient,
    text: []const u8,
    delay_ms: u16,
) (PlatformError || RequestError)!void {
    assert(text.len <= remote.text_bytes_max);
    assert(delay_ms <= remote.delay_ms_max);

    if (!client.connected) return error.ClientDisconnected;

    client.record.push_text(.text_send, text);
}

pub fn simulate_button(
    client: *RemoteClient,
    button: MouseEvent.Button,
    action: ButtonAction,
) (PlatformError || RequestError)!void {
    assert(button.is_valid());

    if (!client.connected) return error.ClientDisconnected;

    const code: u8 = @backingInt(button);

    switch (action) {
        .down => client.record.push(.{ .kind = .mouse_down, .button = code, .down = true }),
        .up => client.record.push(.{ .kind = .mouse_up, .button = code }),
        .click => {
            client.record.push(.{ .kind = .mouse_down, .button = code, .down = true });
            client.record.push(.{ .kind = .mouse_up, .button = code });
        },
    }
}

pub fn simulate_move(client: *RemoteClient, offset: Position) (PlatformError || RequestError)!void {
    if (!client.connected) return error.ClientDisconnected;

    client.record.push(.{ .kind = .mouse_move, .x = offset.x, .y = offset.y });
}

pub fn simulate_scroll(client: *RemoteClient, scroll: Scroll) (PlatformError || RequestError)!void {
    assert(remote.scroll_valid(scroll));

    if (!client.connected) return error.ClientDisconnected;

    client.record.push(.{
        .kind = .mouse_scroll,
        .amount = scroll.vertical,
        .x = scroll.horizontal,
    });
}

fn allocate(
    client: *RemoteClient,
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

const testing = std.testing;

test "the fake client records the synthesis it was asked for" {
    var client = RemoteClient{};

    try testing.expectError(error.ClientDisconnected, client.simulate_move(.zero));

    try client.connect();
    try client.simulate_move(.{ .x = 4, .y = 5 });

    try testing.expectEqual(@as(u16, 1), client.record.count_of(.mouse_move));

    client.disconnect();

    try testing.expect(!client.is_connected());
}

test "the fake client hands out and forgets registrations" {
    var client = RemoteClient{};
    var context: u8 = 0;

    try client.connect();
    defer client.disconnect();

    const id = try client.bind_key(.a, .{}, .{}, ignore_notify, &context);

    try client.unbind(id);
    try testing.expectError(error.HandleUnknown, client.unbind(id));
}

fn ignore_notify(_: *anyopaque, _: ?*const Key) void {}
