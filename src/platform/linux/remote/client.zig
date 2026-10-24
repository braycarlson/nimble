const std = @import("std");

const key_event = @import("../../../event/key.zig");
const keycode_mod = @import("../../../keycode.zig");
const modifier = @import("../../../modifier.zig");
const mouse_event = @import("../../../event/mouse.zig");
const position_module = @import("../../../position.zig");
const protocol = @import("protocol.zig");
const remote = @import("../../../remote.zig");
const response_mod = @import("../../../response.zig");
const time = @import("../time.zig");

const assert = std.debug.assert;
const linux = std.os.linux;
const log = std.log.scoped(.nimble_remote);
const posix = std.posix;

const BindOptions = remote.Client.BindOptions;
const Blocked = remote.Client.Blocked;
const ButtonAction = remote.Client.ButtonAction;
const Key = key_event.Key;
const KeyAction = remote.Client.KeyAction;
const Keycode = keycode_mod.Keycode;
const MouseEvent = mouse_event.MouseEvent;
const Pattern = remote.Client.Pattern;
const Position = position_module.Position;
const Response = response_mod.Response;
const Scroll = remote.Client.Scroll;

const connect_timeout_ms: i32 = 2000;
const connect_retry_max: u8 = 50;
const connect_retry_delay_ms: u32 = 100;
const receive_bytes_max: u16 = protocol.payload_bytes_max + @sizeOf(protocol.Header);

const CapacityError = remote.CapacityError;
const PlatformError = remote.PlatformError;
const RequestError = remote.RequestError;

pub const NotifyCallback = *const fn (context: *anyopaque, key: ?*const Key) void;
pub const FilterCallback = *const fn (context: *anyopaque, key: *const Key) Response;
pub const ReleaseCallback = *const fn (context: *anyopaque) void;

const Registration = struct {
    id: u32,
    callback: NotifyCallback,
    context: *anyopaque,
};

