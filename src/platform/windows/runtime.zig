const std = @import("std");

const contract = @import("../contract.zig");

const assert = std.debug.assert;

pub const Mode = contract.Mode;
pub const Options = contract.Options;

pub const Error = error{
    AlreadyOpen,
};

pub const ReleaseCallback = *const fn () void;

var opened: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var mode_global: std.atomic.Value(u8) = std.atomic.Value(u8).init(@intFromEnum(Mode.observe));
var synthesis_global: std.atomic.Value(bool) = std.atomic.Value(bool).init(true);
var rescue_global: std.atomic.Value(bool) = std.atomic.Value(bool).init(true);
var grab_wanted: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);

var release_callback: std.atomic.Value(?ReleaseCallback) =
    std.atomic.Value(?ReleaseCallback).init(null);

pub fn open(requested: Options) Error!void {
    assert(requested.is_valid());

    if (opened.cmpxchgStrong(false, true, .seq_cst, .seq_cst) != null) {
        return Error.AlreadyOpen;
    }

    mode_global.store(@intFromEnum(requested.mode), .seq_cst);
    synthesis_global.store(requested.synthesis, .seq_cst);
    rescue_global.store(requested.rescue, .seq_cst);
    grab_wanted.store(requested.mode == .grab, .seq_cst);

    assert(is_open());
}

pub fn close() void {
    mode_global.store(@intFromEnum(Mode.observe), .seq_cst);
    synthesis_global.store(true, .seq_cst);
    rescue_global.store(true, .seq_cst);
    grab_wanted.store(false, .seq_cst);
    opened.store(false, .seq_cst);

    assert(!is_open());
}

pub fn release_grab() void {
    const was_grabbing = is_open() and mode() == .grab;

    mode_global.store(@intFromEnum(Mode.observe), .seq_cst);

    if (!was_grabbing) {
        return;
    }

    const callback = release_callback.load(.seq_cst) orelse return;

    callback();
}

pub fn acquire_grab() void {
    if (!is_open()) {
        return;
    }

    if (!grab_wanted.load(.seq_cst)) {
        return;
    }

    mode_global.store(@intFromEnum(Mode.grab), .seq_cst);

    assert(mode() == .grab);
}

pub fn set_release_callback(callback: ?ReleaseCallback) void {
    release_callback.store(callback, .seq_cst);
}

pub fn is_open() bool {
    return opened.load(.seq_cst);
}

pub fn mode() Mode {
    return @enumFromInt(mode_global.load(.seq_cst));
}

pub fn options() Options {
    return Options{
        .mode = mode(),
        .synthesis = synthesis_global.load(.seq_cst),
        .rescue = rescue_global.load(.seq_cst),
    };
}

const testing = std.testing;

test "the runtime opens once and records what it was asked for" {
    close();

    try testing.expect(!is_open());
    try testing.expectEqual(Mode.observe, mode());

    try open(.{ .mode = .grab, .synthesis = false });

    try testing.expect(is_open());
    try testing.expectEqual(Mode.grab, mode());
    try testing.expect(!options().synthesis);
    try testing.expectError(Error.AlreadyOpen, open(.{}));

    close();

    try testing.expect(!is_open());
    try testing.expectEqual(Mode.observe, mode());
}
