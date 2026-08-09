const std = @import("std");

const key_event = @import("../../../event/key.zig");
const keycode_mod = @import("../../../keycode.zig");
const modifier = @import("../../../modifier.zig");
const pattern_mod = @import("../../../builder/pattern.zig");
const protocol = @import("protocol.zig");
const response_mod = @import("../../../response.zig");
const time = @import("../time.zig");

const assert = std.debug.assert;
const linux = std.os.linux;
const log = std.log.scoped(.nimble_remote);
const posix = std.posix;

const Key = key_event.Key;
const Keycode = keycode_mod.Keycode;
const Response = response_mod.Response;

pub const binding_count_max: u16 = 64;
pub const connect_timeout_ms: i32 = 2000;
pub const connect_retry_max: u8 = 50;
pub const connect_retry_delay_ms: u32 = 100;
pub const receive_bytes_max: u16 = protocol.payload_bytes_max + @sizeOf(protocol.Header);

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

const Registration = struct {
    used: bool = false,
    id: u32 = 0,
    callback: ?NotifyCallback = null,
    context: ?*anyopaque = null,
};

pub const Client = struct {
    fd: posix.fd_t = -1,
    registrations: [binding_count_max]Registration = @splat(.{}),
    id_next: u32 = 1,
    filter_callback: ?FilterCallback = null,
    filter_context: ?*anyopaque = null,
    release_callback: ?ReleaseCallback = null,
    release_context: ?*anyopaque = null,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,

    pub fn is_connected(client: *const Client) bool {
        return client.fd >= 0;
    }

    pub fn connect(client: *Client) Error!void {
        assert(!client.is_connected());
        assert(client.thread == null);

        var buffer: [protocol.path_bytes_max]u8 = @splat(0);
        const path = protocol.socket_path(&buffer) orelse return Error.ConnectFailed;

        const fd = try connect_socket(path);
        errdefer _ = linux.close(fd);

        client.fd = fd;
        errdefer client.fd = -1;

        try client.handshake();

        client.running.store(true, .seq_cst);

        client.thread = std.Thread.spawn(.{}, pump, .{client}) catch {
            client.running.store(false, .seq_cst);

            return Error.ConnectFailed;
        };

        assert(client.is_connected());
        assert(client.thread != null);
    }

    fn connect_socket(path: [:0]const u8) Error!posix.fd_t {
        const server = @import("server.zig");

        var address = server.unix_address(path) orelse return Error.ConnectFailed;
        const length = server.unix_address_length(path);

        var attempt: u8 = 0;

        while (attempt < connect_retry_max) : (attempt += 1) {
            const created = linux.socket(
                linux.AF.UNIX,
                linux.SOCK.SEQPACKET | linux.SOCK.CLOEXEC,
                0,
            );

            if (posix.errno(created) != .SUCCESS) {
                return Error.ConnectFailed;
            }

            const fd: posix.fd_t = @intCast(created);
            const connected = linux.connect(fd, @ptrCast(&address), length);

            if (posix.errno(connected) == .SUCCESS) {
                return fd;
            }

            _ = linux.close(fd);

            time.sleep_ms(connect_retry_delay_ms);
        }

        assert(attempt == connect_retry_max);

        return Error.ConnectFailed;
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

        client.registrations = @splat(.{});

        assert(!client.is_connected());
        assert(client.thread == null);
    }

    fn handshake(client: *Client) Error!void {
        const hello = protocol.Hello{ .version = protocol.version };

        client.transmit(.hello, protocol.Hello, &hello) catch return Error.ConnectFailed;

        var fds = [_]linux.pollfd{
            .{ .fd = client.fd, .events = linux.POLL.IN, .revents = 0 },
        };

        const ready = linux.poll(&fds, 1, connect_timeout_ms);

        if (posix.errno(ready) != .SUCCESS or fds[0].revents & linux.POLL.IN == 0) {
            return Error.ConnectFailed;
        }

        var buffer: [receive_bytes_max]u8 = undefined;
        const received = linux.recvfrom(client.fd, &buffer, buffer.len, 0, null, null);

        if (posix.errno(received) != .SUCCESS) {
            return Error.ConnectFailed;
        }

        const size: usize = @intCast(received);

        if (size < @sizeOf(protocol.Header)) {
            return Error.ConnectFailed;
        }

        var header: protocol.Header = undefined;

        @memcpy(std.mem.asBytes(&header), buffer[0..@sizeOf(protocol.Header)]);

        if (header.tag != @intFromEnum(protocol.Tag.hello_ok)) {
            return Error.ConnectFailed;
        }
    }

    pub fn bind_key(
        client: *Client,
        key: Keycode,
        modifiers: modifier.Set,
        options: BindOptions,
        callback: ?NotifyCallback,
        context: ?*anyopaque,
    ) Error!u32 {
        const slot = try client.allocate(callback, context);
        const id = client.registrations[slot].id;

        const request = protocol.BindKey{
            .id = id,
            .key = @intFromEnum(key),
            .modifiers = @intCast(modifiers.flags),
            .consume = @intFromBool(options.consume),
            .exempt = @intFromBool(options.exempt),
        };

        client.transmit(.bind_key, protocol.BindKey, &request) catch {
            client.registrations[slot] = .{};

            return Error.BindFailed;
        };

        return id;
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
        return client.bind_multi(.bind_chord, keys, options, callback, context);
    }

    pub fn bind_sequence(
        client: *Client,
        characters: []const u8,
        options: BindOptions,
        callback: ?NotifyCallback,
        context: ?*anyopaque,
    ) Error!u32 {
        if (characters.len == 0 or characters.len > protocol.sequence_keys_max) {
            return Error.BindFailed;
        }

        const slot = try client.allocate(callback, context);
        const id = client.registrations[slot].id;

        var request = protocol.BindSequence{
            .id = id,
            .count = @intCast(characters.len),
            .consume = @intFromBool(options.consume),
            .exempt = @intFromBool(options.exempt),
            .keys = @splat(.{ .key = 0, .modifiers = 0, .match_any_modifiers = 0 }),
        };

        for (characters, 0..) |character, position| {
            request.keys[position] = .{
                .key = character,
                .modifiers = 0,
                .match_any_modifiers = 1,
            };
        }

        client.transmit(.bind_sequence, protocol.BindSequence, &request) catch {
            client.registrations[slot] = .{};

            return Error.BindFailed;
        };

        return id;
    }

    fn bind_multi(
        client: *Client,
        tag: protocol.Tag,
        keys: []const Keycode,
        options: BindOptions,
        callback: ?NotifyCallback,
        context: ?*anyopaque,
    ) Error!u32 {
        assert(tag == .bind_chord);

        if (keys.len == 0 or keys.len > protocol.chord_keys_max) {
            return Error.BindFailed;
        }

        const slot = try client.allocate(callback, context);
        const id = client.registrations[slot].id;

        var request = protocol.BindChord{
            .id = id,
            .count = @intCast(keys.len),
            .consume = @intFromBool(options.consume),
            .exempt = @intFromBool(options.exempt),
            .keys = @splat(.{ .key = 0, .modifiers = 0, .match_any_modifiers = 0 }),
        };

        for (keys, 0..) |value, position| {
            request.keys[position] = .{
                .key = @intFromEnum(value),
                .modifiers = 0,
                .match_any_modifiers = 1,
            };
        }

        client.transmit(tag, protocol.BindChord, &request) catch {
            client.registrations[slot] = .{};

            return Error.BindFailed;
        };

        return id;
    }

    pub fn unbind(client: *Client, id: u32) void {
        var slot: u16 = 0;

        while (slot < binding_count_max) : (slot += 1) {
            const registration = &client.registrations[slot];

            if (registration.used and registration.id == id) {
                registration.* = .{};

                break;
            }
        }

        const request = protocol.Unbind{ .id = id };

        client.transmit(.unbind, protocol.Unbind, &request) catch return;
    }

    pub fn set_blocked(client: *Client, keyboard: bool, mouse: bool) void {
        const request = protocol.SetBlocked{
            .keyboard = @intFromBool(keyboard),
            .mouse = @intFromBool(mouse),
        };

        client.transmit(.set_blocked, protocol.SetBlocked, &request) catch return;
    }

    pub fn set_filter(
        client: *Client,
        patterns: []const protocol.Pattern,
        callback: ?FilterCallback,
        context: ?*anyopaque,
    ) Error!void {
        if (patterns.len > protocol.filter_patterns_max) {
            return Error.BindFailed;
        }

        client.filter_callback = callback;
        client.filter_context = context;

        var request = protocol.ClaimFilter{
            .count = @intCast(patterns.len),
            .patterns = @splat(.{ .key = 0, .modifiers = 0, .match_any_modifiers = 0 }),
        };

        for (patterns, 0..) |pattern, position| {
            request.patterns[position] = pattern;
        }

        client.transmit(.claim_filter, protocol.ClaimFilter, &request) catch {
            return Error.BindFailed;
        };
    }

    pub fn set_release_callback(
        client: *Client,
        callback: ?ReleaseCallback,
        context: ?*anyopaque,
    ) void {
        client.release_callback = callback;
        client.release_context = context;
    }

    pub fn simulate_key(client: *Client, key: Keycode, action: protocol.KeyAction) void {
        const request = protocol.SimulateKey{
            .key = @intFromEnum(key),
            .action = @intFromEnum(action),
        };

        client.transmit(.simulate_key, protocol.SimulateKey, &request) catch return;
    }

    pub fn simulate_combination(client: *Client, modifiers: modifier.Set, key: Keycode) void {
        const request = protocol.SimulateCombination{
            .key = @intFromEnum(key),
            .modifiers = @intCast(modifiers.flags),
        };

        client.transmit(.simulate_combination, protocol.SimulateCombination, &request) catch {
            return;
        };
    }

    pub fn simulate_text(client: *Client, text: []const u8, delay_ms: u16) void {
        if (text.len > protocol.text_bytes_max) {
            return;
        }

        var request = protocol.SimulateText{
            .length = @intCast(text.len),
            .delay_ms = delay_ms,
            .bytes = @splat(0),
        };

        @memcpy(request.bytes[0..text.len], text);

        client.transmit(.simulate_text, protocol.SimulateText, &request) catch return;
    }

    pub fn simulate_button(client: *Client, button: u8, down: bool, click: bool) void {
        const request = protocol.SimulateButton{
            .button = button,
            .down = @intFromBool(down),
            .click = @intFromBool(click),
        };

        client.transmit(.simulate_button, protocol.SimulateButton, &request) catch return;
    }

    pub fn simulate_move(client: *Client, delta_x: i32, delta_y: i32) void {
        const request = protocol.SimulateMove{ .delta_x = delta_x, .delta_y = delta_y };

        client.transmit(.simulate_move, protocol.SimulateMove, &request) catch return;
    }

    pub fn simulate_scroll(client: *Client, vertical: i32, horizontal: i32) void {
        const request = protocol.SimulateScroll{
            .vertical = vertical,
            .horizontal = horizontal,
        };

        client.transmit(.simulate_scroll, protocol.SimulateScroll, &request) catch return;
    }

    fn allocate(client: *Client, callback: ?NotifyCallback, context: ?*anyopaque) Error!u16 {
        if (!client.is_connected()) {
            return Error.NotConnected;
        }

        var slot: u16 = 0;

        while (slot < binding_count_max) : (slot += 1) {
            if (!client.registrations[slot].used) {
                client.registrations[slot] = .{
                    .used = true,
                    .id = client.id_next,
                    .callback = callback,
                    .context = context,
                };

                client.id_next += 1;

                return slot;
            }
        }

        return Error.TableFull;
    }

    fn transmit(
        client: *Client,
        tag: protocol.Tag,
        comptime Payload: type,
        payload: *const Payload,
    ) !void {
        if (!client.is_connected()) {
            return Error.NotConnected;
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

        if (posix.errno(sent) != .SUCCESS) {
            return Error.NotConnected;
        }
    }

    fn pump(client: *Client) void {
        while (client.running.load(.seq_cst)) {
            var buffer: [receive_bytes_max]u8 = undefined;
            const received = linux.recvfrom(client.fd, &buffer, buffer.len, 0, null, null);

            if (posix.errno(received) != .SUCCESS) {
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

        var slot: u16 = 0;

        while (slot < binding_count_max) : (slot += 1) {
            const registration = &client.registrations[slot];

            if (!registration.used or registration.id != notify.id) {
                continue;
            }

            const callback = registration.callback orelse return;

            if (protocol.keycode_of(notify.key)) |value| {
                const key = Key{
                    .value = value,
                    .down = notify.down != 0,
                    .modifiers = protocol.modifiers_of(notify.modifiers) orelse .{},
                    .time_ms = notify.time_ms,
                };

                callback(registration.context, &key);
            } else {
                callback(registration.context, null);
            }

            return;
        }

        assert(slot == binding_count_max);
    }

    fn on_key_query(client: *Client, payload: []const u8) void {
        if (payload.len != @sizeOf(protocol.KeyQuery)) {
            return;
        }

        var query: protocol.KeyQuery = undefined;

        @memcpy(std.mem.asBytes(&query), payload);

        var response = Response.pass;

        if (client.filter_callback) |callback| {
            if (protocol.keycode_of(query.key)) |value| {
                const key = Key{
                    .value = value,
                    .down = query.down != 0,
                    .injected = query.injected != 0,
                    .modifiers = protocol.modifiers_of(query.modifiers) orelse .{},
                };

                response = callback(client.filter_context, &key);
            }
        }

        const verdict = protocol.Verdict{
            .serial = query.serial,
            .response = @intFromEnum(response),
        };

        client.transmit(.verdict, protocol.Verdict, &verdict) catch return;
    }

    fn on_released(client: *Client) void {
        const callback = client.release_callback orelse return;

        callback(client.release_context);
    }
};

const testing = std.testing;

test "a fresh client is disconnected and rejects binds" {
    var client = Client{};

    try testing.expect(!client.is_connected());
    try testing.expectError(Error.NotConnected, client.bind_key(.a, .{}, .{}, null, null));
}

test "disconnecting an unconnected client is inert" {
    var client = Client{};

    client.disconnect();

    try testing.expect(!client.is_connected());
    try testing.expect(client.thread == null);
}
