const std = @import("std");

const key_event = @import("../../../event/key.zig");
const protocol = @import("protocol.zig");
const response_mod = @import("../../../response.zig");
const simulate_key = @import("../simulate/key.zig");
const simulate_mouse = @import("../simulate/mouse.zig");
const simulate_text = @import("../simulate/text.zig");
const time = @import("../time.zig");

const assert = std.debug.assert;
const linux = std.os.linux;
const log = std.log.scoped(.nimbled);
const posix = std.posix;

const Key = key_event.Key;
const Response = response_mod.Response;

pub const client_count_max: u8 = 8;
pub const binding_count_max: u16 = 128;
pub const receive_bytes_max: u16 = protocol.payload_bytes_max + @sizeOf(protocol.Header);
pub const backlog = 4;
pub const poll_interval_ms: i32 = 100;

pub const query_idle: u32 = 0;
pub const query_pending: u32 = 1;
pub const query_answered: u32 = 2;

pub const Error = error{
    LockUnavailable,
    PathUnavailable,
    SocketFailed,
};

const BindingKind = enum(u8) {
    key,
    chord,
    sequence,
};

pub const Binding = struct {
    used: bool = false,
    client: u8 = 0,
    remote_id: u32 = 0,
    nimble_id: u32 = 0,
    kind: BindingKind = .key,
    consume: bool = false,
};

const Client = struct {
    fd: posix.fd_t = -1,
    ready: bool = false,
    blocked_keyboard: bool = false,
    blocked_mouse: bool = false,
    filter_count: u8 = 0,
    filter: [protocol.filter_patterns_max]protocol.Pattern = undefined,
    query_state: std.atomic.Value(u32) = std.atomic.Value(u32).init(query_idle),
    query_serial: u32 = 0,
    query_answer: u8 = 0,

    fn is_connected(client: *const Client) bool {
        return client.fd >= 0;
    }
};

comptime {
    assert(client_count_max > 0);
    assert(binding_count_max > client_count_max);
    assert(receive_bytes_max > @sizeOf(protocol.Header));
    assert(query_idle < query_pending);
    assert(query_pending < query_answered);
}

