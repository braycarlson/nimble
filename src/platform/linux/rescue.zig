const std = @import("std");

const keycode = @import("../../keycode.zig");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

const Keycode = keycode.Keycode;

pub const hold_ms_default: u32 = 2000;
pub const combination = [_]Keycode{ .shift_left, .shift_right };
pub const share_path_bytes_max: u16 = 128;
pub const share_bytes: u16 = 8;

const Tracker = struct {
    left_down: bool = false,
    right_down: bool = false,
    since_ms: ?i64 = null,
    hold_ms: u32 = hold_ms_default,
    triggered: bool = false,
    share_fd: posix.fd_t = -1,
    share_seen_ms: i64 = 0,
};

var tracker: Tracker = .{};

comptime {
    assert(hold_ms_default >= 500);
    assert(combination.len == 2);
    assert(share_path_bytes_max > 64);
    assert(share_bytes == @sizeOf(i64));
}

pub fn set_hold_ms(hold_ms: u32) void {
    assert(hold_ms >= 100);

    tracker.hold_ms = hold_ms;

    assert(tracker.hold_ms == hold_ms);
}

pub fn observe(code: Keycode, down: bool, now_ms: i64) bool {
    assert(now_ms >= 0);

    switch (code) {
        .shift_left => tracker.left_down = down,
        .shift_right => tracker.right_down = down,
        else => return false,
    }

    const both = tracker.left_down and tracker.right_down;

    if (!both) {
        tracker.since_ms = null;
        tracker.triggered = false;

        return false;
    }

    if (tracker.since_ms == null) {
        tracker.since_ms = now_ms;
    }

    assert(tracker.since_ms != null);

    return false;
}

pub fn poll(now_ms: i64) bool {
    assert(now_ms >= 0);

    const both = tracker.left_down and tracker.right_down;

    if (!both or tracker.triggered) {
        return false;
    }

    const since_ms = tracker.since_ms orelse return false;
    const held_ms = now_ms - since_ms;

    assert(held_ms >= 0);

    if (held_ms < tracker.hold_ms) {
        return false;
    }

    tracker.triggered = true;

    return true;
}

pub fn is_armed() bool {
    return tracker.left_down and tracker.right_down;
}

pub fn reset() void {
    const share_fd = tracker.share_fd;
    const share_seen_ms = tracker.share_seen_ms;

    tracker = .{};

    tracker.share_fd = share_fd;
    tracker.share_seen_ms = share_seen_ms;

    assert(!tracker.triggered);
    assert(tracker.since_ms == null);
    assert(tracker.share_fd == share_fd);
}

pub fn share_open() void {
    if (tracker.share_fd >= 0) {
        return;
    }

    const fd = share_open_file() orelse return;

    tracker.share_fd = fd;
    tracker.share_seen_ms = share_read();

    assert(tracker.share_fd >= 0);
}

pub fn share_close() void {
    if (tracker.share_fd < 0) {
        return;
    }

    _ = linux.close(tracker.share_fd);

    tracker.share_fd = -1;
    tracker.share_seen_ms = 0;

    assert(tracker.share_fd < 0);
}

pub fn share_signal(now_ms: i64) void {
    assert(now_ms >= 0);

    if (tracker.share_fd < 0) {
        return;
    }

    var buffer: [share_bytes]u8 = @splat(0);

    std.mem.writeInt(i64, &buffer, now_ms, .little);

    const status = linux.pwrite(tracker.share_fd, &buffer, buffer.len, 0);

    if (posix.errno(status) != .SUCCESS) {
        return;
    }

    if (status != buffer.len) {
        return;
    }

    tracker.share_seen_ms = now_ms;

    assert(tracker.share_seen_ms == now_ms);
}

pub fn share_tripped() bool {
    if (tracker.share_fd < 0) {
        return false;
    }

    const value = share_read();

    if (value <= tracker.share_seen_ms) {
        return false;
    }

    tracker.share_seen_ms = value;

    assert(tracker.share_seen_ms == value);

    return true;
}

fn share_read() i64 {
    assert(tracker.share_fd >= 0);

    var buffer: [share_bytes]u8 = @splat(0);
    const status = linux.pread(tracker.share_fd, &buffer, buffer.len, 0);

    if (posix.errno(status) != .SUCCESS) {
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
    const flags = posix.O{ .ACCMODE = .RDWR, .CREAT = true, .CLOEXEC = true };

    return posix.openatZ(posix.AT.FDCWD, path, flags, 0o600) catch null;
}

fn share_path(
    buffer: *[share_path_bytes_max]u8,
    comptime format: []const u8,
) ?[*:0]const u8 {
    const room = buffer[0 .. share_path_bytes_max - 1];
    const written = std.fmt.bufPrint(room, format, .{linux.getuid()}) catch return null;

    assert(written.len < share_path_bytes_max);

    buffer[written.len] = 0;

    return @ptrCast(buffer);
}

const testing = std.testing;

test "holding both shifts past the threshold trips the rescue" {
    reset();

    _ = observe(.shift_left, true, 1000);
    _ = observe(.shift_right, true, 1000);

    try testing.expect(is_armed());
    try testing.expect(!poll(1000));
    try testing.expect(!poll(1000 + hold_ms_default - 1));
    try testing.expect(poll(1000 + hold_ms_default));
}

test "the rescue trips only once per hold" {
    reset();

    _ = observe(.shift_left, true, 0);
    _ = observe(.shift_right, true, 0);

    try testing.expect(poll(hold_ms_default));
    try testing.expect(!poll(hold_ms_default * 2));
}

test "releasing either shift disarms the rescue" {
    reset();

    _ = observe(.shift_left, true, 0);
    _ = observe(.shift_right, true, 0);

    try testing.expect(is_armed());

    _ = observe(.shift_left, false, 100);

    try testing.expect(!is_armed());
    try testing.expect(!poll(hold_ms_default * 4));
}

test "unrelated keys never arm the rescue" {
    reset();

    try testing.expect(!observe(.a, true, 0));
    try testing.expect(!observe(.control_left, true, 0));
    try testing.expect(!is_armed());
}

test "a closed shared rescue channel never trips" {
    share_close();

    try testing.expect(!share_tripped());

    share_signal(1234);

    try testing.expect(!share_tripped());
}

test "the shared rescue channel trips once for each newer epoch" {
    share_close();
    share_open();

    if (tracker.share_fd < 0) {
        return error.SkipZigTest;
    }

    const original = share_read();
    defer share_close();
    defer share_signal(original);

    share_signal(1_000_000);

    try testing.expect(!share_tripped());

    tracker.share_seen_ms = 999_999;

    try testing.expect(share_tripped());
    try testing.expect(!share_tripped());
}

test "reset keeps the shared rescue channel open" {
    share_close();
    share_open();

    if (tracker.share_fd < 0) {
        return error.SkipZigTest;
    }
    defer share_close();

    const fd = tracker.share_fd;

    _ = observe(.shift_left, true, 0);
    _ = observe(.shift_right, true, 0);

    try testing.expect(is_armed());

    reset();

    try testing.expect(!is_armed());
    try testing.expectEqual(fd, tracker.share_fd);
}

test "a shorter configured hold trips sooner" {
    reset();
    set_hold_ms(250);

    _ = observe(.shift_left, true, 0);
    _ = observe(.shift_right, true, 0);

    try testing.expect(!poll(249));
    try testing.expect(poll(250));

    reset();
    set_hold_ms(hold_ms_default);
}
