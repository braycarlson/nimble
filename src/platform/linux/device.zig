const std = @import("std");

const evdev = @import("evdev.zig");
const uinput = @import("uinput.zig");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

pub const device_count_max: u8 = 32;
pub const device_index_max: u8 = 64;
pub const path_bytes_max: u16 = 64;
pub const directory = "/dev/input";
pub const uinput_path = "/dev/uinput";

pub const Error = error{
    InputGroupMissing,
    UinputInaccessible,
    DirectoryUnreadable,
    TooManyDevices,
};

pub const Kind = enum(u8) {
    keyboard,
    mouse,
    other,

    pub fn is_valid(kind: Kind) bool {
        return @intFromEnum(kind) <= 2;
    }
};

pub const Origin = enum(u8) {
    direct,
    own,
    sibling,

    pub fn is_valid(origin: Origin) bool {
        return @intFromEnum(origin) <= 2;
    }
};

pub const Prune = enum(u8) {
    not_grabbed,
    sibling,
};

pub const Order = struct {
    stamp_ms: i64 = 0,
    pid: u32 = 0,

    pub fn precedes(order: Order, other: Order) bool {
        if (order.stamp_ms != other.stamp_ms) {
            return order.stamp_ms < other.stamp_ms;
        }

        return order.pid < other.pid;
    }
};

pub const Device = struct {
    fd: posix.fd_t = -1,
    kind: Kind = .other,
    origin: Origin = .direct,
    grabbed: bool = false,
    virtual: bool = false,
    relay: bool = false,
    stamp_ms: i64 = 0,
    pid: u32 = 0,
    path: [path_bytes_max]u8 = @splat(0),
    path_len: u16 = 0,

    pub fn is_open(device: *const Device) bool {
        return device.fd >= 0;
    }

    pub fn name(device: *const Device) []const u8 {
        assert(device.path_len <= path_bytes_max);

        return device.path[0..device.path_len];
    }

    pub fn order(device: *const Device) Order {
        return Order{ .stamp_ms = device.stamp_ms, .pid = device.pid };
    }
};

pub const List = struct {
    devices: [device_count_max]Device = @splat(.{}),
    count: u8 = 0,

    pub fn is_valid(list: *const List) bool {
        return list.count <= device_count_max;
    }

    pub fn find(list: *const List, fd: posix.fd_t) ?*const Device {
        assert(list.is_valid());

        if (fd < 0) {
            return null;
        }

        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            if (list.devices[index].fd == fd) {
                return &list.devices[index];
            }
        }

        return null;
    }

    pub fn count_of(list: *const List, kind: Kind) u8 {
        assert(list.is_valid());

        var total: u8 = 0;
        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            if (list.devices[index].kind == kind) {
                total += 1;
            }
        }

        assert(total <= list.count);

        return total;
    }

    pub fn count_of_origin(list: *const List, kind: Kind, origin: Origin) u8 {
        assert(list.is_valid());

        var total: u8 = 0;
        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            const device = &list.devices[index];

            if (device.kind == kind and device.origin == origin) {
                total += 1;
            }
        }

        assert(total <= list.count);

        return total;
    }

    pub fn count_grabbed(list: *const List, kind: Kind) u8 {
        assert(list.is_valid());

        var total: u8 = 0;
        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            const device = &list.devices[index];

            if (device.kind == kind and device.grabbed) {
                total += 1;
            }
        }

        assert(total <= list.count);

        return total;
    }

    pub fn count_grabbed_origin(list: *const List, kind: Kind, origin: Origin) u8 {
        assert(list.is_valid());

        var total: u8 = 0;
        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            const device = &list.devices[index];

            if (device.kind == kind and device.origin == origin and device.grabbed) {
                total += 1;
            }
        }

        assert(total <= list.count);

        return total;
    }

    pub fn find_path(list: *const List, path: []const u8) ?*const Device {
        assert(list.is_valid());
        assert(path.len > 0);

        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            if (std.mem.eql(u8, list.devices[index].name(), path)) {
                return &list.devices[index];
            }
        }

        return null;
    }

    pub fn close_all(list: *List) void {
        assert(list.is_valid());

        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            const device = &list.devices[index];

            if (!device.is_open()) {
                continue;
            }

            if (device.grabbed) {
                evdev.ungrab(device.fd);
                device.grabbed = false;
            }

            evdev.close(device.fd);
            device.fd = -1;
        }

        list.count = 0;

        assert(list.count == 0);
    }
};

