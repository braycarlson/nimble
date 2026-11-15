const std = @import("std");

const device = @import("device.zig");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

descriptor: posix.fd_t = -1,
watch: i32 = -1,

const Hotplug = @This();

const buffer_bytes: u16 = 4096;
pub const mask: u32 = linux.IN.CREATE | linux.IN.DELETE | linux.IN.ATTRIB;

comptime {
    assert(buffer_bytes >= 1024);
    assert(mask != 0);
}

pub fn open(hotplug: *Hotplug) bool {
    if (hotplug.descriptor >= 0) {
        return true;
    }

    const created = linux.inotify_init1(linux.IN.NONBLOCK | linux.IN.CLOEXEC);

    if (linux.errno(created) != .SUCCESS) {
        return false;
    }

    const fd: posix.fd_t = @intCast(created);
    const added = linux.inotify_add_watch(fd, device.directory, mask);

    if (linux.errno(added) != .SUCCESS) {
        _ = linux.close(fd);

        return false;
    }

    hotplug.descriptor = fd;
    hotplug.watch = @intCast(added);

    assert(hotplug.descriptor >= 0);

    return true;
}

pub fn close(hotplug: *Hotplug) void {
    if (hotplug.descriptor < 0) {
        return;
    }

    _ = linux.close(hotplug.descriptor);

    hotplug.descriptor = -1;
    hotplug.watch = -1;

    assert(hotplug.descriptor < 0);
}

pub fn handle(hotplug: *const Hotplug) posix.fd_t {
    return hotplug.descriptor;
}

pub fn drain(hotplug: *Hotplug) bool {
    if (hotplug.descriptor < 0) {
        return false;
    }

    var buffer: [buffer_bytes]u8 = undefined;
    var changed = false;
    var reads: u8 = 0;

    while (reads < 8) : (reads += 1) {
        const size = posix.read(hotplug.descriptor, &buffer) catch break;

        if (size == 0) {
            break;
        }

        changed = true;
    }

    assert(reads <= 8);

    return changed;
}

const testing = std.testing;

test "the watch is closed before it is opened" {
    var hotplug: Hotplug = .{};

    hotplug.close();

    try testing.expect(hotplug.handle() < 0);
    try testing.expect(!hotplug.drain());
}

test "opening the watch is idempotent" {
    var hotplug: Hotplug = .{};

    if (!hotplug.open()) {
        return;
    }

    defer hotplug.close();

    const first = hotplug.handle();

    try testing.expect(first >= 0);
    try testing.expect(hotplug.open());
    try testing.expectEqual(first, hotplug.handle());
}

test "the mask covers device arrival, removal, and permission change" {
    try testing.expect(mask & linux.IN.CREATE != 0);
    try testing.expect(mask & linux.IN.DELETE != 0);
    try testing.expect(mask & linux.IN.ATTRIB != 0);
}
