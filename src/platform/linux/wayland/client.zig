const std = @import("std");

const wire = @import("wire.zig");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

pub const global_count_max: u16 = 128;
pub const interface_bytes_max: u16 = 64;
pub const read_bytes_max: u16 = 4096;
pub const roundtrip_reads_max: u16 = 256;

pub const object_display: u32 = 1;
pub const opcode_display_sync: u16 = 0;
pub const opcode_display_get_registry: u16 = 1;
pub const opcode_registry_bind: u16 = 0;
pub const event_registry_global: u16 = 0;
pub const event_callback_done: u16 = 0;
pub const event_display_error: u16 = 0;

pub const Error = error{
    NoDisplay,
    ConnectFailed,
    ProtocolError,
    SocketFailed,
    TooManyGlobals,
    WriteFailed,
};

pub const Global = struct {
    name: u32 = 0,
    version: u32 = 0,
    interface: [interface_bytes_max]u8 = @splat(0),
    interface_len: u16 = 0,

    pub fn matches(global: *const Global, target: []const u8) bool {
        assert(global.interface_len <= interface_bytes_max);

        return std.mem.eql(u8, global.interface[0..global.interface_len], target);
    }
};

pub const Connection = struct {
    fd: posix.fd_t = -1,
    next_id: u32 = 2,
    registry: u32 = 0,
    globals: [global_count_max]Global = @splat(.{}),
    global_count: u16 = 0,
    done: bool = false,

    pub fn is_open(connection: *const Connection) bool {
        return connection.fd >= 0;
    }

    pub fn allocate_id(connection: *Connection) u32 {
        const id = connection.next_id;

        connection.next_id += 1;

        assert(id >= 2);

        return id;
    }

    pub fn find(connection: *const Connection, target: []const u8) ?Global {
        assert(connection.global_count <= global_count_max);

        var index: u16 = 0;

        while (index < connection.global_count) : (index += 1) {
            if (connection.globals[index].matches(target)) {
                return connection.globals[index];
            }
        }

        return null;
    }

    pub fn has(connection: *const Connection, target: []const u8) bool {
        return connection.find(target) != null;
    }

    pub fn close(connection: *Connection) void {
        if (!connection.is_open()) {
            return;
        }

        _ = linux.close(connection.fd);

        connection.fd = -1;

        assert(!connection.is_open());
    }

    pub fn send_raw(connection: *Connection, bytes: []const u8) Error!void {
        return connection.send(bytes);
    }

    pub fn read_raw(connection: *Connection, buffer: []u8) Error!usize {
        assert(connection.is_open());

        return posix.read(connection.fd, buffer) catch Error.ProtocolError;
    }

    fn send(connection: *Connection, bytes: []const u8) Error!void {
        assert(connection.is_open());
        assert(bytes.len >= wire.header_bytes);

        const written = linux.write(connection.fd, bytes.ptr, bytes.len);

        if (posix.errno(written) != .SUCCESS) {
            return Error.WriteFailed;
        }
    }

    pub fn get_registry(connection: *Connection) Error!void {
        assert(connection.registry == 0);

        const id = connection.allocate_id();

        var writer = wire.Writer{};

        writer.begin(object_display);
        writer.put_u32(id);
        writer.seal(opcode_display_get_registry);

        try connection.send(writer.finish());

        connection.registry = id;

        assert(connection.registry >= 2);
    }

    pub fn bind(connection: *Connection, global: Global, version: u32) Error!u32 {
        assert(connection.registry >= 2);
        assert(global.interface_len > 0);

        const id = connection.allocate_id();

        var writer = wire.Writer{};

        writer.begin(connection.registry);
        writer.put_u32(global.name);

        writer.put_string(global.interface[0..global.interface_len]) catch {
            return Error.ProtocolError;
        };

        writer.put_u32(version);
        writer.put_u32(id);
        writer.seal(opcode_registry_bind);

        try connection.send(writer.finish());

        return id;
    }

    pub fn roundtrip(connection: *Connection) Error!void {
        assert(connection.is_open());

        const callback = connection.allocate_id();

        var writer = wire.Writer{};

        writer.begin(object_display);
        writer.put_u32(callback);
        writer.seal(opcode_display_sync);

        try connection.send(writer.finish());

        connection.done = false;

        var reads: u16 = 0;

        while (reads < roundtrip_reads_max and !connection.done) : (reads += 1) {
            try connection.pump(callback);
        }

        assert(reads <= roundtrip_reads_max);
    }

    fn pump(connection: *Connection, callback: u32) Error!void {
        var buffer: [read_bytes_max]u8 = undefined;
        const size = posix.read(connection.fd, &buffer) catch return Error.ProtocolError;

        if (size == 0) {
            return Error.ProtocolError;
        }

        var reader = wire.Reader{ .bytes = buffer[0..size] };

        while (reader.remaining() >= wire.header_bytes) {
            const header = reader.read_header() catch return Error.ProtocolError;
            const body = header.size - wire.header_bytes;
            const start = reader.offset;

            connection.dispatch(header, &reader, callback) catch return Error.ProtocolError;

            reader.offset = start;
            reader.skip(body) catch return Error.ProtocolError;
        }
    }

    fn dispatch(
        connection: *Connection,
        header: wire.Header,
        reader: *wire.Reader,
        callback: u32,
    ) !void {
        if (header.object == callback and header.opcode == event_callback_done) {
            connection.done = true;

            return;
        }

        if (header.object == connection.registry and header.opcode == event_registry_global) {
            try connection.record_global(reader);

            return;
        }
    }

    fn record_global(connection: *Connection, reader: *wire.Reader) !void {
        const name = try reader.read_u32();
        const interface = try reader.read_string();
        const version = try reader.read_u32();

        if (connection.global_count == global_count_max) {
            return;
        }

        if (interface.len > interface_bytes_max) {
            return;
        }

        var global = Global{ .name = name, .version = version };

        @memcpy(global.interface[0..interface.len], interface);

        global.interface_len = @intCast(interface.len);

        connection.globals[connection.global_count] = global;
        connection.global_count += 1;

        assert(connection.global_count <= global_count_max);
    }
};