pub const Claim = struct {
    keyboard_fd: posix.fd_t = -1,
    mouse_fd: posix.fd_t = -1,
    keyboard_held: bool = false,
    mouse_held: bool = false,

    pub fn is_valid(claim: *const Claim) bool {
        if (claim.keyboard_held and claim.keyboard_fd < 0) {
            return false;
        }

        if (claim.mouse_held and claim.mouse_fd < 0) {
            return false;
        }

        return true;
    }

    pub fn is_open(claim: *const Claim) bool {
        return claim.keyboard_fd >= 0 and claim.mouse_fd >= 0;
    }
};

comptime {
    assert(device_count_max > 0);
    assert(path_bytes_max > directory.len + 16);
    assert(device_index_max >= device_count_max);
}

pub fn probe_permissions() Error!void {
    const readable = count_readable();

    if (readable == 0) {
        return Error.InputGroupMissing;
    }

    assert(readable > 0);

    const flags = posix.O{ .ACCMODE = .WRONLY, .NONBLOCK = true, .CLOEXEC = true };

    const fd = posix.openatZ(posix.AT.FDCWD, uinput_path, flags, 0) catch {
        return Error.UinputInaccessible;
    };

    _ = linux.close(fd);
}

fn count_readable() u8 {
    var total: u8 = 0;
    var index: u8 = 0;

    while (index < device_index_max and total < device_count_max) : (index += 1) {
        var buffer: [path_bytes_max]u8 = @splat(0);
        const path = build_path(&buffer, index) orelse continue;
        const fd = evdev.open_read(path) catch continue;

        evdev.close(fd);

        total += 1;
    }

    assert(total <= device_count_max);

    return total;
}

pub fn build_path(buffer: *[path_bytes_max]u8, index: u8) ?[*:0]const u8 {
    const written = std.fmt.bufPrint(buffer, "{s}/event{d}", .{ directory, index }) catch {
        return null;
    };

    if (written.len + 1 > path_bytes_max) {
        return null;
    }

    assert(written.len < path_bytes_max);

    buffer[written.len] = 0;

    return @ptrCast(buffer);
}

pub fn scan(list: *List) Error!void {
    assert(list.count == 0);

    var index: u8 = 0;

    while (index < device_index_max) : (index += 1) {
        if (list.count == device_count_max) {
            return Error.TooManyDevices;
        }

        const device = open_at(index) orelse continue;

        list.devices[list.count] = device;
        list.count += 1;
    }

    assert(list.is_valid());
}

pub fn open_at(index: u8) ?Device {
    assert(index < device_index_max);

    var device = Device{};
    const path = build_path(&device.path, index) orelse return null;

    device.path_len = @intCast(std.mem.len(path));
    device.fd = evdev.open_read(path) catch return null;

    const origin = origin_of(device.fd);

    if (origin == .own) {
        evdev.close(device.fd);

        return null;
    }

    device.origin = origin;
    device.kind = classify(device.fd);
    device.virtual = is_virtual(device.fd);

    if (device.kind == .other) {
        evdev.close(device.fd);

        return null;
    }

    annotate(&device);

    return device;
}