const Allocation = struct {
    slot: u16,
    id: u32,
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
    fd: posix.fd_t = -1,
    registrations: [remote.binding_count_max]?Registration = @splat(null),
    id_next: u32 = 1,
    filter: ?Filter = null,
    release: ?Release = null,
    running: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,

    pub fn is_connected(client: *const Client) bool {
        return client.fd >= 0;
    }

    pub fn connect(client: *Client) PlatformError!void {
        assert(!client.is_connected());
        assert(client.thread == null);

        var buffer: [protocol.path_bytes_max]u8 = @splat(0);
        const path = protocol.socket_path(&buffer) orelse return error.ConnectFailed;
        const fd = try connect_socket(path);
        errdefer _ = linux.close(fd);

        client.fd = fd;
        errdefer client.fd = -1;

        try client.handshake();

        client.running.store(true, .seq_cst);

        client.thread = std.Thread.spawn(.{}, pump, .{client}) catch {
            client.running.store(false, .seq_cst);

            return error.ConnectFailed;
        };

        assert(client.is_connected());
        assert(client.thread != null);
    }

    fn connect_socket(path: [:0]const u8) PlatformError!posix.fd_t {
        const server = @import("server.zig");

        var address = server.unix_address(path) orelse return error.ConnectFailed;
        const length = server.unix_address_length(path);

        var attempt: u8 = 0;

        while (attempt < connect_retry_max) : (attempt += 1) {
            const created = linux.socket(
                linux.AF.UNIX,
                linux.SOCK.SEQPACKET | linux.SOCK.CLOEXEC,
                0,
            );

            if (linux.errno(created) != .SUCCESS) {
                return error.ConnectFailed;
            }

            const fd: posix.fd_t = @intCast(created);
            const connected = linux.connect(fd, @ptrCast(&address), length);

            if (linux.errno(connected) == .SUCCESS) {
                return fd;
            }

            _ = linux.close(fd);

            time.sleep_ms(connect_retry_delay_ms);
        }

        assert(attempt == connect_retry_max);

        return error.ConnectFailed;
    }

    pub fn disconnect(client: *Client) void {
        client.running.store(false, .seq_cst);

        if (client.fd >= 0) {
            _ = linux.shutdown(client.fd, linux.SHUT.RDWR);
        }

        if (client.thread) |thread| {
            thread.join();

            client.thread = null;
        }

        if (client.fd >= 0) {
            _ = linux.close(client.fd);

            client.fd = -1;
        }

        client.registrations = @splat(null);
        client.filter = null;

        assert(!client.is_connected());
        assert(client.thread == null);
    }

    fn handshake(client: *Client) PlatformError!void {
        const hello = protocol.Hello{ .version = protocol.version };

        client.transmit(.hello, protocol.Hello, &hello) catch return error.ConnectFailed;

        var fds = [_]linux.pollfd{
            .{ .fd = client.fd, .events = linux.POLL.IN, .revents = 0 },
        };

        const ready = linux.poll(&fds, 1, connect_timeout_ms);
        if (linux.errno(ready) != .SUCCESS) return error.ConnectFailed;
        if (fds[0].revents & linux.POLL.IN == 0) return error.ConnectFailed;

        var buffer: [receive_bytes_max]u8 = undefined;
        const received = linux.recvfrom(client.fd, &buffer, buffer.len, 0, null, null);

        if (linux.errno(received) != .SUCCESS) {
            return error.ConnectFailed;
        }

        const size: usize = @intCast(received);

        if (size < @sizeOf(protocol.Header)) {
            return error.ConnectFailed;
        }

        var header: protocol.Header = undefined;

        @memcpy(std.mem.asBytes(&header), buffer[0..@sizeOf(protocol.Header)]);

        if (header.tag != @backingInt(protocol.Tag.hello_ok)) {
            return error.ConnectFailed;
        }
    }

    pub fn bind_key(
        client: *Client,
        key: Keycode,
        modifiers: modifier.Set,
        options: BindOptions,
        callback: NotifyCallback,
        context: *anyopaque,
    ) (CapacityError || PlatformError || RequestError)!u32 {
        const allocation = try client.allocate(callback, context);

        const request = protocol.BindKey{
            .id = allocation.id,
            .key = @backingInt(key),
            .modifiers = modifiers.flags,
            .consume = @intFromBool(options.consume),
            .exempt = @intFromBool(options.exempt),
        };

        client.transmit(.bind_key, protocol.BindKey, &request) catch |err| {
            client.registrations[allocation.slot] = null;

            return err;
        };

        return allocation.id;
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

        const allocation = try client.allocate(callback, context);

        var request = protocol.BindChord{
            .id = allocation.id,
            .count = @intCast(keys.len),
            .consume = @intFromBool(options.consume),
            .exempt = @intFromBool(options.exempt),
            .keys = @splat(.{}),
        };

        for (keys, 0..) |value, position| {
            request.keys[position] = .{ .key = @backingInt(value), .match_any_modifiers = 1 };
        }

        client.transmit(.bind_chord, protocol.BindChord, &request) catch |err| {
            client.registrations[allocation.slot] = null;

            return err;
        };

        return allocation.id;
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

        const allocation = try client.allocate(callback, context);

        var request = protocol.BindSequence{
            .id = allocation.id,
            .count = @intCast(text.len),
            .consume = @intFromBool(options.consume),
            .exempt = @intFromBool(options.exempt),
            .keys = @splat(.{}),
        };

        for (text, 0..) |character, position| {
            request.keys[position] = .{ .key = character, .match_any_modifiers = 1 };
        }

        client.transmit(.bind_sequence, protocol.BindSequence, &request) catch |err| {
            client.registrations[allocation.slot] = null;

            return err;
        };

        return allocation.id;
    }

    pub fn unbind(client: *Client, id: u32) (PlatformError || RequestError)!void {
        assert(id >= 1);

        if (!client.is_connected()) return error.ClientDisconnected;

        const slot = client.find(id) orelse return error.HandleUnknown;

        client.registrations[slot] = null;

        const request = protocol.Unbind{ .id = id };

        try client.transmit(.unbind, protocol.Unbind, &request);
    }

    pub fn set_blocked(client: *Client, blocked: Blocked) (PlatformError || RequestError)!void {
        const request = protocol.SetBlocked{
            .keyboard = @intFromBool(blocked.keyboard),
            .mouse = @intFromBool(blocked.mouse),
        };

        try client.transmit(.set_blocked, protocol.SetBlocked, &request);
    }

    pub fn set_filter(
        client: *Client,
        patterns: []const Pattern,
        callback: FilterCallback,
        context: *anyopaque,
    ) (PlatformError || RequestError)!void {
        assert(patterns.len <= remote.filter_patterns_max);

        if (!client.is_connected()) return error.ClientDisconnected;

        var request = protocol.ClaimFilter{
            .count = @intCast(patterns.len),
            .patterns = @splat(.{}),
        };

        for (patterns, 0..) |*pattern, position| {
            request.patterns[position] = protocol.pattern_from(pattern);
        }

        client.filter = .{ .callback = callback, .context = context };

        try client.transmit(.claim_filter, protocol.ClaimFilter, &request);
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
        const request = protocol.SimulateKey{
            .key = @backingInt(key),
            .action = @backingInt(action),
        };

        try client.transmit(.simulate_key, protocol.SimulateKey, &request);
    }

    pub fn simulate_combination(
        client: *Client,
        modifiers: modifier.Set,
        key: Keycode,
    ) (PlatformError || RequestError)!void {
        const request = protocol.SimulateCombination{
            .key = @backingInt(key),
            .modifiers = modifiers.flags,
        };

        try client.transmit(.simulate_combination, protocol.SimulateCombination, &request);
    }

    pub fn simulate_text(
        client: *Client,
        text: []const u8,
        delay_ms: u16,
    ) (PlatformError || RequestError)!void {
        assert(text.len <= remote.text_bytes_max);
        assert(delay_ms <= remote.delay_ms_max);

        var request = protocol.SimulateText{
            .length = @intCast(text.len),
            .delay_ms = delay_ms,
            .bytes = @splat(0),
        };

        @memcpy(request.bytes[0..text.len], text);

        try client.transmit(.simulate_text, protocol.SimulateText, &request);
    }

    pub fn simulate_button(
        client: *Client,
        button: MouseEvent.Button,
        action: ButtonAction,
    ) (PlatformError || RequestError)!void {
        const request = protocol.SimulateButton{
            .button = @backingInt(button),
            .down = @intFromBool(action == .down),
            .click = @intFromBool(action == .click),
        };

        try client.transmit(.simulate_button, protocol.SimulateButton, &request);
    }

    pub fn simulate_move(client: *Client, offset: Position) (PlatformError || RequestError)!void {
        const request = protocol.SimulateMove{ .delta_x = offset.x, .delta_y = offset.y };

        try client.transmit(.simulate_move, protocol.SimulateMove, &request);
    }

    pub fn simulate_scroll(client: *Client, scroll: Scroll) (PlatformError || RequestError)!void {
        assert(remote.scroll_valid(scroll));

        const request = protocol.SimulateScroll{
            .vertical = scroll.vertical,
            .horizontal = scroll.horizontal,
        };

        try client.transmit(.simulate_scroll, protocol.SimulateScroll, &request);
    }

    fn allocate(
        client: *Client,
        callback: NotifyCallback,
        context: *anyopaque,
    ) (CapacityError || RequestError)!Allocation {
        if (!client.is_connected()) {
            return error.ClientDisconnected;
        }

        for (&client.registrations, 0..) |*registration, slot| {
            if (registration.* != null) continue;

            const id = client.id_next;

            registration.* = .{ .id = id, .callback = callback, .context = context };
            client.id_next += 1;

            assert(id >= 1);

            return .{ .slot = @intCast(slot), .id = id };
        }

        return error.RegistrationsExhausted;
    }

    fn find(client: *const Client, id: u32) ?u16 {
        assert(id >= 1);

        for (client.registrations, 0..) |maybe, slot| {
            const registration = maybe orelse continue;
            if (registration.id == id) return @intCast(slot);
        }

        return null;
    }

    fn transmit(
        client: *Client,
        tag: protocol.Tag,
        comptime Payload: type,
        payload: *const Payload,
    ) (PlatformError || RequestError)!void {
        if (!client.is_connected()) {
            return error.ClientDisconnected;
        }

        var buffer: [receive_bytes_max]u8 = undefined;
        const header = protocol.Header.of(tag, Payload);

        @memcpy(buffer[0..@sizeOf(protocol.Header)], std.mem.asBytes(&header));

        @memcpy(
            buffer[@sizeOf(protocol.Header)..][0..@sizeOf(Payload)],
            std.mem.asBytes(payload),
        );

        const total = @sizeOf(protocol.Header) + @sizeOf(Payload);
        const sent = linux.sendto(client.fd, &buffer, total, linux.MSG.NOSIGNAL, null, 0);

        if (linux.errno(sent) != .SUCCESS) {
            return error.SendFailed;
        }
    }

    fn pump(client: *Client) void {
        while (client.running.load(.seq_cst)) {
            assert(client.fd >= 0);

            var buffer: [receive_bytes_max]u8 = undefined;
            const received = linux.recvfrom(client.fd, &buffer, buffer.len, 0, null, null);

            if (linux.errno(received) != .SUCCESS) {
                break;
            }

            const size: usize = @intCast(received);

            if (size == 0) {
                break;
            }

            client.handle_message(buffer[0..size]);
        }

        log.info("daemon connection closed", .{});
    }

    fn handle_message(client: *Client, bytes: []const u8) void {
        if (bytes.len < @sizeOf(protocol.Header)) {
            return;
        }

        var header: protocol.Header = undefined;

        @memcpy(std.mem.asBytes(&header), bytes[0..@sizeOf(protocol.Header)]);

        const payload = bytes[@sizeOf(protocol.Header)..];

        if (payload.len != header.size) {
            return;
        }

        const tag = std.enums.fromInt(protocol.Tag, header.tag) orelse return;

        switch (tag) {
            .notify => client.on_notify(payload),
            .key_query => client.on_key_query(payload),
            .released => client.on_released(),

            else => {},
        }
    }

    fn on_notify(client: *Client, payload: []const u8) void {
        if (payload.len != @sizeOf(protocol.Notify)) {
            return;
        }

        var notify: protocol.Notify = undefined;

        @memcpy(std.mem.asBytes(&notify), payload);

        for (client.registrations) |maybe| {
            const registration = maybe orelse continue;
            if (registration.id != notify.id) continue;

            const value = protocol.keycode_of(notify.key) orelse {
                registration.callback(registration.context, null);

                return;
            };

            const key = Key{
                .value = value,
                .down = notify.down != 0,
                .modifiers = protocol.modifiers_of(notify.modifiers) orelse .{},
                .time_ms = notify.time_ms,
            };

            registration.callback(registration.context, &key);

            return;
        }
    }

    fn on_key_query(client: *Client, payload: []const u8) void {
        if (payload.len != @sizeOf(protocol.KeyQuery)) {
            return;
        }

        var query: protocol.KeyQuery = undefined;

        @memcpy(std.mem.asBytes(&query), payload);

        var response = Response.pass;

        if (client.filter) |filter| {
            if (protocol.keycode_of(query.key)) |value| {
                const key = Key{
                    .value = value,
                    .down = query.down != 0,
                    .injected = query.injected != 0,
                    .modifiers = protocol.modifiers_of(query.modifiers) orelse .{},
                };

                response = filter.callback(filter.context, &key);
            }
        }

        const verdict = protocol.Verdict{
            .serial = query.serial,
            .response = @backingInt(response),
        };

        client.transmit(.verdict, protocol.Verdict, &verdict) catch return;
    }

    fn on_released(client: *Client) void {
        const release = client.release orelse return;

        release.callback(release.context);
    }
};

const testing = std.testing;

test "a fresh client is disconnected and rejects binds" {
    var client = Client{};
    var context: u8 = 0;

    try testing.expect(!client.is_connected());

    const result = client.bind_key(.a, .{}, .{}, ignore_notify, &context);

    try testing.expectError(error.ClientDisconnected, result);
    try testing.expectError(error.ClientDisconnected, client.unbind(1));
    try testing.expectError(error.ClientDisconnected, client.simulate_move(.zero));
}

test "disconnecting an unconnected client is inert" {
    var client = Client{};

    client.disconnect();

    try testing.expect(!client.is_connected());
    try testing.expect(client.thread == null);
}

fn ignore_notify(_: *anyopaque, _: ?*const Key) void {}