pub fn ServerType(comptime Keyboard: type, comptime Mouse: type) type {
    return struct {
        const Server = @This();

        keyboard: *Keyboard,
        mouse: *Mouse,
        listen_fd: posix.fd_t = -1,
        lock_fd: posix.fd_t = -1,
        clients: [client_count_max]Client = @splat(.{}),
        bindings: [binding_count_max]Binding = @splat(.{}),
        serial_next: u32 = 1,
        running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        thread: ?std.Thread = null,

        var instance_global: ?*Server = null;

        pub fn init(keyboard: *Keyboard, mouse: *Mouse) Server {
            return Server{ .keyboard = keyboard, .mouse = mouse };
        }

        pub fn start(server: *Server) Error!void {
            assert(server.thread == null);
            assert(instance_global == null);

            try server.acquire_lock();
            errdefer server.release_lock();

            try server.open_socket();
            errdefer server.close_socket();

            instance_global = server;

            server.keyboard.set_key_callback(filter_callback, server);
            server.running.store(true, .seq_cst);

            server.thread = std.Thread.spawn(.{}, serve, .{server}) catch {
                server.running.store(false, .seq_cst);
                instance_global = null;

                return Error.SocketFailed;
            };

            assert(server.thread != null);
            assert(server.listen_fd >= 0);
        }

        pub fn stop(server: *Server) void {
            const thread = server.thread orelse return;

            server.running.store(false, .seq_cst);

            thread.join();

            server.thread = null;

            var index: u8 = 0;

            while (index < client_count_max) : (index += 1) {
                server.drop_client(index);
            }

            server.close_socket();
            server.release_lock();

            instance_global = null;

            assert(server.thread == null);
        }

        pub fn send_notify(server: *Server, binding: *const Binding, key: ?*const Key) void {
            var payload = protocol.Notify{
                .id = binding.remote_id,
                .key = 0,
                .modifiers = 0,
                .down = 0,
                .time_ms = time.now_ms(),
            };

            if (key) |value| {
                payload.key = @intFromEnum(value.value);
                payload.modifiers = @intCast(value.modifiers.flags);
                payload.down = @intFromBool(value.down);
            }

            server.send(binding.client, .notify, protocol.Notify, &payload);
        }

        pub fn broadcast_released(server: *Server) void {
            const payload = protocol.Released{};

            var index: u8 = 0;

            while (index < client_count_max) : (index += 1) {
                if (server.clients[index].is_connected()) {
                    server.send(index, .released, protocol.Released, &payload);
                }
            }

            assert(index == client_count_max);
        }

        pub fn on_runtime_released() void {
            const self = instance_global orelse return;

            self.broadcast_released();
        }

        fn acquire_lock(server: *Server) Error!void {
            var buffer: [protocol.path_bytes_max]u8 = @splat(0);
            const path = protocol.lock_path(&buffer) orelse return Error.PathUnavailable;
            const flags = posix.O{ .ACCMODE = .RDWR, .CREAT = true, .CLOEXEC = true };

            const fd = posix.openatZ(posix.AT.FDCWD, path, flags, 0o600) catch {
                return Error.PathUnavailable;
            };

            const status = linux.flock(fd, posix.LOCK.EX | posix.LOCK.NB);

            if (posix.errno(status) != .SUCCESS) {
                _ = linux.close(fd);

                return Error.LockUnavailable;
            }

            server.lock_fd = fd;

            assert(server.lock_fd >= 0);
        }

        fn release_lock(server: *Server) void {
            if (server.lock_fd < 0) {
                return;
            }

            _ = linux.flock(server.lock_fd, posix.LOCK.UN);
            _ = linux.close(server.lock_fd);

            server.lock_fd = -1;
        }

        fn open_socket(server: *Server) Error!void {
            assert(server.listen_fd < 0);

            var buffer: [protocol.path_bytes_max]u8 = @splat(0);
            const path = protocol.socket_path(&buffer) orelse return Error.PathUnavailable;

            _ = linux.unlink(path);

            const kind = linux.SOCK.SEQPACKET | linux.SOCK.CLOEXEC;
            const created = linux.socket(linux.AF.UNIX, kind, 0);

            if (posix.errno(created) != .SUCCESS) {
                return Error.SocketFailed;
            }

            const fd: posix.fd_t = @intCast(created);
            errdefer _ = linux.close(fd);

            var address = unix_address(path) orelse return Error.PathUnavailable;
            const length = unix_address_length(path);
            const bound = linux.bind(fd, @ptrCast(&address), length);

            if (posix.errno(bound) != .SUCCESS) {
                return Error.SocketFailed;
            }

            const listening = linux.listen(fd, backlog);

            if (posix.errno(listening) != .SUCCESS) {
                return Error.SocketFailed;
            }

            server.listen_fd = fd;

            assert(server.listen_fd >= 0);
        }

        fn close_socket(server: *Server) void {
            if (server.listen_fd < 0) {
                return;
            }

            _ = linux.close(server.listen_fd);

            server.listen_fd = -1;

            var buffer: [protocol.path_bytes_max]u8 = @splat(0);

            if (protocol.socket_path(&buffer)) |path| {
                _ = linux.unlink(path);
            }
        }

        fn serve(server: *Server) void {
            while (server.running.load(.seq_cst)) {
                server.serve_once();
            }
        }

        fn serve_once(server: *Server) void {
            var fds: [1 + client_count_max]linux.pollfd = undefined;

            fds[0] = .{ .fd = server.listen_fd, .events = linux.POLL.IN, .revents = 0 };

            var index: u8 = 0;

            while (index < client_count_max) : (index += 1) {
                const client = &server.clients[index];
                const fd: posix.fd_t = if (client.is_connected()) client.fd else -1;

                fds[1 + index] = .{ .fd = fd, .events = linux.POLL.IN, .revents = 0 };
            }

            const ready = linux.poll(&fds, fds.len, poll_interval_ms);

            if (posix.errno(ready) != .SUCCESS) {
                return;
            }

            if (fds[0].revents & linux.POLL.IN != 0) {
                server.accept_client();
            }

            index = 0;

            while (index < client_count_max) : (index += 1) {
                const revents = fds[1 + index].revents;

                if (revents & (linux.POLL.IN | linux.POLL.HUP | linux.POLL.ERR) != 0) {
                    server.service_client(index);
                }
            }

            assert(index == client_count_max);
        }

        fn accept_client(server: *Server) void {
            const accepted = linux.accept4(server.listen_fd, null, null, linux.SOCK.CLOEXEC);

            if (posix.errno(accepted) != .SUCCESS) {
                return;
            }

            const fd: posix.fd_t = @intCast(accepted);

            var index: u8 = 0;

            while (index < client_count_max) : (index += 1) {
                const client = &server.clients[index];

                if (!client.is_connected()) {
                    client.* = .{ .fd = fd };

                    log.info("client {d} connected", .{index});

                    return;
                }
            }

            log.warn("client table full, rejecting connection", .{});

            _ = linux.close(fd);
        }

        fn service_client(server: *Server, index: u8) void {
            const client = &server.clients[index];

            if (!client.is_connected()) {
                return;
            }

            var buffer: [receive_bytes_max]u8 = undefined;
            const received = linux.recvfrom(client.fd, &buffer, buffer.len, 0, null, null);

            if (posix.errno(received) != .SUCCESS) {
                server.drop_client(index);

                return;
            }

            const size: usize = @intCast(received);

            if (size == 0) {
                server.drop_client(index);

                return;
            }

            server.handle_message(index, buffer[0..size]);
        }

        fn handle_message(server: *Server, index: u8, bytes: []const u8) void {
            if (bytes.len < @sizeOf(protocol.Header)) {
                server.drop_client(index);

                return;
            }

            var header: protocol.Header = undefined;

            @memcpy(std.mem.asBytes(&header), bytes[0..@sizeOf(protocol.Header)]);

            const payload = bytes[@sizeOf(protocol.Header)..];

            if (payload.len != header.size) {
                server.drop_client(index);

                return;
            }

            const tag = std.enums.fromInt(protocol.Tag, header.tag) orelse {
                server.drop_client(index);

                return;
            };

            server.dispatch_message(index, tag, payload);
        }

        fn dispatch_message(
            server: *Server,
            index: u8,
            tag: protocol.Tag,
            payload: []const u8,
        ) void {
            switch (tag) {
                .hello => server.on_hello(index, payload),
                .bind_key => server.on_bind_key(index, payload),
                .bind_chord => server.on_bind_chord(index, payload),
                .bind_sequence => server.on_bind_sequence(index, payload),
                .unbind => server.on_unbind(index, payload),
                .set_blocked => server.on_set_blocked(index, payload),
                .claim_filter => server.on_claim_filter(index, payload),
                .verdict => server.on_verdict(index, payload),
                .simulate_key => server.on_simulate_key(index, payload),
                .simulate_combination => server.on_simulate_combination(index, payload),
                .simulate_text => server.on_simulate_text(index, payload),
                .simulate_button => server.on_simulate_button(index, payload),
                .simulate_move => server.on_simulate_move(index, payload),
                .simulate_scroll => server.on_simulate_scroll(index, payload),

                .hello_ok, .bound, .reject, .key_query, .notify, .released => {
                    server.drop_client(index);
                },
            }
        }

        fn decode(
            server: *Server,
            index: u8,
            comptime Payload: type,
            payload: []const u8,
        ) ?Payload {
            if (payload.len != @sizeOf(Payload)) {
                server.drop_client(index);

                return null;
            }

            var value: Payload = undefined;

            @memcpy(std.mem.asBytes(&value), payload);

            return value;
        }

        fn on_hello(server: *Server, index: u8, payload: []const u8) void {
            const hello = server.decode(index, protocol.Hello, payload) orelse return;

            if (hello.version != protocol.version) {
                server.drop_client(index);

                return;
            }

            server.clients[index].ready = true;

            const reply = protocol.Hello{ .version = protocol.version };

            server.send(index, .hello_ok, protocol.Hello, &reply);
        }

        fn allocate_binding(server: *Server, index: u8, remote_id: u32) ?u16 {
            var slot: u16 = 0;

            while (slot < binding_count_max) : (slot += 1) {
                if (!server.bindings[slot].used) {
                    server.bindings[slot] = .{
                        .used = true,
                        .client = index,
                        .remote_id = remote_id,
                    };

                    return slot;
                }
            }

            server.reject(index, remote_id, 1);

            return null;
        }

        fn on_bind_key(server: *Server, index: u8, payload: []const u8) void {
            const request = server.decode(index, protocol.BindKey, payload) orelse return;

            const key = protocol.keycode_of(request.key) orelse {
                return server.reject(index, request.id, 2);
            };

            const modifiers = protocol.modifiers_of(request.modifiers) orelse {
                return server.reject(index, request.id, 2);
            };

            const slot = server.allocate_binding(index, request.id) orelse return;

            server.bindings[slot].kind = .key;
            server.bindings[slot].consume = request.consume != 0;

            const nimble_id = server.keyboard.registry.register(
                key,
                modifiers,
                binding_key_callback,
                &server.bindings[slot],
                .{ .block_exempt = request.exempt != 0 },
            ) catch {
                server.bindings[slot] = .{};

                return server.reject(index, request.id, 3);
            };

            server.bindings[slot].nimble_id = nimble_id;

            server.confirm(index, request.id);
        }

        fn on_bind_chord(server: *Server, index: u8, payload: []const u8) void {
            const request = server.decode(index, protocol.BindChord, payload) orelse return;

            var keys: [protocol.chord_keys_max]Keycode = undefined;

            const count = server.decode_keys(
                index,
                request.id,
                request.keys[0..],
                request.count,
                &keys,
            ) orelse return;

            const slot = server.allocate_binding(index, request.id) orelse return;

            server.bindings[slot].kind = .chord;
            server.bindings[slot].consume = request.consume != 0;

            const nimble_id = server.keyboard.chord_registry.register(
                keys[0..count],
                binding_plain_callback,
                &server.bindings[slot],
                .{},
            ) catch {
                server.bindings[slot] = .{};

                return server.reject(index, request.id, 3);
            };

            server.bindings[slot].nimble_id = nimble_id;

            server.confirm(index, request.id);
        }

        fn on_bind_sequence(server: *Server, index: u8, payload: []const u8) void {
            const request = server.decode(index, protocol.BindSequence, payload) orelse return;

            if (request.count == 0 or request.count > protocol.sequence_keys_max) {
                return server.reject(index, request.id, 2);
            }

            var characters: [protocol.sequence_keys_max]u8 = undefined;
            var position: u8 = 0;

            while (position < request.count) : (position += 1) {
                characters[position] = request.keys[position].key;
            }

            assert(position == request.count);

            const slot = server.allocate_binding(index, request.id) orelse return;

            server.bindings[slot].kind = .sequence;
            server.bindings[slot].consume = request.consume != 0;

            const nimble_id = server.keyboard.sequence_registry.register(
                characters[0..request.count],
                binding_sequence_callback,
                &server.bindings[slot],
                .{ .block_exempt = request.exempt != 0 },
            ) catch {
                server.bindings[slot] = .{};

                return server.reject(index, request.id, 3);
            };

            server.bindings[slot].nimble_id = nimble_id;

            server.confirm(index, request.id);
        }

        fn decode_keys(
            server: *Server,
            index: u8,
            remote_id: u32,
            patterns: []const protocol.Pattern,
            count: u8,
            keys: []Keycode,
        ) ?u8 {
            if (count == 0 or count > patterns.len or count > keys.len) {
                server.reject(index, remote_id, 2);

                return null;
            }

            var position: u8 = 0;

            while (position < count) : (position += 1) {
                keys[position] = protocol.keycode_of(patterns[position].key) orelse {
                    server.reject(index, remote_id, 2);

                    return null;
                };
            }

            assert(position == count);

            return count;
        }

        fn on_unbind(server: *Server, index: u8, payload: []const u8) void {
            const request = server.decode(index, protocol.Unbind, payload) orelse return;

            var slot: u16 = 0;

            while (slot < binding_count_max) : (slot += 1) {
                const binding = &server.bindings[slot];

                if (binding.used and binding.client == index and binding.remote_id == request.id) {
                    server.remove_binding(slot);

                    return;
                }
            }

            assert(slot == binding_count_max);
        }

        fn remove_binding(server: *Server, slot: u16) void {
            assert(slot < binding_count_max);

            const binding = &server.bindings[slot];

            assert(binding.used);

            switch (binding.kind) {
                .key => server.keyboard.registry.unregister(binding.nimble_id) catch |err| {
                    log.warn("key unregister failed: {}", .{err});
                },

                .chord => server.keyboard.chord_registry.unregister(binding.nimble_id) catch |err| {
                    log.warn("chord unregister failed: {}", .{err});
                },

                .sequence => server.keyboard.sequence_registry.unregister(
                    binding.nimble_id,
                ) catch |err| {
                    log.warn("sequence unregister failed: {}", .{err});
                },
            }

            binding.* = .{};

            assert(!binding.used);
        }

        fn on_set_blocked(server: *Server, index: u8, payload: []const u8) void {
            const request = server.decode(index, protocol.SetBlocked, payload) orelse return;

            server.clients[index].blocked_keyboard = request.keyboard != 0;
            server.clients[index].blocked_mouse = request.mouse != 0;

            server.apply_blocked();
        }

        fn apply_blocked(server: *Server) void {
            var keyboard_blocked = false;
            var mouse_blocked = false;
            var index: u8 = 0;

            while (index < client_count_max) : (index += 1) {
                const client = &server.clients[index];

                if (!client.is_connected()) {
                    continue;
                }

                keyboard_blocked = keyboard_blocked or client.blocked_keyboard;
                mouse_blocked = mouse_blocked or client.blocked_mouse;
            }

            server.keyboard.set_blocked(keyboard_blocked);
            server.mouse.set_blocked(mouse_blocked);

            assert(index == client_count_max);
        }

        fn on_claim_filter(server: *Server, index: u8, payload: []const u8) void {
            const request = server.decode(index, protocol.ClaimFilter, payload) orelse return;

            if (request.count > protocol.filter_patterns_max) {
                server.drop_client(index);

                return;
            }

            const client = &server.clients[index];

            client.filter = request.patterns;
            client.filter_count = request.count;

            assert(client.filter_count <= protocol.filter_patterns_max);
        }

        fn on_verdict(server: *Server, index: u8, payload: []const u8) void {
            const request = server.decode(index, protocol.Verdict, payload) orelse return;

            const client = &server.clients[index];

            if (client.query_state.load(.seq_cst) != query_pending) {
                return;
            }

            if (client.query_serial != request.serial) {
                return;
            }

            client.query_answer = request.response;
            client.query_state.store(query_answered, .seq_cst);

            futex_wake(&client.query_state.raw);
        }

        fn on_simulate_key(server: *Server, index: u8, payload: []const u8) void {
            const request = server.decode(index, protocol.SimulateKey, payload) orelse return;

            const action = std.enums.fromInt(protocol.KeyAction, request.action) orelse return;

            if (action == .dummy) {
                _ = simulate_key.dummy();

                return;
            }

            const key = protocol.keycode_of(request.key) orelse return;

            _ = switch (action) {
                .down => simulate_key.key_down(key),
                .up => simulate_key.key_up(key),
                .press => simulate_key.press(key),
                .suppress => simulate_key.suppress(key),
                .dummy => unreachable,
            };
        }

        fn on_simulate_combination(server: *Server, index: u8, payload: []const u8) void {
            const combination = protocol.SimulateCombination;
            const request = server.decode(index, combination, payload) orelse return;

            const key = protocol.keycode_of(request.key) orelse return;
            const modifiers = protocol.modifiers_of(request.modifiers) orelse return;

            _ = simulate_key.combination(&modifiers, key);
        }

        fn on_simulate_text(server: *Server, index: u8, payload: []const u8) void {
            const request = server.decode(index, protocol.SimulateText, payload) orelse return;

            if (request.length > protocol.text_bytes_max) {
                return;
            }

            const text = request.bytes[0..request.length];

            _ = simulate_text.send_with_delay(text, request.delay_ms) catch return;
        }

        fn on_simulate_button(server: *Server, index: u8, payload: []const u8) void {
            const request = server.decode(index, protocol.SimulateButton, payload) orelse return;

            const button = std.enums.fromInt(simulate_mouse.Button, request.button) orelse return;

            if (request.click != 0) {
                _ = simulate_mouse.click(button);

                return;
            }

            if (request.down != 0) {
                _ = simulate_mouse.button_down(button);
            } else {
                _ = simulate_mouse.button_up(button);
            }
        }

        fn on_simulate_move(server: *Server, index: u8, payload: []const u8) void {
            const request = server.decode(index, protocol.SimulateMove, payload) orelse return;

            _ = simulate_mouse.move_relative(request.delta_x, request.delta_y);
        }

        fn on_simulate_scroll(server: *Server, index: u8, payload: []const u8) void {
            const request = server.decode(index, protocol.SimulateScroll, payload) orelse return;

            if (request.vertical > 0) {
                _ = simulate_mouse.scroll_up(@intCast(request.vertical));
            } else if (request.vertical < 0) {
                _ = simulate_mouse.scroll_down(@intCast(-request.vertical));
            }

            if (request.horizontal > 0) {
                _ = simulate_mouse.scroll_right(@intCast(request.horizontal));
            } else if (request.horizontal < 0) {
                _ = simulate_mouse.scroll_left(@intCast(-request.horizontal));
            }
        }

        fn drop_client(server: *Server, index: u8) void {
            const client = &server.clients[index];

            if (!client.is_connected()) {
                return;
            }

            log.info("client {d} disconnected", .{index});

            var slot: u16 = 0;

            while (slot < binding_count_max) : (slot += 1) {
                if (server.bindings[slot].used and server.bindings[slot].client == index) {
                    server.remove_binding(slot);
                }
            }

            _ = linux.close(client.fd);

            client.* = .{};

            server.apply_blocked();

            assert(!client.is_connected());
        }

        fn confirm(server: *Server, index: u8, remote_id: u32) void {
            const payload = protocol.Bound{ .id = remote_id };

            server.send(index, .bound, protocol.Bound, &payload);
        }

        fn reject(server: *Server, index: u8, remote_id: u32, code: u32) void {
            const payload = protocol.Reject{ .id = remote_id, .code = code };

            server.send(index, .reject, protocol.Reject, &payload);
        }

        fn send(
            server: *Server,
            index: u8,
            tag: protocol.Tag,
            comptime Payload: type,
            payload: *const Payload,
        ) void {
            const client = &server.clients[index];

            if (!client.is_connected()) {
                return;
            }

            var buffer: [receive_bytes_max]u8 = undefined;
            const header = protocol.Header.of(tag, Payload);

            @memcpy(buffer[0..@sizeOf(protocol.Header)], std.mem.asBytes(&header));

            @memcpy(
                buffer[@sizeOf(protocol.Header)..][0..@sizeOf(Payload)],
                std.mem.asBytes(payload),
            );

            const total = @sizeOf(protocol.Header) + @sizeOf(Payload);
            const flags = linux.MSG.DONTWAIT | linux.MSG.NOSIGNAL;

            _ = linux.sendto(client.fd, &buffer, total, flags, null, 0);
        }

        fn filter_callback(context: *anyopaque, key: *const Key) ?Response {
            const self: *Server = @ptrCast(@alignCast(context));

            var index: u8 = 0;

            while (index < client_count_max) : (index += 1) {
                const client = &self.clients[index];

                if (!client.is_connected() or client.filter_count == 0) {
                    continue;
                }

                if (!filter_matches(client, key)) {
                    continue;
                }

                const verdict = self.query_client(index, key);

                if (verdict != .pass) {
                    return verdict;
                }
            }

            assert(index == client_count_max);

            return null;
        }

        fn filter_matches(client: *const Client, key: *const Key) bool {
            var index: u8 = 0;

            while (index < client.filter_count) : (index += 1) {
                if (pattern_matches(&client.filter[index], key)) {
                    return true;
                }
            }

            assert(index == client.filter_count);

            return false;
        }

        fn pattern_matches(pattern: *const protocol.Pattern, key: *const Key) bool {
            if (pattern.match_any_key == 0) {
                const wanted = protocol.keycode_of(pattern.key) orelse return false;

                if (wanted != key.value) {
                    return false;
                }
            }

            const required = protocol.modifiers_of(pattern.modifiers) orelse return false;

            if (pattern.match_any_modifiers != 0) {
                return modifiers_superset(key.modifiers, required);
            }

            return required.eql(&key.modifiers);
        }

        fn modifiers_superset(present: anytype, required: anytype) bool {
            return (present.flags & required.flags) == required.flags;
        }

        fn query_client(server: *Server, index: u8, key: *const Key) Response {
            const client = &server.clients[index];
            const serial = server.serial_next;

            server.serial_next +%= 1;

            client.query_serial = serial;
            client.query_state.store(query_pending, .seq_cst);

            const query = protocol.KeyQuery{
                .serial = serial,
                .key = @intFromEnum(key.value),
                .modifiers = @intCast(key.modifiers.flags),
                .down = @intFromBool(key.down),
                .injected = @intFromBool(key.injected),
            };

            server.send(index, .key_query, protocol.KeyQuery, &query);

            const deadline_ms = time.now_ms() + protocol.verdict_timeout_ms;

            while (client.query_state.load(.seq_cst) == query_pending) {
                const remaining_ms = deadline_ms - time.now_ms();

                if (remaining_ms <= 0) {
                    break;
                }

                futex_wait(&client.query_state.raw, query_pending, remaining_ms);
            }

            const answered = client.query_state.load(.seq_cst) == query_answered;

            client.query_state.store(query_idle, .seq_cst);

            if (!answered) {
                return .pass;
            }

            return protocol.response_of(client.query_answer) orelse .pass;
        }
    };
}