fn annotate(device: *Device) void {
    assert(device.is_open());

    if (device.origin != .sibling) {
        return;
    }

    var buffer: [evdev.NAME_BYTES]u8 = @splat(0);
    const label = evdev.name(device.fd, &buffer) catch return;
    const parsed = uinput.parse_label(label) orelse return;

    device.relay = parsed.relay;
    device.stamp_ms = parsed.stamp_ms;
    device.pid = parsed.pid;

    assert(device.stamp_ms >= 0);
}

pub fn origin_of(fd: posix.fd_t) Origin {
    assert(fd >= 0);

    const id = evdev.identity(fd) catch return .direct;

    var buffer: [evdev.NAME_BYTES]u8 = @splat(0);
    const label = evdev.name(fd, &buffer) catch return .direct;

    const family_id = uinput.is_family(&id);
    const family_name = std.mem.startsWith(u8, label, uinput.name_prefix);

    if (!family_id and !family_name) {
        return .direct;
    }

    const parsed = uinput.parse_label(label) orelse return .sibling;

    if (parsed.pid == uinput.pid_self()) {
        return .own;
    }

    return .sibling;
}

pub fn close_dead(list: *List) u8 {
    assert(list.is_valid());

    var kept: u8 = 0;
    var index: u8 = 0;
    var closed: u8 = 0;

    while (index < list.count) : (index += 1) {
        const device = &list.devices[index];

        if (is_alive(device.fd)) {
            list.devices[kept] = device.*;
            kept += 1;

            continue;
        }

        evdev.close(device.fd);

        closed += 1;
    }

    list.count = kept;

    assert(kept + closed == index);
    assert(list.is_valid());

    return closed;
}

fn is_alive(fd: posix.fd_t) bool {
    assert(fd >= 0);

    _ = evdev.identity(fd) catch return false;

    return true;
}

pub fn is_virtual(fd: posix.fd_t) bool {
    assert(fd >= 0);

    const id = evdev.identity(fd) catch return false;

    return id.bustype == evdev.BUS_VIRTUAL;
}

pub fn classify(fd: posix.fd_t) Kind {
    assert(fd >= 0);

    var keys: [evdev.KEY_BYTES]u8 = @splat(0);
    var rels: [evdev.REL_BYTES]u8 = @splat(0);

    evdev.key_bits(fd, &keys) catch return .other;

    const has_letters = evdev.bit_is_set(&keys, 30) and evdev.bit_is_set(&keys, 44);
    const has_escape = evdev.bit_is_set(&keys, 1);

    if (has_letters and has_escape) {
        return .keyboard;
    }

    evdev.rel_bits(fd, &rels) catch return .other;

    const has_motion = evdev.bit_is_set(&rels, evdev.REL_X) and
        evdev.bit_is_set(&rels, evdev.REL_Y);
    const has_button = evdev.bit_is_set(&keys, evdev.BTN_LEFT);

    if (has_motion and has_button) {
        return .mouse;
    }

    return .other;
}

pub fn claim_open(claim: *Claim) void {
    assert(claim.is_valid());

    if (claim.is_open()) {
        return;
    }

    var index: u8 = 0;

    while (index < device_index_max) : (index += 1) {
        if (claim.is_open()) {
            break;
        }

        var buffer: [path_bytes_max]u8 = @splat(0);
        const path = build_path(&buffer, index) orelse continue;
        const fd = evdev.open_read(path) catch continue;

        claim_adopt(claim, fd);
    }

    assert(index <= device_index_max);
    assert(claim.is_valid());
}

fn claim_adopt(claim: *Claim, fd: posix.fd_t) void {
    assert(fd >= 0);

    if (origin_of(fd) != .own) {
        evdev.close(fd);

        return;
    }

    const kind = classify(fd);

    if (kind == .other) {
        evdev.close(fd);

        return;
    }

    const slot = claim_slot(claim, kind);

    if (slot.* >= 0) {
        evdev.close(fd);

        return;
    }

    slot.* = fd;

    assert(slot.* >= 0);
    assert(claim.is_valid());
}

