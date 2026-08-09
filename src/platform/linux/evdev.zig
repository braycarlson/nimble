const std = @import("std");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

pub const EV_SYN: u16 = 0x00;
pub const EV_KEY: u16 = 0x01;
pub const EV_REL: u16 = 0x02;
pub const EV_ABS: u16 = 0x03;
pub const EV_MSC: u16 = 0x04;

pub const SYN_REPORT: u16 = 0;
pub const SYN_DROPPED: u16 = 3;

pub const MSC_SCAN: u16 = 0x04;

pub const REL_X: u16 = 0x00;
pub const REL_Y: u16 = 0x01;
pub const REL_HWHEEL: u16 = 0x06;
pub const REL_WHEEL: u16 = 0x08;
pub const REL_MISC: u16 = 0x09;

pub const ABS_X: u16 = 0x00;
pub const ABS_Y: u16 = 0x01;
pub const ABS_RANGE_MAX: i32 = 65535;

pub const BTN_LEFT: u16 = 0x110;
pub const BTN_RIGHT: u16 = 0x111;
pub const BTN_MIDDLE: u16 = 0x112;
pub const BTN_SIDE: u16 = 0x113;
pub const BTN_EXTRA: u16 = 0x114;

pub const KEY_MAX: u16 = 0x2FF;
pub const KEY_BYTES: u16 = (KEY_MAX / 8) + 1;
pub const REL_MAX: u16 = 0x0F;
pub const REL_BYTES: u16 = (REL_MAX / 8) + 1;
pub const NAME_BYTES: u16 = 256;

pub const value_up: i32 = 0;
pub const value_down: i32 = 1;
pub const value_repeat: i32 = 2;

pub const Error = error{
    DeviceUnreadable,
    GrabFailed,
    QueryFailed,
    ReadFailed,
};

pub const BUS_VIRTUAL: u16 = 0x06;

pub const InputId = extern struct {
    bustype: u16,
    vendor: u16,
    product: u16,
    version: u16,

    pub fn eql(id: *const InputId, other: *const InputId) bool {
        const bus = id.bustype == other.bustype;
        const vendor = id.vendor == other.vendor;
        const product = id.product == other.product;
        const version = id.version == other.version;

        return bus and vendor and product and version;
    }
};

pub const Event = extern struct {
    time: linux.timeval,
    type: u16,
    code: u16,
    value: i32,

    pub fn is_key(event: *const Event) bool {
        return event.type == EV_KEY;
    }

    pub fn is_press(event: *const Event) bool {
        assert(event.type == EV_KEY);

        return event.value == value_down or event.value == value_repeat;
    }
};

comptime {
    assert(@sizeOf(Event) == 24);
    assert(KEY_BYTES == 96);
    assert(EV_KEY == 1);
}

const EVIOCGID = linux.IOCTL.IOR('E', 0x02, InputId);
const EVIOCGRAB = linux.IOCTL.IOW('E', 0x90, i32);
const EVIOCGNAME = linux.IOCTL.IOR('E', 0x06, [NAME_BYTES]u8);
const EVIOCGKEY = linux.IOCTL.IOR('E', 0x18, [KEY_BYTES]u8);
const EVIOCGBIT_KEY = linux.IOCTL.IOR('E', 0x20 + @as(u8, @intCast(EV_KEY)), [KEY_BYTES]u8);
const EVIOCGBIT_REL = linux.IOCTL.IOR('E', 0x20 + @as(u8, @intCast(EV_REL)), [REL_BYTES]u8);

pub fn open_read(path: [*:0]const u8) Error!posix.fd_t {
    const flags = posix.O{ .ACCMODE = .RDONLY, .NONBLOCK = true, .CLOEXEC = true };

    return posix.openatZ(posix.AT.FDCWD, path, flags, 0) catch Error.DeviceUnreadable;
}

pub fn close(fd: posix.fd_t) void {
    assert(fd >= 0);

    _ = linux.close(fd);
}

pub fn grab(fd: posix.fd_t) Error!void {
    assert(fd >= 0);

    const status = linux.ioctl(fd, EVIOCGRAB, 1);

    if (posix.errno(status) != .SUCCESS) {
        return Error.GrabFailed;
    }
}

pub fn ungrab(fd: posix.fd_t) void {
    assert(fd >= 0);

    _ = linux.ioctl(fd, EVIOCGRAB, 0);
}

