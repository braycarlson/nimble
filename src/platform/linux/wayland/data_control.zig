const std = @import("std");

const client = @import("client.zig");
const fd = @import("fd.zig");
const wire = @import("wire.zig");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

pub const interface_ext = "ext_data_control_manager_v1";
pub const interface_wlr = "zwlr_data_control_manager_v1";
pub const interface_seat = "wl_seat";
pub const mime_text = "text/plain;charset=utf-8";

pub const opcode_manager_create_source: u16 = 0;
pub const opcode_manager_get_device: u16 = 1;
pub const opcode_source_offer: u16 = 0;
pub const opcode_device_set_selection: u16 = 0;
pub const opcode_offer_receive: u16 = 0;

pub const event_device_data_offer: u16 = 0;
pub const event_device_selection: u16 = 1;
pub const event_source_send: u16 = 0;
pub const event_source_cancelled: u16 = 1;

pub const version_manager: u32 = 1;
pub const version_seat: u32 = 1;
pub const serve_reads_max: u16 = 64;
pub const text_bytes_max: u16 = 4096;

pub const Error = error{
    Unsupported,
    NoSeat,
    TransferFailed,
    TextTooLong,
} || client.Error;

pub const Session = struct {
    connection: client.Connection = .{},
    manager: u32 = 0,
    seat: u32 = 0,
    device: u32 = 0,
    source: u32 = 0,
    offer: u32 = 0,
    selection: u32 = 0,

    pub fn is_open(session: *const Session) bool {
        return session.connection.is_open();
    }

    pub fn close(session: *Session) void {
        session.connection.close();

        session.manager = 0;
        session.device = 0;
        session.source = 0;
        session.offer = 0;
        session.selection = 0;
    }
};

comptime {
    assert(mime_text.len > 0);
    assert(serve_reads_max > 0);
    assert(text_bytes_max > 0);
}

pub fn open(session: *Session, path: []const u8) Error!void {
    assert(!session.is_open());

    session.connection = try client.connect(path);
    errdefer session.close();

    try session.connection.get_registry();
    try session.connection.roundtrip();

    const manager_global = session.connection.find(interface_ext) orelse
        session.connection.find(interface_wlr) orelse return Error.Unsupported;

    const seat_global = session.connection.find(interface_seat) orelse return Error.NoSeat;

    session.manager = try session.connection.bind(manager_global, version_manager);
    session.seat = try session.connection.bind(seat_global, version_seat);
    session.device = session.connection.allocate_id();

    var writer = wire.Writer{};

    writer.begin(session.manager);
    writer.put_u32(session.device);
    writer.put_u32(session.seat);
    writer.seal(opcode_manager_get_device);

    try session.connection.send_raw(writer.finish());

    assert(session.device >= 2);
}

pub fn set(session: *Session, text: []const u8) Error!void {
    assert(session.is_open());

    if (text.len > text_bytes_max) {
        return Error.TextTooLong;
    }

    session.source = session.connection.allocate_id();

    var writer = wire.Writer{};

    writer.begin(session.manager);
    writer.put_u32(session.source);
    writer.seal(opcode_manager_create_source);

    try session.connection.send_raw(writer.finish());

    writer = wire.Writer{};

    writer.begin(session.source);
    writer.put_string(mime_text) catch return Error.TransferFailed;
    writer.seal(opcode_source_offer);

    try session.connection.send_raw(writer.finish());

    writer = wire.Writer{};

    writer.begin(session.device);
    writer.put_u32(session.source);
    writer.seal(opcode_device_set_selection);

    try session.connection.send_raw(writer.finish());

    assert(session.source >= 2);
}

pub fn serve(session: *Session, text: []const u8) Error!u32 {
    assert(session.is_open());
    assert(session.source >= 2);

    var served: u32 = 0;
    var reads: u16 = 0;

    while (reads < serve_reads_max) : (reads += 1) {
        var buffer: [client.read_bytes_max]u8 = undefined;
        var descriptor: posix.fd_t = -1;

        const size = fd.receive_with_fd(session.connection.fd, &buffer, &descriptor) catch break;

        if (size == 0) {
            break;
        }

        if (descriptor < 0) {
            continue;
        }

        if (!is_send_event(session, buffer[0..size])) {
            fd.close(descriptor);

            continue;
        }

        _ = linux.write(descriptor, text.ptr, text.len);

        fd.close(descriptor);

        served += 1;

        break;
    }

    assert(reads <= serve_reads_max);

    return served;
}