fn claim_slot(claim: *Claim, kind: Kind) *posix.fd_t {
    return switch (kind) {
        .keyboard => &claim.keyboard_fd,
        .mouse => &claim.mouse_fd,
        .other => unreachable,
    };
}

fn claim_flag(claim: *Claim, kind: Kind) *bool {
    return switch (kind) {
        .keyboard => &claim.keyboard_held,
        .mouse => &claim.mouse_held,
        .other => unreachable,
    };
}

pub fn claim_hold(claim: *Claim, kind: Kind) void {
    assert(kind != .other);
    assert(claim.is_valid());

    const fd = claim_slot(claim, kind).*;
    const held = claim_flag(claim, kind);

    if (fd < 0) {
        return;
    }

    if (held.*) {
        return;
    }

    evdev.grab(fd) catch return;

    held.* = true;

    assert(held.*);
    assert(claim.is_valid());
}

pub fn claim_release(claim: *Claim, kind: Kind) void {
    assert(kind != .other);
    assert(claim.is_valid());

    const fd = claim_slot(claim, kind).*;
    const held = claim_flag(claim, kind);

    if (fd < 0) {
        return;
    }

    if (!held.*) {
        return;
    }

    evdev.ungrab(fd);

    held.* = false;

    assert(!held.*);
    assert(claim.is_valid());
}

pub fn claim_close(claim: *Claim) void {
    claim_release(claim, .keyboard);
    claim_release(claim, .mouse);

    if (claim.keyboard_fd >= 0) {
        evdev.close(claim.keyboard_fd);

        claim.keyboard_fd = -1;
    }

    if (claim.mouse_fd >= 0) {
        evdev.close(claim.mouse_fd);

        claim.mouse_fd = -1;
    }

    assert(claim.keyboard_fd < 0);
    assert(claim.mouse_fd < 0);
    assert(claim.is_valid());
}

pub fn is_quiescent(fd: posix.fd_t) bool {
    assert(fd >= 0);

    var bits: [evdev.KEY_BYTES]u8 = @splat(0);

    evdev.key_state(fd, &bits) catch return true;

    for (bits) |byte| {
        if (byte != 0) {
            return false;
        }
    }

    return true;
}

pub fn grab_all(list: *List, kind: Kind, origin: Origin) u8 {
    assert(list.is_valid());
    assert(kind.is_valid());
    assert(origin != .own);

    var grabbed: u8 = 0;
    var index: u8 = 0;

    while (index < list.count) : (index += 1) {
        const device = &list.devices[index];

        if (device.kind != kind or device.origin != origin or device.grabbed) {
            continue;
        }

        if (!grab_quiescent(device.fd)) {
            continue;
        }

        device.grabbed = true;
        grabbed += 1;
    }

    assert(grabbed <= list.count);

    return grabbed;
}

fn grab_quiescent(fd: posix.fd_t) bool {
    assert(fd >= 0);

    if (!is_quiescent(fd)) {
        return false;
    }

    evdev.grab(fd) catch return false;

    if (is_quiescent(fd)) {
        return true;
    }

    evdev.ungrab(fd);

    return false;
}

pub fn grab_chain(list: *List, kind: Kind, own: Order) ?u8 {
    assert(list.is_valid());
    assert(kind.is_valid());
    assert(own.stamp_ms >= 0);

    var tried: [device_count_max]bool = @splat(false);
    var round: u8 = 0;

    while (round < list.count) : (round += 1) {
        const index = chain_best(list, kind, own, &tried) orelse return null;

        assert(index < list.count);

        tried[index] = true;

        const device = &list.devices[index];

        if (!grab_quiescent(device.fd)) {
            continue;
        }

        device.grabbed = true;

        return index;
    }

    assert(round == list.count);

    return null;
}

