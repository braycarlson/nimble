const std = @import("std");

const evdev = @import("evdev.zig");
const keycode = @import("../../keycode.zig");
const mapping = @import("keycode.zig");
const time = @import("time.zig");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

const Keycode = keycode.Keycode;

pub const path = "/dev/uinput";
pub const name_bytes_max: usize = 80;
pub const name_prefix = "nimble";
pub const pid_digits_max: usize = 10;
pub const stamp_digits_max: usize = 19;
pub const vendor: u16 = 0x6e6d;
pub const product_keyboard: u16 = 0x0001;
pub const product_mouse: u16 = 0x0002;
pub const version: u16 = 1;

pub const Error = error{
    DeviceCreateFailed,
    Inaccessible,
    SetupFailed,
    WriteFailed,
};

const UI_SET_EVBIT = linux.IOCTL.IOW('U', 100, i32);
const UI_SET_KEYBIT = linux.IOCTL.IOW('U', 101, i32);
const UI_SET_RELBIT = linux.IOCTL.IOW('U', 102, i32);
const UI_SET_MSCBIT = linux.IOCTL.IOW('U', 104, i32);
const UI_DEV_CREATE = linux.IOCTL.IO('U', 1);
const UI_DEV_DESTROY = linux.IOCTL.IO('U', 2);
const UI_DEV_SETUP = linux.IOCTL.IOW('U', 3, SetupInfo);

const InputId = evdev.InputId;

const SetupInfo = extern struct {
    id: InputId,
    name: [name_bytes_max]u8,
    ff_effects_max: u32,
};

pub const Kind = enum(u8) {
    keyboard,
    mouse,

    pub fn label(kind: Kind) []const u8 {
        return switch (kind) {
            .keyboard => name_prefix ++ " virtual keyboard",
            .mouse => name_prefix ++ " virtual mouse",
        };
    }

    pub fn product(kind: Kind) u16 {
        return switch (kind) {
            .keyboard => product_keyboard,
            .mouse => product_mouse,
        };
    }
};

pub const Role = enum(u8) {
    relay,
    inject,

    pub fn word(role: Role) []const u8 {
        return switch (role) {
            .relay => "relay",
            .inject => "inject",
        };
    }
};

pub const Label = struct {
    pid: u32,
    stamp_ms: i64,
    relay: bool,
};

comptime {
    const budget = 1 + pid_digits_max + 1 + stamp_digits_max + 1 + Role.inject.word().len;

    assert(Kind.keyboard.label().len + budget < name_bytes_max);
    assert(Kind.mouse.label().len + budget < name_bytes_max);
    assert(Role.relay.word().len <= Role.inject.word().len);
}

pub fn identity_of(kind: Kind) InputId {
    return InputId{
        .bustype = evdev.BUS_VIRTUAL,
        .vendor = vendor,
        .product = kind.product(),
        .version = version,
    };
}

pub fn is_family(id: *const InputId) bool {
    const keyboard = identity_of(.keyboard);
    const mouse = identity_of(.mouse);

    return id.eql(&keyboard) or id.eql(&mouse);
}

pub fn pid_self() u32 {
    const pid = linux.getpid();

    assert(pid > 0);

    return @intCast(pid);
}

pub fn parse_label(label: []const u8) ?Label {
    assert(label.len <= evdev.NAME_BYTES);

    const role_space = std.mem.lastIndexOfScalar(u8, label, ' ') orelse return null;
    const role = label[role_space + 1 ..];
    const relay = std.mem.eql(u8, role, Role.relay.word());
    const inject = std.mem.eql(u8, role, Role.inject.word());

    if (!relay and !inject) {
        return null;
    }

    const head = label[0..role_space];
    const stamp_space = std.mem.lastIndexOfScalar(u8, head, ' ') orelse return null;
    const stamp_digits = head[stamp_space + 1 ..];

    if (stamp_digits.len == 0 or stamp_digits.len > stamp_digits_max) {
        return null;
    }

    const rest = head[0..stamp_space];
    const pid_space = std.mem.lastIndexOfScalar(u8, rest, ' ') orelse return null;
    const pid_digits = rest[pid_space + 1 ..];

    if (pid_digits.len == 0 or pid_digits.len > pid_digits_max) {
        return null;
    }

    const stamp_ms = std.fmt.parseInt(i64, stamp_digits, 10) catch return null;
    const pid = std.fmt.parseInt(u32, pid_digits, 10) catch return null;

    if (stamp_ms < 0) {
        return null;
    }

    return Label{ .pid = pid, .stamp_ms = stamp_ms, .relay = relay };
}

