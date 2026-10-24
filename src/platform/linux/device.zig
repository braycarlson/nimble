const std = @import("std");

const evdev = @import("evdev.zig");
const time = @import("time.zig");
const uinput = @import("uinput.zig");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

pub const device_count_max: u8 = 32;
pub const device_index_max: u8 = 64;
pub const path_bytes_max: u16 = 64;
const capabilities_bytes_max: u16 = 512;
pub const directory = "/dev/input";
pub const sysfs_directory = "/sys/class/input";
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
        return @backingInt(kind) <= 2;
    }
};

pub const Origin = enum(u8) {
    direct,
    own,
    sibling,

    pub fn is_valid(origin: Origin) bool {
        return @backingInt(origin) <= 2;
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
    ignored: [device_index_max]?u64 = @splat(null),
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
            if (device.kind != kind) continue;
            if (device.origin != origin) continue;

            total += 1;
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
            if (device.kind != kind) continue;
            if (!device.grabbed) continue;

            total += 1;
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
            if (device.kind != kind) continue;
            if (device.origin != origin) continue;
            if (!device.grabbed) continue;

            total += 1;
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
        list.ignored = @splat(null);

        assert(list.count == 0);
    }
};

pub const Claim = struct {
    keyboard_fd: posix.fd_t = -1,
    mouse_fd: posix.fd_t = -1,
    keyboard_held: bool = false,
    mouse_held: bool = false,

    pub fn is_valid(claim: *const Claim) bool {
        if (claim.keyboard_held) {
            if (claim.keyboard_fd < 0) return false;
        }

        if (claim.mouse_held) {
            if (claim.mouse_fd < 0) return false;
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
    assert(path_bytes_max > sysfs_directory.len + 40);
    assert(capabilities_bytes_max > (evdev.KEY_BYTES / 8) * 17);
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

    while (index < device_index_max) : (index += 1) {
        if (total >= device_count_max) break;

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
    const written = std.mem.print(buffer, "{s}/event{d}", .{ directory, index }) catch {
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

        const device = open_at(list, index) orelse continue;

        list.devices[list.count] = device;
        list.count += 1;
    }

    assert(list.is_valid());
}

pub fn open_at(list: *List, index: u8) ?Device {
    assert(list.is_valid());
    assert(index < device_index_max);

    var device = Device{};
    const path = build_path(&device.path, index) orelse return null;
    const inode = inode_at(path);

    if (inode != null) {
        if (list.ignored[index] == inode) return null;
    }

    list.ignored[index] = null;

    if (classify_at(index) == .other) {
        list.ignored[index] = inode;

        return null;
    }

    device.path_len = @intCast(std.mem.len(path));
    device.fd = evdev.open_read(path) catch return null;

    const origin = origin_of(device.fd);

    if (origin == .own) {
        list.ignored[index] = inode;

        evdev.close(device.fd);

        return null;
    }

    device.origin = origin;
    device.kind = classify(device.fd);
    device.virtual = is_virtual(device.fd);

    if (device.kind == .other) {
        list.ignored[index] = inode;

        evdev.close(device.fd);

        return null;
    }

    annotate(&device);

    assert(list.ignored[index] == null);

    return device;
}

fn inode_at(path: [*:0]const u8) ?u64 {
    var status: linux.Statx = undefined;
    const result = linux.statx(linux.AT.FDCWD, path, 0, .{ .INO = true }, &status);

    if (linux.errno(result) != .SUCCESS) {
        return null;
    }

    if (!status.mask.INO) {
        return null;
    }

    return status.ino;
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

    if (!family_id) {
        if (!family_name) return .direct;
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

    if (is_keyboard(&keys)) {
        return .keyboard;
    }

    evdev.rel_bits(fd, &rels) catch return .other;

    if (is_mouse(&keys, &rels)) {
        return .mouse;
    }

    return .other;
}

fn classify_at(index: u8) ?Kind {
    assert(index < device_index_max);

    var keys: [evdev.KEY_BYTES]u8 = @splat(0);
    var rels: [evdev.REL_BYTES]u8 = @splat(0);

    if (!capabilities_at(index, "key", &keys)) {
        return null;
    }

    if (is_keyboard(&keys)) {
        return .keyboard;
    }

    if (!capabilities_at(index, "rel", &rels)) {
        return null;
    }

    if (is_mouse(&keys, &rels)) {
        return .mouse;
    }

    return .other;
}

fn is_keyboard(keys: *const [evdev.KEY_BYTES]u8) bool {
    const has_letters = evdev.bit_is_set(keys, 30) and evdev.bit_is_set(keys, 44);
    const has_escape = evdev.bit_is_set(keys, 1);

    return has_letters and has_escape;
}

fn is_mouse(keys: *const [evdev.KEY_BYTES]u8, rels: *const [evdev.REL_BYTES]u8) bool {
    const has_motion = evdev.bit_is_set(rels, evdev.REL_X) and
        evdev.bit_is_set(rels, evdev.REL_Y);

    const has_button = evdev.bit_is_set(keys, evdev.BTN_LEFT);
    return has_motion and has_button;
}

fn capabilities_at(index: u8, comptime name: []const u8, bits: []u8) bool {
    assert(index < device_index_max);
    assert(bits.len > 0);

    var path: [path_bytes_max]u8 = @splat(0);
    const room = path[0 .. path_bytes_max - 1];
    const format = sysfs_directory ++ "/event{d}/device/capabilities/" ++ name;

    _ = std.mem.print(room, format, .{index}) catch return false;

    const flags = posix.O{ .ACCMODE = .RDONLY, .CLOEXEC = true };
    const fd = posix.openatZ(posix.AT.FDCWD, @ptrCast(&path), flags, 0) catch return false;
    defer _ = linux.close(fd);

    var text: [capabilities_bytes_max]u8 = undefined;
    const size = posix.read(fd, &text) catch return false;

    if (size == text.len) {
        return false;
    }

    return capabilities_parse(text[0..size], bits);
}

fn capabilities_parse(text: []const u8, bits: []u8) bool {
    assert(text.len < capabilities_bytes_max);
    assert(bits.len > 0);

    var words = std.mem.splitBackwardsScalar(u8, std.mem.trimEnd(u8, text, "\n"), ' ');
    var start: usize = 0;

    @memset(bits, 0);

    while (words.next()) |word| : (start += 8) {
        assert(start <= text.len * 8);

        const value = std.fmt.parseInt(u64, word, 16) catch return false;
        var offset: usize = 0;

        while (offset < 8) : (offset += 1) {
            if (start + offset >= bits.len) break;

            bits[start + offset] = @truncate(value >> @intCast(8 * offset));
        }
    }

    assert(start > 0);

    return true;
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
        if (device.kind != kind) continue;
        if (device.origin != origin) continue;
        if (device.grabbed) continue;

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
    if (device.kind != kind) return false;
    if (device.origin != .sibling) return false;
    if (device.grabbed) return false;

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
        if (device.kind != kind) continue;
        if (device.origin != .sibling) continue;
        if (!device.is_open()) continue;
        if (!device.relay) continue;

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
        if (device.kind != kind) continue;
        if (device.origin != origin) continue;
        if (!device.grabbed) continue;

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
    try testing.expectEqual(@as(u8, 3), @typeInfo(Kind).@"enum".field_names.len);
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
    try testing.expectEqual(@as(u8, 3), @typeInfo(Origin).@"enum".field_names.len);
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

test "close_all forgets the nodes a scan passed over" {
    var list = List{};

    list.ignored[3] = 42;

    list.close_all();

    try testing.expect(list.ignored[3] == null);
}

const foreign_axes = [_]u16{ evdev.REL_X, evdev.REL_Y };
const foreign_buttons = [_]u16{evdev.BTN_LEFT};
const foreign_keys = [_]u16{ 29, 42, 47, 110 };
const foreign_label_hidden = "foreign hidden keyboard";
const foreign_label_passed = "foreign passed keyboard";
const foreign_label_pointer = "foreign hidden pointer";
const label_poll_ms: u32 = 10;
const foreign_settle_ms: u32 = 500;
const label_wait_ms_max: u32 = 2000;

const ForeignSetup = extern struct {
    id: evdev.InputId,
    name: [uinput.name_bytes_max]u8,
    ff_effects_max: u32,
};

const UI_DEV_CREATE = linux.IOCTL.IO('U', 1);
const UI_DEV_DESTROY = linux.IOCTL.IO('U', 2);
const UI_DEV_SETUP = linux.IOCTL.IOW('U', 3, ForeignSetup);
const UI_SET_EVBIT = linux.IOCTL.IOW('U', 100, i32);
const UI_SET_KEYBIT = linux.IOCTL.IOW('U', 101, i32);
const UI_SET_RELBIT = linux.IOCTL.IOW('U', 102, i32);

fn foreign_create(label: []const u8, keys: []const u16, axes: []const u16) !posix.fd_t {
    assert(label.len < uinput.name_bytes_max);
    assert(keys.len > 0);

    const flags = posix.O{ .ACCMODE = .WRONLY, .NONBLOCK = true, .CLOEXEC = true };

    const fd = posix.openatZ(posix.AT.FDCWD, uinput_path, flags, 0) catch |err| switch (err) {
        error.AccessDenied, error.FileNotFound => return error.SkipZigTest,
        error.NoDevice, error.PermissionDenied => return error.SkipZigTest,
        else => return err,
    };

    errdefer _ = linux.close(fd);

    try foreign_bits(fd, UI_SET_EVBIT, &.{evdev.EV_KEY});
    try foreign_bits(fd, UI_SET_KEYBIT, keys);

    if (axes.len > 0) {
        try foreign_bits(fd, UI_SET_EVBIT, &.{evdev.EV_REL});
        try foreign_bits(fd, UI_SET_RELBIT, axes);
    }

    var setup = ForeignSetup{
        .id = .{ .bustype = evdev.BUS_VIRTUAL, .vendor = 0, .product = 0, .version = 0 },
        .name = @splat(0),
        .ff_effects_max = 0,
    };

    @memcpy(setup.name[0..label.len], label);

    try foreign_ioctl(fd, UI_DEV_SETUP, @intFromPtr(&setup));
    try foreign_ioctl(fd, UI_DEV_CREATE, 0);

    return fd;
}

fn foreign_bits(fd: posix.fd_t, request: u32, codes: []const u16) !void {
    for (codes) |code| {
        try foreign_ioctl(fd, request, code);
    }
}

fn foreign_ioctl(fd: posix.fd_t, request: u32, argument: usize) !void {
    assert(fd >= 0);

    if (linux.errno(linux.ioctl(fd, request, argument)) != .SUCCESS) {
        return error.UinputRefused;
    }
}

fn foreign_destroy(fd: posix.fd_t) void {
    assert(fd >= 0);

    _ = linux.ioctl(fd, UI_DEV_DESTROY, 0);
    _ = linux.close(fd);
}

fn foreign_label(buffer: *[uinput.name_bytes_max]u8, base: []const u8) ![]const u8 {
    const room = buffer[0 .. uinput.name_bytes_max - 1];
    return std.mem.print(room, "{s} {d}", .{ base, uinput.pid_self() });
}

fn label_find(label: []const u8) ?u8 {
    var index: u8 = 0;

    while (index < device_index_max) : (index += 1) {
        var buffer: [evdev.NAME_BYTES]u8 = @splat(0);
        const name = sysfs_name(index, &buffer) orelse continue;

        if (std.mem.eql(u8, name, label)) {
            return index;
        }
    }

    return null;
}

fn node_readable(index: u8) bool {
    var buffer: [path_bytes_max]u8 = @splat(0);
    const path = build_path(&buffer, index) orelse return false;
    const fd = evdev.open_read(path) catch return false;

    evdev.close(fd);

    return true;
}

fn label_wait(label: []const u8) ?u8 {
    var waited: u32 = 0;

    while (waited < label_wait_ms_max) : (waited += label_poll_ms) {
        if (label_find(label)) |index| {
            if (node_readable(index)) {
                return index;
            }
        }

        time.sleep_ms(label_poll_ms);
    }

    return null;
}

fn sysfs_name(index: u8, buffer: *[evdev.NAME_BYTES]u8) ?[]const u8 {
    var path: [path_bytes_max]u8 = @splat(0);
    const room = path[0 .. path_bytes_max - 1];
    const format = sysfs_directory ++ "/event{d}/device/name";

    _ = std.mem.print(room, format, .{index}) catch return null;

    const flags = posix.O{ .ACCMODE = .RDONLY, .CLOEXEC = true };
    const fd = posix.openatZ(posix.AT.FDCWD, @ptrCast(&path), flags, 0) catch return null;
    defer _ = linux.close(fd);

    const size = posix.read(fd, buffer) catch return null;
    return std.mem.trimEnd(u8, buffer[0..size], "\n");
}

fn hardware_lock() !posix.fd_t {
    var path: [path_bytes_max]u8 = @splat(0);
    const room = path[0 .. path_bytes_max - 1];

    _ = try std.mem.print(room, "/tmp/nimble-input-tests-{d}.lock", .{linux.getuid()});

    const flags = posix.O{ .ACCMODE = .RDWR, .CREAT = true, .CLOEXEC = true };
    const fd = try posix.openatZ(posix.AT.FDCWD, @ptrCast(&path), flags, 0o600);
    errdefer _ = linux.close(fd);

    if (linux.errno(linux.flock(fd, posix.LOCK.EX)) != .SUCCESS) {
        return error.LockUnavailable;
    }

    return fd;
}

fn capabilities_path(buffer: *[path_bytes_max]u8, index: u8) ![*:0]const u8 {
    const room = buffer[0 .. path_bytes_max - 1];
    const format = sysfs_directory ++ "/event{d}/device/capabilities/key";

    _ = try std.mem.print(room, format, .{index});

    return @ptrCast(buffer);
}

fn opens_watch(path: [*:0]const u8) !posix.fd_t {
    const created = linux.inotify_init1(linux.IN.NONBLOCK | linux.IN.CLOEXEC);

    if (linux.errno(created) != .SUCCESS) {
        return error.WatchUnavailable;
    }

    const fd: posix.fd_t = @intCast(created);
    const added = linux.inotify_add_watch(fd, path, linux.IN.OPEN);

    if (linux.errno(added) != .SUCCESS) {
        _ = linux.close(fd);

        return error.WatchUnavailable;
    }

    return fd;
}

fn opens_seen(watch: posix.fd_t) bool {
    assert(watch >= 0);

    var buffer: [256]u8 = undefined;
    const size = linux.read(watch, &buffer, buffer.len);

    return linux.errno(size) == .SUCCESS and size > 0;
}

fn agrees_at(index: u8) !bool {
    var buffer: [path_bytes_max]u8 = @splat(0);
    const path = build_path(&buffer, index) orelse return false;
    const fd = evdev.open_read(path) catch return false;
    defer evdev.close(fd);

    const ioctl_kind = classify(fd);
    const sysfs_kind = classify_at(index);

    if (!is_alive(fd)) {
        return false;
    }

    try testing.expectEqual(@as(?Kind, ioctl_kind), sysfs_kind);

    return true;
}

test "sysfs capability text parses into the bitmap the ioctl returns" {
    var keys: [evdev.KEY_BYTES]u8 = @splat(0xff);
    var rels: [evdev.REL_BYTES]u8 = @splat(0xff);

    try testing.expect(capabilities_parse("ffff0000 0 0 0 0\n", &keys));
    try testing.expect(capabilities_parse("1943\n", &rels));
    try testing.expect(is_mouse(&keys, &rels));
    try testing.expect(!is_keyboard(&keys));

    const wide = "733eff 0 0 483ffff17aff32d bfd4444600000000 1 130ff38b17c007 " ++
        "ffff7bfad941dfff febeffdfffefffff fffffffffffffffe\n";

    try testing.expect(capabilities_parse(wide, &keys));
    try testing.expect(capabilities_parse("1040\n", &rels));
    try testing.expect(is_keyboard(&keys));
    try testing.expect(!is_mouse(&keys, &rels));
    try testing.expect(evdev.bit_is_set(&keys, 9 * 64));
    try testing.expect(!evdev.bit_is_set(&keys, 9 * 64 + 8));
    try testing.expect(!evdev.bit_is_set(&keys, 10 * 64));

    try testing.expect(capabilities_parse("400000000000 840020000000\n", &keys));
    try testing.expect(capabilities_parse("0\n", &rels));
    try testing.expect(evdev.bit_is_set(&keys, 29));
    try testing.expect(evdev.bit_is_set(&keys, 42));
    try testing.expect(evdev.bit_is_set(&keys, 47));
    try testing.expect(evdev.bit_is_set(&keys, 110));
    try testing.expect(!evdev.bit_is_set(&keys, 30));
    try testing.expect(!is_keyboard(&keys));
    try testing.expect(!is_mouse(&keys, &rels));
}

test "sysfs capability text that is not hex is refused" {
    var keys: [evdev.KEY_BYTES]u8 = @splat(0);

    try testing.expect(!capabilities_parse("zz\n", &keys));
    try testing.expect(!capabilities_parse("\n", &keys));
    try testing.expect(!capabilities_parse("1  2\n", &keys));
}

test "sysfs and ioctl classification agree on every readable device" {
    const lock = try hardware_lock();
    defer _ = linux.close(lock);

    var keys_buffer: [uinput.name_bytes_max]u8 = @splat(0);
    const keys_label = try foreign_label(&keys_buffer, foreign_label_passed);
    const keys = try foreign_create(keys_label, &foreign_keys, &.{});
    defer foreign_destroy(keys);

    var pointer_buffer: [uinput.name_bytes_max]u8 = @splat(0);
    const pointer_label = try foreign_label(&pointer_buffer, foreign_label_pointer);
    const pointer = try foreign_create(pointer_label, &foreign_buttons, &foreign_axes);
    defer foreign_destroy(pointer);

    const keys_index = label_wait(keys_label) orelse return error.DeviceMissing;
    const pointer_index = label_wait(pointer_label) orelse return error.DeviceMissing;

    var compared: u8 = 0;
    var index: u8 = 0;

    while (index < device_index_max) : (index += 1) {
        if (try agrees_at(index)) {
            compared += 1;
        }
    }

    try testing.expect(compared >= 2);
    try testing.expectEqual(@as(?Kind, .other), classify_at(keys_index));
    try testing.expectEqual(@as(?Kind, .mouse), classify_at(pointer_index));
}

test "a scan passes over a foreign node without ever opening it" {
    const lock = try hardware_lock();
    defer _ = linux.close(lock);

    var label_buffer: [uinput.name_bytes_max]u8 = @splat(0);
    const label = try foreign_label(&label_buffer, foreign_label_passed);
    const keys = try foreign_create(label, &foreign_keys, &.{});
    defer foreign_destroy(keys);

    const index = label_wait(label) orelse return error.DeviceMissing;

    time.sleep_ms(foreign_settle_ms);

    var node_buffer: [path_bytes_max]u8 = @splat(0);
    var capabilities_buffer: [path_bytes_max]u8 = @splat(0);
    const node = build_path(&node_buffer, index) orelse return error.PathTooLong;
    const capabilities = try capabilities_path(&capabilities_buffer, index);
    const node_watch = try opens_watch(node);
    defer _ = linux.close(node_watch);

    const capabilities_watch = try opens_watch(capabilities);
    defer _ = linux.close(capabilities_watch);

    var list = List{};

    try testing.expect(open_at(&list, index) == null);
    try testing.expect(opens_seen(capabilities_watch));

    const passed = list.ignored[index] orelse return error.NodeForgotten;

    try testing.expect(open_at(&list, index) == null);
    try testing.expect(!opens_seen(capabilities_watch));

    list.ignored[index] = passed +% 1;

    try testing.expect(open_at(&list, index) == null);
    try testing.expect(opens_seen(capabilities_watch));
    try testing.expect(!opens_seen(node_watch));
    try testing.expectEqual(passed, list.ignored[index] orelse return error.NodeForgotten);
}

test "a scan opens one of its own devices to learn it is its own and remembers it" {
    const lock = try hardware_lock();
    defer _ = linux.close(lock);

    var own = uinput.create(.keyboard, .inject) catch |err| switch (err) {
        error.Inaccessible => return error.SkipZigTest,
        else => return err,
    };

    defer own.destroy();

    var label_buffer: [uinput.name_bytes_max]u8 = @splat(0);
    const room = label_buffer[0 .. uinput.name_bytes_max - 1];

    const label = try std.mem.print(room, "{s} {d} {d} {s}", .{
        uinput.Kind.keyboard.label(),
        uinput.pid_self(),
        own.stamp_ms,
        uinput.Role.inject.word(),
    });

    const index = label_wait(label) orelse return error.DeviceMissing;

    var node_buffer: [path_bytes_max]u8 = @splat(0);
    const node = build_path(&node_buffer, index) orelse return error.PathTooLong;
    const node_watch = try opens_watch(node);
    defer _ = linux.close(node_watch);

    var list = List{};

    try testing.expect(open_at(&list, index) == null);
    try testing.expect(opens_seen(node_watch));
    try testing.expect(list.ignored[index] != null);
}

test "a remembered node never hides a different node at its index" {
    const lock = try hardware_lock();
    defer _ = linux.close(lock);

    var keys_buffer: [uinput.name_bytes_max]u8 = @splat(0);
    const keys_label = try foreign_label(&keys_buffer, foreign_label_hidden);
    const keys = try foreign_create(keys_label, &foreign_keys, &.{});
    defer foreign_destroy(keys);

    const index = label_wait(keys_label) orelse return error.DeviceMissing;

    var list = List{};

    try testing.expect(open_at(&list, index) == null);

    const passed = list.ignored[index] orelse return error.NodeForgotten;

    var pointer_buffer: [uinput.name_bytes_max]u8 = @splat(0);
    const pointer_label = try foreign_label(&pointer_buffer, foreign_label_pointer);
    const pointer = try foreign_create(pointer_label, &foreign_buttons, &foreign_axes);
    defer foreign_destroy(pointer);

    const other = label_wait(pointer_label) orelse return error.DeviceMissing;

    try testing.expect(other != index);

    list.ignored[other] = passed;

    const kept = open_at(&list, other) orelse return error.ReplacementSkipped;
    defer evdev.close(kept.fd);

    try testing.expectEqual(Kind.mouse, kept.kind);
    try testing.expectEqual(Origin.direct, kept.origin);
    try testing.expect(list.ignored[other] == null);
}