fn chain_best(list: *const List, kind: Kind, own: Order, tried: *const [device_count_max]bool) ?u8 {
    assert(list.is_valid());

    var best: ?u8 = null;
    var index: u8 = 0;

    while (index < list.count) : (index += 1) {
        const device = &list.devices[index];

        if (tried[index]) {
            continue;
        }

        if (!chain_eligible(device, kind, own)) {
            continue;
        }

        if (best) |current| {
            if (!list.devices[current].order().precedes(device.order())) {
                continue;
            }
        }

        best = index;
    }

    return best;
}

fn chain_eligible(device: *const Device, kind: Kind, own: Order) bool {
    if (device.kind != kind or device.origin != .sibling or device.grabbed) {
        return false;
    }

    if (!device.is_open()) {
        return false;
    }

    if (!device.relay) {
        return false;
    }

    return device.order().precedes(own);
}

pub fn chain_elder_present(list: *const List, kind: Kind, own: Order) bool {
    assert(list.is_valid());
    assert(kind.is_valid());

    var index: u8 = 0;

    while (index < list.count) : (index += 1) {
        const device = &list.devices[index];

        if (device.kind != kind or device.origin != .sibling) {
            continue;
        }

        if (!device.is_open() or !device.relay) {
            continue;
        }

        if (device.order().precedes(own)) {
            return true;
        }
    }

    assert(index == list.count);

    return false;
}

pub fn ungrab_at(list: *List, index: u8) void {
    assert(list.is_valid());
    assert(index < list.count);

    const device = &list.devices[index];

    assert(device.grabbed);
    assert(device.is_open());

    evdev.ungrab(device.fd);

    device.grabbed = false;

    assert(!device.grabbed);
}

pub fn close_where(list: *List, kind: Kind, prune: Prune) u8 {
    assert(list.is_valid());
    assert(kind.is_valid());

    var kept: u8 = 0;
    var index: u8 = 0;
    var closed: u8 = 0;

    while (index < list.count) : (index += 1) {
        const device = &list.devices[index];

        const drop = switch (prune) {
            .not_grabbed => device.kind == kind and !device.grabbed,
            .sibling => device.kind == kind and device.origin == .sibling,
        };

        if (drop) {
            assert(!device.grabbed);

            if (device.is_open()) {
                evdev.close(device.fd);
            }

            closed += 1;

            continue;
        }

        list.devices[kept] = device.*;
        kept += 1;
    }

    list.count = kept;

    assert(kept + closed == index);
    assert(list.is_valid());

    return closed;
}

pub fn ungrab_where(list: *List, kind: Kind, origin: Origin) u8 {
    assert(list.is_valid());
    assert(kind.is_valid());

    var released: u8 = 0;
    var index: u8 = 0;

    while (index < list.count) : (index += 1) {
        const device = &list.devices[index];

        if (device.kind != kind or device.origin != origin or !device.grabbed) {
            continue;
        }

        evdev.ungrab(device.fd);

        device.grabbed = false;
        released += 1;
    }

    assert(released <= list.count);

    return released;
}

pub fn ungrab_all(list: *List) u8 {
    assert(list.is_valid());

    var released: u8 = 0;
    var index: u8 = 0;

    while (index < list.count) : (index += 1) {
        const device = &list.devices[index];

        if (!device.grabbed) {
            continue;
        }

        evdev.ungrab(device.fd);

        device.grabbed = false;
        released += 1;
    }

    assert(released <= list.count);

    return released;
}

const testing = std.testing;

test "the kinds cover exactly the classified device roles" {
    try testing.expect(Kind.keyboard.is_valid());
    try testing.expect(Kind.mouse.is_valid());
    try testing.expect(Kind.other.is_valid());
    try testing.expectEqual(@as(u8, 3), @typeInfo(Kind).@"enum".fields.len);
}

test "an empty list reports nothing and stays valid" {
    var list = List{};

    try testing.expect(list.is_valid());
    try testing.expectEqual(@as(u8, 0), list.count);
    try testing.expectEqual(@as(u8, 0), list.count_of(.keyboard));

    list.close_all();

    try testing.expectEqual(@as(u8, 0), list.count);
}