pub const Device = struct {
    fd: posix.fd_t = -1,
    kind: Kind = .keyboard,
    stamp_ms: i64 = 0,
    pressed: [evdev.KEY_BYTES]u8 = @splat(0),

    pub fn is_open(device: *const Device) bool {
        return device.fd >= 0;
    }

    pub fn is_down(device: *const Device, code: u16) bool {
        if (code > evdev.KEY_MAX) {
            return false;
        }

        return evdev.bit_is_set(&device.pressed, code);
    }

    pub fn emit(device: *Device, kind: u16, code: u16, value: i32) Error!void {
        assert(device.is_open());

        const event = evdev.Event{
            .time = .{ .sec = 0, .usec = 0 },
            .type = kind,
            .code = code,
            .value = value,
        };

        const bytes = std.mem.asBytes(&event);
        const written = linux.write(device.fd, bytes.ptr, bytes.len);

        if (posix.errno(written) != .SUCCESS) {
            return Error.WriteFailed;
        }

        if (kind == evdev.EV_KEY and code <= evdev.KEY_MAX) {
            device.track(code, value);
        }
    }

    fn track(device: *Device, code: u16, value: i32) void {
        assert(code <= evdev.KEY_MAX);

        const byte = code / 8;
        const bit = @as(u8, 1) << @truncate(code % 8);

        if (value == evdev.value_up) {
            device.pressed[byte] &= ~bit;
        } else {
            device.pressed[byte] |= bit;
        }
    }

    pub fn sync(device: *Device) Error!void {
        return device.emit(evdev.EV_SYN, evdev.SYN_REPORT, 0);
    }

    pub fn release_pressed(device: *Device) void {
        if (!device.is_open()) {
            return;
        }

        var code: u16 = 0;
        var wrote = false;

        while (code <= evdev.KEY_MAX) : (code += 1) {
            if (!evdev.bit_is_set(&device.pressed, code)) {
                continue;
            }

            device.emit(evdev.EV_KEY, code, evdev.value_up) catch return;

            wrote = true;
        }

        assert(code == evdev.KEY_MAX + 1);

        if (wrote) {
            device.sync() catch return;
        }
    }

    pub fn key(device: *Device, code: Keycode, down: bool) Error!void {
        assert(device.kind == .keyboard);

        const native = mapping.to_native(code) orelse return;
        const value: i32 = if (down) evdev.value_down else evdev.value_up;

        try device.emit(evdev.EV_KEY, native, value);
        try device.sync();
    }

    pub fn button(device: *Device, code: u16, down: bool) Error!void {
        assert(device.kind == .mouse);

        const value: i32 = if (down) evdev.value_down else evdev.value_up;

        try device.emit(evdev.EV_KEY, code, value);
        try device.sync();
    }

    pub fn move_relative(device: *Device, dx: i32, dy: i32) Error!void {
        assert(device.kind == .mouse);

        if (dx != 0) {
            try device.emit(evdev.EV_REL, evdev.REL_X, dx);
        }

        if (dy != 0) {
            try device.emit(evdev.EV_REL, evdev.REL_Y, dy);
        }

        try device.sync();
    }

    pub fn move_absolute(device: *Device, x: i32, y: i32) Error!void {
        assert(device.kind == .mouse);
        assert(x >= 0);
        assert(y >= 0);

        try device.emit(evdev.EV_ABS, evdev.ABS_X, x);
        try device.emit(evdev.EV_ABS, evdev.ABS_Y, y);
        try device.sync();
    }

    pub fn scroll(device: *Device, vertical: i32, horizontal: i32) Error!void {
        assert(device.kind == .mouse);

        if (vertical != 0) {
            try device.emit(evdev.EV_REL, evdev.REL_WHEEL, vertical);
        }

        if (horizontal != 0) {
            try device.emit(evdev.EV_REL, evdev.REL_HWHEEL, horizontal);
        }

        try device.sync();
    }

    pub fn destroy(device: *Device) void {
        if (!device.is_open()) {
            return;
        }

        _ = linux.ioctl(device.fd, UI_DEV_DESTROY, 0);
        _ = linux.close(device.fd);

        device.fd = -1;
        device.pressed = @splat(0);

        assert(!device.is_open());
    }
};