pub fn read_events(fd: posix.fd_t, buffer: []Event) Error!usize {
    assert(fd >= 0);
    assert(buffer.len > 0);

    const bytes = std.mem.sliceAsBytes(buffer);
    const size = linux.read(fd, bytes.ptr, bytes.len);

    switch (posix.errno(size)) {
        .SUCCESS => {},
        .AGAIN => return 0,
        .INTR => return 0,

        else => return Error.ReadFailed,
    }

    assert(size % @sizeOf(Event) == 0);

    return size / @sizeOf(Event);
}

pub fn key_bits(fd: posix.fd_t, bits: *[KEY_BYTES]u8) Error!void {
    assert(fd >= 0);

    const status = linux.ioctl(fd, EVIOCGBIT_KEY, @intFromPtr(bits));

    if (posix.errno(status) != .SUCCESS) {
        return Error.QueryFailed;
    }
}

pub fn rel_bits(fd: posix.fd_t, bits: *[REL_BYTES]u8) Error!void {
    assert(fd >= 0);

    const status = linux.ioctl(fd, EVIOCGBIT_REL, @intFromPtr(bits));

    if (posix.errno(status) != .SUCCESS) {
        return Error.QueryFailed;
    }
}

pub fn key_state(fd: posix.fd_t, bits: *[KEY_BYTES]u8) Error!void {
    assert(fd >= 0);

    const status = linux.ioctl(fd, EVIOCGKEY, @intFromPtr(bits));

    if (posix.errno(status) != .SUCCESS) {
        return Error.QueryFailed;
    }
}

pub fn identity(fd: posix.fd_t) Error!InputId {
    assert(fd >= 0);

    var result: InputId = .{ .bustype = 0, .vendor = 0, .product = 0, .version = 0 };
    const status = linux.ioctl(fd, EVIOCGID, @intFromPtr(&result));

    if (posix.errno(status) != .SUCCESS) {
        return Error.QueryFailed;
    }

    return result;
}

pub fn name(fd: posix.fd_t, buffer: *[NAME_BYTES]u8) Error![]const u8 {
    assert(fd >= 0);

    const status = linux.ioctl(fd, EVIOCGNAME, @intFromPtr(buffer));

    if (posix.errno(status) != .SUCCESS) {
        return Error.QueryFailed;
    }

    const end = std.mem.indexOfScalar(u8, buffer, 0) orelse NAME_BYTES;

    assert(end <= NAME_BYTES);

    return buffer[0..end];
}

pub fn bit_is_set(bits: []const u8, index: u16) bool {
    const byte = index / 8;
    const offset: u3 = @truncate(index % 8);

    if (byte >= bits.len) {
        return false;
    }

    assert(byte < bits.len);

    return (bits[byte] & (@as(u8, 1) << offset)) != 0;
}

const testing = std.testing;

test "the event layout matches the kernel ABI" {
    try testing.expectEqual(@as(usize, 24), @sizeOf(Event));
    try testing.expectEqual(@as(usize, 16), @offsetOf(Event, "type"));
    try testing.expectEqual(@as(usize, 18), @offsetOf(Event, "code"));
    try testing.expectEqual(@as(usize, 20), @offsetOf(Event, "value"));
}

test "bit_is_set reads a capability bitmap" {
    var bits = [_]u8{0} ** 8;

    bits[0] = 0b0000_0101;
    bits[3] = 0b1000_0000;

    try testing.expect(bit_is_set(&bits, 0));
    try testing.expect(!bit_is_set(&bits, 1));
    try testing.expect(bit_is_set(&bits, 2));
    try testing.expect(bit_is_set(&bits, 31));
    try testing.expect(!bit_is_set(&bits, 30));
    try testing.expect(!bit_is_set(&bits, 999));
}

test "ioctl request numbers match the kernel encoding" {
    try testing.expectEqual(@as(u32, 0x40044590), EVIOCGRAB);
    try testing.expectEqual(@as(u32, 0x81004506), EVIOCGNAME);
    try testing.expectEqual(@as(u32, 0x80604518), EVIOCGKEY);
    try testing.expectEqual(@as(u32, 0x80084502), EVIOCGID);
}

test "an input id compares every field" {
    const base = InputId{ .bustype = 6, .vendor = 1, .product = 2, .version = 3 };
    const same = InputId{ .bustype = 6, .vendor = 1, .product = 2, .version = 3 };
    const other = InputId{ .bustype = 6, .vendor = 1, .product = 9, .version = 3 };

    try testing.expectEqual(@as(usize, 8), @sizeOf(InputId));
    try testing.expect(base.eql(&same));
    try testing.expect(!base.eql(&other));
}
