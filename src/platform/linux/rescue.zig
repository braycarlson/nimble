const std = @import("std");

const keycode = @import("../../keycode.zig");
const rescue_module = @import("../../rescue.zig");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

const Keycode = keycode.Keycode;

share_fd: posix.fd_t = -1,
share_seen_ms: i64 = 0,
tracker: rescue_module.Tracker = .{},

const Rescue = @This();

const hold_ms_default = rescue_module.hold_ms_default;
pub const combination = [_]Keycode{ .shift_left, .shift_right };
const share_path_bytes_max: u16 = 128;
const share_bytes: u16 = 8;

comptime {
    assert(combination.len == 2);
    assert(share_path_bytes_max > 64);
    assert(share_bytes == @sizeOf(i64));
}

pub fn set_hold_ms(rescue: *Rescue, hold_ms: u32) void {
    assert(hold_ms >= 100);

    rescue.tracker.hold_ms = hold_ms;

    assert(rescue.tracker.hold_ms == hold_ms);
}

pub fn observe(rescue: *Rescue, code: Keycode, down: bool, now_ms: i64) bool {
    assert(now_ms >= 0);

    rescue.tracker.observe(code, down, now_ms);

    return false;
}

pub fn poll(rescue: *Rescue, now_ms: i64) bool {
    assert(now_ms >= 0);

    return rescue.tracker.poll(now_ms);
}

pub fn is_armed(rescue: *const Rescue) bool {
    return rescue.tracker.is_armed();
}

pub fn reset(rescue: *Rescue) void {
    const share_fd = rescue.share_fd;

    rescue.tracker = .{};

    assert(!rescue.tracker.triggered);
    assert(rescue.tracker.since_ms == null);
    assert(rescue.share_fd == share_fd);
}

pub fn share_open(rescue: *Rescue) void {
    if (rescue.share_fd >= 0) {
        return;
    }

    const fd = share_open_file() orelse return;

    rescue.share_fd = fd;
    rescue.share_seen_ms = rescue.share_read();

    assert(rescue.share_fd >= 0);
}

pub fn share_close(rescue: *Rescue) void {
    if (rescue.share_fd < 0) {
        return;
    }

    _ = linux.close(rescue.share_fd);

    rescue.share_fd = -1;
    rescue.share_seen_ms = 0;

    assert(rescue.share_fd < 0);
}

pub fn share_signal(rescue: *Rescue, now_ms: i64) void {
    assert(now_ms >= 0);

    if (rescue.share_fd < 0) {
        return;
    }

    var buffer: [share_bytes]u8 = @splat(0);

    std.mem.writeInt(i64, &buffer, now_ms, .little);

    const status = linux.pwrite(rescue.share_fd, &buffer, buffer.len, 0);

    if (linux.errno(status) != .SUCCESS) {
        return;
    }

    if (status != buffer.len) {
        return;
    }

    rescue.share_seen_ms = now_ms;

    assert(rescue.share_seen_ms == now_ms);
}

pub fn share_tripped(rescue: *Rescue) bool {
    if (rescue.share_fd < 0) {
        return false;
    }

    const value = rescue.share_read();

    if (value <= rescue.share_seen_ms) {
        return false;
    }

    rescue.share_seen_ms = value;

    assert(rescue.share_seen_ms == value);

    return true;
}

fn share_read(rescue: *const Rescue) i64 {
    assert(rescue.share_fd >= 0);

    var buffer: [share_bytes]u8 = @splat(0);
    const status = linux.pread(rescue.share_fd, &buffer, buffer.len, 0);

    if (linux.errno(status) != .SUCCESS) {
        return 0;
    }

    if (status != buffer.len) {
        return 0;
    }

    return std.mem.readInt(i64, &buffer, .little);
}

fn share_open_file() ?posix.fd_t {
    var runtime_buffer: [share_path_bytes_max]u8 = @splat(0);
    var shared_buffer: [share_path_bytes_max]u8 = @splat(0);

    const runtime_path = share_path(&runtime_buffer, "/run/user/{d}/nimble-rescue");
    const shared_path = share_path(&shared_buffer, "/tmp/nimble-rescue-{d}");

    if (runtime_path) |path| {
        if (share_open_path(path)) |fd| {
            return fd;
        }
    }

    const path = shared_path orelse return null;
    return share_open_path(path);
}