pub fn create(kind: Kind, role: Role) Error!Device {
    const flags = posix.O{ .ACCMODE = .WRONLY, .NONBLOCK = true, .CLOEXEC = true };

    const fd = posix.openatZ(posix.AT.FDCWD, path, flags, 0) catch {
        return Error.Inaccessible;
    };

    errdefer _ = linux.close(fd);

    const stamp_ms = time.now_ms();

    assert(stamp_ms >= 0);

    try enable(fd, kind);
    try setup(fd, kind, role, stamp_ms);

    const status = linux.ioctl(fd, UI_DEV_CREATE, 0);

    if (posix.errno(status) != .SUCCESS) {
        return Error.DeviceCreateFailed;
    }

    return Device{ .fd = fd, .kind = kind, .stamp_ms = stamp_ms };
}

fn enable(fd: posix.fd_t, kind: Kind) Error!void {
    assert(fd >= 0);

    try set_bit(fd, UI_SET_EVBIT, evdev.EV_KEY);
    try set_bit(fd, UI_SET_EVBIT, evdev.EV_SYN);

    switch (kind) {
        .keyboard => try enable_keys(fd),
        .mouse => try enable_pointer(fd),
    }
}

fn enable_keys(fd: posix.fd_t) Error!void {
    assert(fd >= 0);

    inline for (@typeInfo(Keycode).@"enum".fields) |field| {
        const code: Keycode = @enumFromInt(field.value);

        if (mapping.to_native(code)) |native| {
            try set_bit(fd, UI_SET_KEYBIT, native);
        }
    }

    try set_bit(fd, UI_SET_EVBIT, evdev.EV_MSC);
    try set_bit(fd, UI_SET_MSCBIT, evdev.MSC_SCAN);
}

fn enable_pointer(fd: posix.fd_t) Error!void {
    assert(fd >= 0);

    const buttons = [_]u16{
        evdev.BTN_LEFT,
        evdev.BTN_RIGHT,
        evdev.BTN_MIDDLE,
        evdev.BTN_SIDE,
        evdev.BTN_EXTRA,
    };

    for (buttons) |code| {
        try set_bit(fd, UI_SET_KEYBIT, code);
    }

    try set_bit(fd, UI_SET_EVBIT, evdev.EV_REL);
    try set_bit(fd, UI_SET_RELBIT, evdev.REL_X);
    try set_bit(fd, UI_SET_RELBIT, evdev.REL_Y);
    try set_bit(fd, UI_SET_RELBIT, evdev.REL_WHEEL);
    try set_bit(fd, UI_SET_RELBIT, evdev.REL_HWHEEL);
}

fn set_bit(fd: posix.fd_t, request: u32, value: u16) Error!void {
    assert(fd >= 0);

    const status = linux.ioctl(fd, request, value);

    if (posix.errno(status) != .SUCCESS) {
        return Error.SetupFailed;
    }
}

fn setup(fd: posix.fd_t, kind: Kind, role: Role, stamp_ms: i64) Error!void {
    assert(fd >= 0);
    assert(stamp_ms >= 0);

    var info = SetupInfo{
        .id = identity_of(kind),
        .name = @splat(0),
        .ff_effects_max = 0,
    };

    const written = std.fmt.bufPrint(&info.name, "{s} {d} {d} {s}", .{
        kind.label(),
        pid_self(),
        stamp_ms,
        role.word(),
    }) catch return Error.SetupFailed;

    assert(written.len < name_bytes_max);

    const parsed = parse_label(written) orelse return Error.SetupFailed;

    assert(parsed.pid == pid_self());
    assert(parsed.stamp_ms == stamp_ms);
    assert(parsed.relay == (role == .relay));

    const status = linux.ioctl(fd, UI_DEV_SETUP, @intFromPtr(&info));

    if (posix.errno(status) != .SUCCESS) {
        return Error.SetupFailed;
    }
}

const testing = std.testing;