test "build_path composes a null terminated device path" {
    var buffer: [path_bytes_max]u8 = @splat(0);
    const path = build_path(&buffer, 3) orelse return error.PathTooLong;

    try testing.expectEqualStrings("/dev/input/event3", std.mem.span(path));
}

test "build_path handles every index the scan can reach" {
    var index: u8 = 0;

    while (index < device_index_max) : (index += 1) {
        var buffer: [path_bytes_max]u8 = @splat(0);

        try testing.expect(build_path(&buffer, index) != null);
    }
}

test "a closed device reports itself closed" {
    const device = Device{};

    try testing.expect(!device.is_open());
    try testing.expectEqual(@as(u16, 0), device.path_len);
    try testing.expectEqual(Origin.direct, device.origin);
}

test "the origins cover exactly the chain relationships" {
    try testing.expect(Origin.direct.is_valid());
    try testing.expect(Origin.own.is_valid());
    try testing.expect(Origin.sibling.is_valid());
    try testing.expectEqual(@as(u8, 3), @typeInfo(Origin).@"enum".fields.len);
}

test "grab_chain skips closed devices and reports no source" {
    var list = List{};

    list.devices[0] = entry(.keyboard, .sibling, false);
    list.devices[1] = entry(.mouse, .sibling, false);
    list.devices[0].relay = true;
    list.devices[1].relay = true;
    list.count = 2;

    const own = Order{ .stamp_ms = 100, .pid = 42 };

    try testing.expect(grab_chain(&list, .keyboard, own) == null);
    try testing.expect(grab_chain(&list, .mouse, own) == null);
    try testing.expect(!list.devices[0].grabbed);
    try testing.expect(!list.devices[1].grabbed);
}

test "the chain order runs stamp first and breaks ties by pid" {
    const early = Order{ .stamp_ms = 100, .pid = 90 };
    const late = Order{ .stamp_ms = 200, .pid = 10 };
    const late_twin = Order{ .stamp_ms = 200, .pid = 20 };

    try testing.expect(early.precedes(late));
    try testing.expect(!late.precedes(early));
    try testing.expect(late.precedes(late_twin));
    try testing.expect(!late_twin.precedes(late));
    try testing.expect(!late.precedes(late));
}

fn relay_entry(kind: Kind, stamp_ms: i64, pid: u32) Device {
    var result = entry(kind, .sibling, false);

    result.fd = 999;
    result.relay = true;
    result.stamp_ms = stamp_ms;
    result.pid = pid;

    return result;
}

test "the best chain candidate is the nearest elder, not the first found" {
    var list = List{};

    list.devices[0] = relay_entry(.keyboard, 100, 1);
    list.devices[1] = relay_entry(.keyboard, 300, 3);
    list.devices[2] = relay_entry(.keyboard, 200, 2);
    list.count = 3;

    const own = Order{ .stamp_ms = 400, .pid = 4 };
    const tried: [device_count_max]bool = @splat(false);
    const best = chain_best(&list, .keyboard, own, &tried) orelse return error.MissingBest;

    try testing.expectEqual(@as(u8, 1), best);

    const younger = Order{ .stamp_ms = 250, .pid = 9 };
    const nearest = chain_best(&list, .keyboard, younger, &tried) orelse return error.MissingBest;

    try testing.expectEqual(@as(u8, 2), nearest);

    const eldest = Order{ .stamp_ms = 50, .pid = 9 };

    try testing.expect(chain_best(&list, .keyboard, eldest, &tried) == null);
}

test "an elder relay forbids a direct grab, a younger one does not" {
    var list = List{};

    list.devices[0] = relay_entry(.keyboard, 200, 2);
    list.count = 1;

    const younger = Order{ .stamp_ms = 300, .pid = 3 };
    const elder = Order{ .stamp_ms = 100, .pid = 1 };

    try testing.expect(chain_elder_present(&list, .keyboard, younger));
    try testing.expect(!chain_elder_present(&list, .keyboard, elder));
    try testing.expect(!chain_elder_present(&list, .mouse, younger));
}