pub fn connect(path: []const u8) Error!Connection {
    if (path.len == 0 or path.len >= 108) {
        return Error.NoDisplay;
    }

    const created = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);

    if (posix.errno(created) != .SUCCESS) {
        return Error.SocketFailed;
    }

    const fd: posix.fd_t = @intCast(created);
    errdefer _ = linux.close(fd);

    var address = linux.sockaddr.un{ .path = @splat(0) };

    @memcpy(address.path[0..path.len], path);

    const status = linux.connect(fd, &address, @sizeOf(linux.sockaddr.un));

    if (posix.errno(status) != .SUCCESS) {
        return Error.ConnectFailed;
    }

    return Connection{ .fd = fd };
}

pub fn socket_path(buffer: *[108]u8, runtime: []const u8, display: []const u8) ?[]const u8 {
    if (display.len == 0) {
        return null;
    }

    if (display[0] == '/') {
        if (display.len >= buffer.len) {
            return null;
        }

        @memcpy(buffer[0..display.len], display);

        return buffer[0..display.len];
    }

    if (runtime.len == 0) {
        return null;
    }

    const total = runtime.len + 1 + display.len;

    if (total >= buffer.len) {
        return null;
    }

    @memcpy(buffer[0..runtime.len], runtime);

    buffer[runtime.len] = '/';

    @memcpy(buffer[runtime.len + 1 ..][0..display.len], display);

    return buffer[0..total];
}

const testing = std.testing;

test "a fresh connection is closed and allocates ids from two" {
    var connection = Connection{};

    try testing.expect(!connection.is_open());
    try testing.expectEqual(@as(u32, 2), connection.allocate_id());
    try testing.expectEqual(@as(u32, 3), connection.allocate_id());
}

test "globals match on their exact interface name" {
    var global = Global{ .name = 7, .version = 3 };

    @memcpy(global.interface[0.."wl_output".len], "wl_output");

    global.interface_len = "wl_output".len;

    try testing.expect(global.matches("wl_output"));
    try testing.expect(!global.matches("wl_outpu"));
    try testing.expect(!global.matches("wl_output2"));
}

test "socket_path composes a runtime relative display name" {
    var buffer: [108]u8 = @splat(0);
    const path = socket_path(&buffer, "/run/user/1000", "wayland-0") orelse
        return error.MissingPath;

    try testing.expectEqualStrings("/run/user/1000/wayland-0", path);
}

test "socket_path passes an absolute display through unchanged" {
    var buffer: [108]u8 = @splat(0);
    const path = socket_path(&buffer, "", "/tmp/custom.sock") orelse return error.MissingPath;

    try testing.expectEqualStrings("/tmp/custom.sock", path);
}

test "socket_path refuses an empty or oversized display" {
    var buffer: [108]u8 = @splat(0);
    const long = "d" ** 120;

    try testing.expect(socket_path(&buffer, "/run/user/1000", "") == null);
    try testing.expect(socket_path(&buffer, "/run/user/1000", long) == null);
    try testing.expect(socket_path(&buffer, "", "wayland-0") == null);
}

test "connect refuses an empty path without touching a socket" {
    try testing.expectError(Error.NoDisplay, connect(""));
}

test "an empty registry finds nothing" {
    const connection = Connection{};

    try testing.expect(connection.find("wl_output") == null);
    try testing.expect(!connection.has("wl_output"));
}