test "uinput ioctl request numbers match the kernel encoding" {
    try testing.expectEqual(@as(u32, 0x40045564), UI_SET_EVBIT);
    try testing.expectEqual(@as(u32, 0x40045565), UI_SET_KEYBIT);
    try testing.expectEqual(@as(u32, 0x40045566), UI_SET_RELBIT);
    try testing.expectEqual(@as(u32, 0x5501), UI_DEV_CREATE);
    try testing.expectEqual(@as(u32, 0x5502), UI_DEV_DESTROY);
}

test "the setup info matches the kernel layout" {
    try testing.expectEqual(@as(usize, 8), @sizeOf(InputId));
    try testing.expectEqual(@as(usize, 0), @offsetOf(SetupInfo, "id"));
    try testing.expectEqual(@as(usize, 8), @offsetOf(SetupInfo, "name"));
    try testing.expectEqual(@as(usize, 88), @offsetOf(SetupInfo, "ff_effects_max"));
}

test "a closed virtual device reports itself closed" {
    const device = Device{};

    try testing.expect(!device.is_open());
    try testing.expect(!device.is_down(30));
}

test "nimble recognises the identity it stamps on its own devices" {
    const keyboard = identity_of(.keyboard);
    const mouse = identity_of(.mouse);

    try testing.expect(is_family(&keyboard));
    try testing.expect(is_family(&mouse));
    try testing.expectEqual(evdev.BUS_VIRTUAL, keyboard.bustype);
    try testing.expect(keyboard.product != mouse.product);
}

test "a foreign virtual device is not mistaken for nimble" {
    const foreign = evdev.InputId{
        .bustype = evdev.BUS_VIRTUAL,
        .vendor = vendor +% 1,
        .product = product_keyboard,
        .version = version,
    };

    try testing.expect(!is_family(&foreign));
}

test "parse_label reads pid, stamp, and role back out of a device label" {
    const relay = parse_label("nimble virtual keyboard 1234 567890 relay") orelse
        return error.MissingLabel;

    try testing.expectEqual(@as(u32, 1234), relay.pid);
    try testing.expectEqual(@as(i64, 567890), relay.stamp_ms);
    try testing.expect(relay.relay);

    const inject = parse_label("nimble virtual mouse 1 0 inject") orelse
        return error.MissingLabel;

    try testing.expectEqual(@as(u32, 1), inject.pid);
    try testing.expectEqual(@as(i64, 0), inject.stamp_ms);
    try testing.expect(!inject.relay);
}

test "parse_label rejects labels without the stamped structure" {
    try testing.expect(parse_label("nimble virtual keyboard") == null);
    try testing.expect(parse_label("nimble virtual keyboard 1234") == null);
    try testing.expect(parse_label("nimble virtual keyboard 1234 5678") == null);
    try testing.expect(parse_label("nimble virtual keyboard 1234 5678 pilot") == null);
    try testing.expect(parse_label("nimble virtual keyboard 12x4 5678 relay") == null);
    try testing.expect(parse_label("nimble virtual keyboard 1234 56x8 relay") == null);
    try testing.expect(parse_label("nimble") == null);
    try testing.expect(parse_label("") == null);
    try testing.expect(parse_label("relay") == null);
}

test "the process pid is stable and embeddable" {
    const first = pid_self();
    const again = pid_self();

    try testing.expectEqual(first, again);
    try testing.expect(first > 0);
}

test "device labels carry the nimble prefix and fit the setup buffer" {
    try testing.expect(std.mem.startsWith(u8, Kind.keyboard.label(), name_prefix));
    try testing.expect(std.mem.startsWith(u8, Kind.mouse.label(), name_prefix));
    try testing.expect(Kind.keyboard.label().len < name_bytes_max);
    try testing.expect(Kind.mouse.label().len < name_bytes_max);
}

test "a device tracks which keys it holds down" {
    var device = Device{};

    device.track(30, evdev.value_down);

    try testing.expect(device.is_down(30));
    try testing.expect(!device.is_down(31));

    device.track(30, evdev.value_repeat);

    try testing.expect(device.is_down(30));

    device.track(30, evdev.value_up);

    try testing.expect(!device.is_down(30));
    try testing.expect(!device.is_down(evdev.KEY_MAX + 1));
}