test "a device exposes its own chain order" {
    var device = Device{};

    device.stamp_ms = 7;
    device.pid = 9;

    const order = device.order();

    try testing.expectEqual(@as(i64, 7), order.stamp_ms);
    try testing.expectEqual(@as(u32, 9), order.pid);
}

fn entry(kind: Kind, origin: Origin, grabbed: bool) Device {
    const result = Device{
        .kind = kind,
        .origin = origin,
        .grabbed = grabbed,
    };

    return result;
}

test "close_where drops ungrabbed devices of one kind and keeps the rest" {
    var list = List{};

    list.devices[0] = entry(.keyboard, .direct, true);
    list.devices[1] = entry(.keyboard, .sibling, false);
    list.devices[2] = entry(.mouse, .direct, false);
    list.devices[3] = entry(.keyboard, .direct, false);
    list.count = 4;

    const closed = close_where(&list, .keyboard, .not_grabbed);

    try testing.expectEqual(@as(u8, 2), closed);
    try testing.expectEqual(@as(u8, 2), list.count);
    try testing.expect(list.devices[0].grabbed);
    try testing.expectEqual(Kind.keyboard, list.devices[0].kind);
    try testing.expectEqual(Kind.mouse, list.devices[1].kind);
}

test "close_where drops siblings of one kind and keeps direct devices" {
    var list = List{};

    list.devices[0] = entry(.keyboard, .sibling, false);
    list.devices[1] = entry(.keyboard, .direct, false);
    list.devices[2] = entry(.mouse, .sibling, false);
    list.count = 3;

    const closed = close_where(&list, .keyboard, .sibling);

    try testing.expectEqual(@as(u8, 1), closed);
    try testing.expectEqual(@as(u8, 2), list.count);
    try testing.expectEqual(Origin.direct, list.devices[0].origin);
    try testing.expectEqual(Kind.mouse, list.devices[1].kind);
    try testing.expectEqual(Origin.sibling, list.devices[1].origin);
}

test "a fresh claim owns nothing and stays valid" {
    const claim = Claim{};

    try testing.expect(claim.is_valid());
    try testing.expect(!claim.is_open());
    try testing.expectEqual(@as(posix.fd_t, -1), claim.keyboard_fd);
    try testing.expectEqual(@as(posix.fd_t, -1), claim.mouse_fd);
}

test "a claim cannot hold a kind it has no descriptor for" {
    var claim = Claim{};

    claim.keyboard_held = true;

    try testing.expect(!claim.is_valid());

    claim.keyboard_fd = 3;

    try testing.expect(claim.is_valid());
    try testing.expect(!claim.is_open());

    claim.mouse_held = true;

    try testing.expect(!claim.is_valid());

    claim.mouse_fd = 4;

    try testing.expect(claim.is_valid());
    try testing.expect(claim.is_open());
}

test "claiming a kind without a descriptor is inert" {
    var claim = Claim{};

    claim_hold(&claim, .keyboard);
    claim_release(&claim, .mouse);

    try testing.expect(claim.is_valid());
    try testing.expect(!claim.keyboard_held);
    try testing.expect(!claim.mouse_held);
}

test "closing a fresh claim is inert" {
    var claim = Claim{};

    claim_close(&claim);

    try testing.expect(claim.is_valid());
    try testing.expect(!claim.is_open());
}

test "close_where on an empty list is inert" {
    var list = List{};

    try testing.expectEqual(@as(u8, 0), close_where(&list, .keyboard, .not_grabbed));
    try testing.expectEqual(@as(u8, 0), close_where(&list, .mouse, .sibling));
    try testing.expectEqual(@as(u8, 0), list.count);
}