fn share_open_path(path: [*:0]const u8) ?posix.fd_t {
    assert(path[0] != 0);

    const flags = posix.O{ .ACCMODE = .RDWR, .CREAT = true, .CLOEXEC = true };
    return posix.openatZ(posix.AT.FDCWD, path, flags, 0o600) catch null;
}

fn share_path(buffer: *[share_path_bytes_max]u8, comptime format: []const u8) ?[*:0]const u8 {
    const room = buffer[0 .. share_path_bytes_max - 1];
    const written = std.mem.print(room, format, .{linux.getuid()}) catch return null;

    assert(written.len < share_path_bytes_max);

    buffer[written.len] = 0;

    return @ptrCast(buffer);
}

const testing = std.testing;

test "holding both shifts past the threshold trips the rescue" {
    var rescue: Rescue = .{};

    rescue.reset();

    _ = rescue.observe(.shift_left, true, 1000);
    _ = rescue.observe(.shift_right, true, 1000);

    try testing.expect(rescue.is_armed());
    try testing.expect(!rescue.poll(1000));
    try testing.expect(!rescue.poll(1000 + hold_ms_default - 1));
    try testing.expect(rescue.poll(1000 + hold_ms_default));
}

test "the rescue trips only once per hold" {
    var rescue: Rescue = .{};

    rescue.reset();

    _ = rescue.observe(.shift_left, true, 0);
    _ = rescue.observe(.shift_right, true, 0);

    try testing.expect(rescue.poll(hold_ms_default));
    try testing.expect(!rescue.poll(hold_ms_default * 2));
}

test "releasing either shift disarms the rescue" {
    var rescue: Rescue = .{};

    rescue.reset();

    _ = rescue.observe(.shift_left, true, 0);
    _ = rescue.observe(.shift_right, true, 0);

    try testing.expect(rescue.is_armed());

    _ = rescue.observe(.shift_left, false, 100);

    try testing.expect(!rescue.is_armed());
    try testing.expect(!rescue.poll(hold_ms_default * 4));
}

test "unrelated keys never arm the rescue" {
    var rescue: Rescue = .{};

    rescue.reset();

    try testing.expect(!rescue.observe(.a, true, 0));
    try testing.expect(!rescue.observe(.control_left, true, 0));
    try testing.expect(!rescue.is_armed());
}

test "a closed shared rescue channel never trips" {
    var rescue: Rescue = .{};

    rescue.share_close();

    try testing.expect(!rescue.share_tripped());

    rescue.share_signal(1234);

    try testing.expect(!rescue.share_tripped());
}

test "the shared rescue channel trips once for each newer epoch" {
    var rescue: Rescue = .{};

    rescue.share_close();
    rescue.share_open();

    if (rescue.share_fd < 0) {
        return error.SkipZigTest;
    }

    const original = rescue.share_read();
    defer rescue.share_close();
    defer rescue.share_signal(original);

    rescue.share_signal(1_000_000);

    try testing.expect(!rescue.share_tripped());

    rescue.share_seen_ms = 999_999;

    try testing.expect(rescue.share_tripped());
    try testing.expect(!rescue.share_tripped());
}

test "reset keeps the shared rescue channel open" {
    var rescue: Rescue = .{};

    rescue.share_close();
    rescue.share_open();

    if (rescue.share_fd < 0) {
        return error.SkipZigTest;
    }

    defer rescue.share_close();

    const fd = rescue.share_fd;

    _ = rescue.observe(.shift_left, true, 0);
    _ = rescue.observe(.shift_right, true, 0);

    try testing.expect(rescue.is_armed());

    rescue.reset();

    try testing.expect(!rescue.is_armed());
    try testing.expectEqual(fd, rescue.share_fd);
}

test "a shorter configured hold trips sooner" {
    var rescue: Rescue = .{};

    rescue.reset();
    rescue.set_hold_ms(250);

    _ = rescue.observe(.shift_left, true, 0);
    _ = rescue.observe(.shift_right, true, 0);

    try testing.expect(!rescue.poll(249));
    try testing.expect(rescue.poll(250));

    rescue.reset();
    rescue.set_hold_ms(hold_ms_default);
}
