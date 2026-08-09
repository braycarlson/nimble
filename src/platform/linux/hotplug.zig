const std = @import("std");

const device = @import("device.zig");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

pub const buffer_bytes: u16 = 4096;
pub const mask: u32 = linux.IN.CREATE | linux.IN.DELETE | linux.IN.ATTRIB;

var descriptor: posix.fd_t = -1;
var watch: i32 = -1;

comptime {
    assert(buffer_bytes >= 1024);
    assert(mask != 0);
}

pub fn open() bool {
    if (descriptor >= 0) {
        return true;
    }

    const created = linux.inotify_init1(linux.IN.NONBLOCK | linux.IN.CLOEXEC);

    if (posix.errno(created) != .SUCCESS) {
        return false;
    }

    const fd: posix.fd_t = @intCast(created);
    const added = linux.inotify_add_watch(fd, device.directory, mask);

    if (posix.errno(added) != .SUCCESS) {
        _ = linux.close(fd);

        return false;
    }

    descriptor = fd;
    watch = @intCast(added);

    assert(descriptor >= 0);

    return true;
}

pub fn close() void {
    if (descriptor < 0) {
        return;
    }

    _ = linux.close(descriptor);

    descriptor = -1;
    watch = -1;

    assert(descriptor < 0);
}

pub fn handle() posix.fd_t {
    return descriptor;
}

pub fn drain() bool {
    if (descriptor < 0) {
        return false;
    }

    var buffer: [buffer_bytes]u8 = undefined;
    var changed = false;
    var reads: u8 = 0;

    while (reads < 8) : (reads += 1) {
        const size = posix.read(descriptor, &buffer) catch break;

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
    close();

    try testing.expect(handle() < 0);
    try testing.expect(!drain());
}

test "opening the watch is idempotent" {
    close();

    if (!open()) {
        return;
    }
    defer close();

    const first = handle();

    try testing.expect(first >= 0);
    try testing.expect(open());
    try testing.expectEqual(first, handle());
}

test "the mask covers device arrival, removal, and permission change" {
    try testing.expect(mask & linux.IN.CREATE != 0);
    try testing.expect(mask & linux.IN.DELETE != 0);
    try testing.expect(mask & linux.IN.ATTRIB != 0);
}
