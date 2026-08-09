const std = @import("std");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

pub const SCM_RIGHTS: i32 = 1;
pub const SOL_SOCKET: i32 = 1;

pub const control_bytes: usize = 24;
pub const header_bytes: usize = 16;
pub const align_bytes: usize = @sizeOf(usize);

pub const Error = error{
    SendFailed,
    ReceiveFailed,
    NoDescriptor,
    PipeFailed,
};

const Cmsghdr = extern struct {
    len: usize,
    level: i32,
    kind: i32,
};

comptime {
    assert(@sizeOf(Cmsghdr) == header_bytes);
    assert(align_bytes == 8);
    assert(control_bytes == header_bytes + align_up(@sizeOf(i32)));
}

pub fn align_up(size: usize) usize {
    const result = (size + align_bytes - 1) & ~(align_bytes - 1);

    assert(result >= size);
    assert(result % align_bytes == 0);

    return result;
}

pub fn send_with_fd(socket: posix.fd_t, bytes: []const u8, descriptor: posix.fd_t) Error!void {
    assert(socket >= 0);
    assert(descriptor >= 0);
    assert(bytes.len > 0);

    var control: [control_bytes]u8 align(align_bytes) = @splat(0);
    const header: *Cmsghdr = @ptrCast(@alignCast(&control));

    header.len = header_bytes + @sizeOf(i32);
    header.level = SOL_SOCKET;
    header.kind = SCM_RIGHTS;

    @memcpy(control[header_bytes..][0..@sizeOf(i32)], std.mem.asBytes(&descriptor));

    var vector = [_]posix.iovec_const{.{ .base = bytes.ptr, .len = bytes.len }};

    const message = linux.msghdr_const{
        .name = null,
        .namelen = 0,
        .iov = &vector,
        .iovlen = 1,
        .control = &control,
        .controllen = control_bytes,
        .flags = 0,
    };

    const sent = linux.sendmsg(socket, &message, 0);

    if (posix.errno(sent) != .SUCCESS) {
        return Error.SendFailed;
    }
}

pub fn receive_with_fd(socket: posix.fd_t, buffer: []u8, descriptor: *posix.fd_t) Error!usize {
    assert(socket >= 0);
    assert(buffer.len > 0);

    var control: [control_bytes]u8 align(align_bytes) = @splat(0);
    var vector = [_]posix.iovec{.{ .base = buffer.ptr, .len = buffer.len }};

    var message = linux.msghdr{
        .name = null,
        .namelen = 0,
        .iov = &vector,
        .iovlen = 1,
        .control = &control,
        .controllen = control_bytes,
        .flags = 0,
    };

    const received = linux.recvmsg(socket, &message, 0);

    if (posix.errno(received) != .SUCCESS) {
        return Error.ReceiveFailed;
    }

    descriptor.* = extract(&control, message.controllen);

    return @intCast(received);
}

fn extract(control: *const [control_bytes]u8, length: usize) posix.fd_t {
    if (length < header_bytes + @sizeOf(i32)) {
        return -1;
    }

    const header: *const Cmsghdr = @ptrCast(@alignCast(control));

    if (header.level != SOL_SOCKET or header.kind != SCM_RIGHTS) {
        return -1;
    }

    if (header.len < header_bytes + @sizeOf(i32)) {
        return -1;
    }

    var descriptor: i32 = -1;

    @memcpy(std.mem.asBytes(&descriptor), control[header_bytes..][0..@sizeOf(i32)]);

    return descriptor;
}

pub fn make_pipe(read_end: *posix.fd_t, write_end: *posix.fd_t) Error!void {
    var pair: [2]i32 = .{ -1, -1 };
    const status = linux.pipe2(&pair, .{ .CLOEXEC = true });

    if (posix.errno(status) != .SUCCESS) {
        return Error.PipeFailed;
    }

    read_end.* = pair[0];
    write_end.* = pair[1];

    assert(read_end.* >= 0);
    assert(write_end.* >= 0);
}

pub fn close(descriptor: posix.fd_t) void {
    if (descriptor < 0) {
        return;
    }

    _ = linux.close(descriptor);
}

const testing = std.testing;

test "align_up rounds to the pointer word" {
    try testing.expectEqual(@as(usize, 0), align_up(0));
    try testing.expectEqual(@as(usize, 8), align_up(1));
    try testing.expectEqual(@as(usize, 8), align_up(8));
    try testing.expectEqual(@as(usize, 16), align_up(9));
}

test "an empty control block yields no descriptor" {
    const control: [control_bytes]u8 align(align_bytes) = @splat(0);

    try testing.expectEqual(@as(posix.fd_t, -1), extract(&control, 0));
    try testing.expectEqual(@as(posix.fd_t, -1), extract(&control, control_bytes));
}

test "a descriptor round trips over a socket pair" {
    var pair: [2]i32 = .{ -1, -1 };
    const status = linux.socketpair(linux.AF.UNIX, linux.SOCK.STREAM, 0, &pair);

    if (posix.errno(status) != .SUCCESS) {
        return error.SocketPairUnavailable;
    }
    defer close(pair[0]);
    defer close(pair[1]);

    var read_end: posix.fd_t = -1;
    var write_end: posix.fd_t = -1;

    try make_pipe(&read_end, &write_end);
    defer close(read_end);

    try send_with_fd(pair[0], "nimble", write_end);

    close(write_end);

    var buffer: [16]u8 = undefined;
    var received: posix.fd_t = -1;

    const size = try receive_with_fd(pair[1], &buffer, &received);
    defer close(received);

    try testing.expectEqual(@as(usize, 6), size);
    try testing.expectEqualStrings("nimble", buffer[0..size]);
    try testing.expect(received >= 0);
}

test "a descriptor received over a socket pair is usable" {
    var pair: [2]i32 = .{ -1, -1 };
    const status = linux.socketpair(linux.AF.UNIX, linux.SOCK.STREAM, 0, &pair);

    if (posix.errno(status) != .SUCCESS) {
        return error.SocketPairUnavailable;
    }
    defer close(pair[0]);
    defer close(pair[1]);

    var read_end: posix.fd_t = -1;
    var write_end: posix.fd_t = -1;

    try make_pipe(&read_end, &write_end);
    defer close(read_end);

    try send_with_fd(pair[0], "x", write_end);

    close(write_end);

    var buffer: [4]u8 = undefined;
    var received: posix.fd_t = -1;

    _ = try receive_with_fd(pair[1], &buffer, &received);
    defer close(received);

    const payload = "clipboard";
    const written = linux.write(received, payload, payload.len);

    try testing.expectEqual(@as(usize, payload.len), written);

    var readback: [16]u8 = undefined;
    const size = try posix.read(read_end, &readback);

    try testing.expectEqualStrings(payload, readback[0..size]);
}