const Keycode = @import("../../../keycode.zig").Keycode;

fn binding_key_callback(context: *anyopaque, key: *const Key) Response {
    const binding: *Binding = @ptrCast(@alignCast(context));

    notify_binding(binding, key);

    if (binding.consume) {
        return .consume;
    }

    return .pass;
}

fn binding_sequence_callback(context: *anyopaque) void {
    const binding: *Binding = @ptrCast(@alignCast(context));

    notify_binding(binding, null);
}

fn binding_plain_callback(context: *anyopaque) Response {
    const binding: *Binding = @ptrCast(@alignCast(context));

    notify_binding(binding, null);

    if (binding.consume) {
        return .consume;
    }

    return .pass;
}

var notify_sender: ?*const fn (binding: *const Binding, key: ?*const Key) void = null;

pub fn set_notify_sender(sender: ?*const fn (binding: *const Binding, key: ?*const Key) void) void {
    notify_sender = sender;
}

fn notify_binding(binding: *const Binding, key: ?*const Key) void {
    const sender = notify_sender orelse return;

    sender(binding, key);
}

pub fn unix_address(path: [:0]const u8) ?linux.sockaddr.un {
    var address = linux.sockaddr.un{ .family = linux.AF.UNIX, .path = @splat(0) };

    if (path.len + 1 > address.path.len) {
        return null;
    }

    @memcpy(address.path[0..path.len], path);

    return address;
}

pub fn unix_address_length(path: [:0]const u8) linux.socklen_t {
    assert(path.len > 0);

    return @intCast(@offsetOf(linux.sockaddr.un, "path") + path.len + 1);
}

fn futex_wait(address: *const u32, expected: u32, timeout_ms: i64) void {
    assert(timeout_ms > 0);

    const timeout = linux.timespec{
        .sec = @divFloor(timeout_ms, 1000),
        .nsec = @mod(timeout_ms, 1000) * 1_000_000,
    };

    _ = linux.futex_4arg(address, .{ .cmd = .WAIT, .private = true }, expected, &timeout);
}

fn futex_wake(address: *const u32) void {
    _ = linux.futex_3arg(address, .{ .cmd = .WAKE, .private = true }, 1);
}
