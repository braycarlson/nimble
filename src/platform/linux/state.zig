const std = @import("std");

const device = @import("device.zig");
const evdev = @import("evdev.zig");
const keycode = @import("../../keycode.zig");
const mapping = @import("keycode.zig");

const assert = std.debug.assert;

const posix = std.posix;

const Keycode = keycode.Keycode;

pub const source_count_max: u8 = device.device_count_max;

pub const Snapshot = struct {
    bits: [source_count_max][evdev.KEY_BYTES]u8 = undefined,
    count: u8 = 0,

    pub fn is_valid(snapshot: *const Snapshot) bool {
        return snapshot.count <= source_count_max;
    }

    pub fn is_set(snapshot: *const Snapshot, native: u8) bool {
        assert(snapshot.is_valid());

        var index: u8 = 0;

        while (index < snapshot.count) : (index += 1) {
            if (evdev.bit_is_set(&snapshot.bits[index], native)) {
                return true;
            }
        }

        assert(index == snapshot.count);

        return false;
    }
};

var sources: [source_count_max]posix.fd_t = @splat(-1);
var source_count: u8 = 0;

comptime {
    assert(source_count_max > 0);
    assert(source_count_max >= device.device_count_max);
}

pub fn add_source(fd: posix.fd_t) bool {
    assert(fd >= 0);

    if (source_count == source_count_max) {
        return false;
    }

    sources[source_count] = fd;
    source_count += 1;

    assert(source_count <= source_count_max);

    return true;
}

pub fn clear_sources() void {
    sources = @splat(-1);
    source_count = 0;

    assert(source_count == 0);
}

pub fn capture() Snapshot {
    var result = Snapshot{};
    var index: u8 = 0;

    while (index < source_count) : (index += 1) {
        const fd = sources[index];

        if (fd < 0) {
            continue;
        }

        assert(result.count < source_count_max);

        evdev.key_state(fd, &result.bits[result.count]) catch continue;

        result.count += 1;
    }

    assert(index == source_count);
    assert(result.is_valid());

    return result;
}

pub fn is_key_down_at(snapshot: *const Snapshot, code: Keycode) bool {
    assert(snapshot.is_valid());

    const native = mapping.to_native(code) orelse return false;

    return snapshot.is_set(native);
}

pub fn is_key_down(code: Keycode) bool {
    const snapshot = capture();

    return is_key_down_at(&snapshot, code);
}

const testing = std.testing;

test "no sources means nothing reads as down" {
    clear_sources();

    try testing.expect(!is_key_down(.a));
    try testing.expect(!is_key_down(.control_left));
}

test "sources are bounded" {
    clear_sources();

    var index: u8 = 0;

    while (index < source_count_max) : (index += 1) {
        try testing.expect(add_source(@intCast(index)));
    }

    try testing.expect(!add_source(99));

    clear_sources();
}

test "the source bound matches the device bound" {
    try testing.expectEqual(device.device_count_max, source_count_max);
}

test "unmappable keycodes never read as down" {
    clear_sources();

    _ = add_source(0);

    try testing.expect(!is_key_down(.silent));

    clear_sources();
}

test "an empty snapshot reports every key up" {
    clear_sources();

    const snapshot = capture();

    try testing.expect(snapshot.is_valid());
    try testing.expectEqual(@as(u8, 0), snapshot.count);
    try testing.expect(!is_key_down_at(&snapshot, .a));
    try testing.expect(!is_key_down_at(&snapshot, .silent));
}

test "a snapshot reads bits it was handed" {
    var snapshot = Snapshot{};

    snapshot.bits[0] = @splat(0);
    snapshot.bits[1] = @splat(0);
    snapshot.count = 2;

    const native = mapping.to_native(.a) orelse return error.MissingMapping;

    try testing.expect(!snapshot.is_set(native));

    snapshot.bits[1][native / 8] |= @as(u8, 1) << @truncate(native % 8);

    try testing.expect(snapshot.is_set(native));
    try testing.expect(is_key_down_at(&snapshot, .a));
}