fn is_send_event(session: *const Session, bytes: []const u8) bool {
    var reader = wire.Reader{ .bytes = bytes };

    while (reader.remaining() >= wire.header_bytes) {
        const header = reader.read_header() catch return false;
        const body = header.size - wire.header_bytes;

        if (header.object == session.source and header.opcode == event_source_send) {
            return true;
        }

        reader.skip(body) catch return false;
    }

    return false;
}

pub fn get(session: *Session, buffer: []u8) Error!usize {
    assert(session.is_open());
    assert(buffer.len > 0);

    try await_selection(session);

    if (session.selection == 0) {
        return Error.Unsupported;
    }

    var read_end: posix.fd_t = -1;
    var write_end: posix.fd_t = -1;

    fd.make_pipe(&read_end, &write_end) catch return Error.TransferFailed;
    defer fd.close(read_end);

    var writer = wire.Writer{};

    writer.begin(session.selection);
    writer.put_string(mime_text) catch return Error.TransferFailed;
    writer.seal(opcode_offer_receive);

    fd.send_with_fd(session.connection.fd, writer.finish(), write_end) catch {
        fd.close(write_end);

        return Error.TransferFailed;
    };

    fd.close(write_end);

    const size = posix.read(read_end, buffer) catch return Error.TransferFailed;

    assert(size <= buffer.len);

    return size;
}

fn await_selection(session: *Session) Error!void {
    var reads: u16 = 0;

    while (reads < serve_reads_max and session.selection == 0) : (reads += 1) {
        var buffer: [client.read_bytes_max]u8 = undefined;
        const size = session.connection.read_raw(&buffer) catch break;

        if (size == 0) {
            break;
        }

        absorb(session, buffer[0..size]);
    }

    assert(reads <= serve_reads_max);
}

pub fn absorb(session: *Session, bytes: []const u8) void {
    var reader = wire.Reader{ .bytes = bytes };

    while (reader.remaining() >= wire.header_bytes) {
        const header = reader.read_header() catch return;
        const body = header.size - wire.header_bytes;
        const start = reader.offset;

        if (header.object == session.device) {
            apply_device(session, header.opcode, &reader);
        }

        reader.offset = start;
        reader.skip(body) catch return;
    }
}

fn apply_device(session: *Session, opcode: u16, reader: *wire.Reader) void {
    switch (opcode) {
        event_device_data_offer => {
            session.offer = reader.read_u32() catch return;
        },
        event_device_selection => {
            session.selection = reader.read_u32() catch return;
        },
        else => {},
    }
}

const testing = std.testing;

test "a closed session reports itself closed" {
    var session = Session{};

    try testing.expect(!session.is_open());

    session.close();

    try testing.expectEqual(@as(u32, 0), session.manager);
}

test "device events populate the offer and selection ids" {
    var session = Session{ .device = 5 };

    var writer = wire.Writer{};

    writer.begin(5);
    writer.put_u32(11);
    writer.seal(event_device_data_offer);

    absorb(&session, writer.finish());

    try testing.expectEqual(@as(u32, 11), session.offer);

    writer = wire.Writer{};

    writer.begin(5);
    writer.put_u32(11);
    writer.seal(event_device_selection);

    absorb(&session, writer.finish());

    try testing.expectEqual(@as(u32, 11), session.selection);
}

test "events for other objects are ignored" {
    var session = Session{ .device = 5 };

    var writer = wire.Writer{};

    writer.begin(9);
    writer.put_u32(11);
    writer.seal(event_device_selection);

    absorb(&session, writer.finish());

    try testing.expectEqual(@as(u32, 0), session.selection);
}

test "a send event is recognised only for the active source" {
    const session = Session{ .source = 7 };

    var writer = wire.Writer{};

    writer.begin(7);
    try writer.put_string(mime_text);
    writer.seal(event_source_send);

    try testing.expect(is_send_event(&session, writer.finish()));

    var other = wire.Writer{};

    other.begin(8);
    try other.put_string(mime_text);
    other.seal(event_source_send);

    try testing.expect(!is_send_event(&session, other.finish()));
}

test "opening against an empty path fails before any protocol work" {
    var session = Session{};

    try testing.expectError(client.Error.NoDisplay, open(&session, ""));
}
