const std = @import("std");

const contract = @import("../contract.zig");
const loop = @import("loop.zig");

const assert = std.debug.assert;

pub const Mode = contract.Mode;
pub const Options = contract.Options;

pub const Error = error{
    AlreadyOpen,
};

pub const ReleaseCallback = *const fn () void;

var options_global: Options = .{};
var opened: bool = false;
var open_count: u16 = 0;
var close_count: u16 = 0;
var grab_wanted: bool = false;
var release_callback: ?ReleaseCallback = null;

pub fn open(requested: Options) Error!void {
    assert(requested.is_valid());

    if (opened) {
        return Error.AlreadyOpen;
    }

    loop.reset();

    options_global = requested;
    opened = true;
    open_count += 1;
    grab_wanted = requested.mode == .grab;

    assert(is_open());
}

pub fn close() void {
    if (opened) {
        close_count += 1;
    }

    options_global = .{};
    opened = false;
    grab_wanted = false;

    assert(!is_open());
}

pub fn release_grab() void {
    const was_grabbing = opened and options_global.mode == .grab;

    options_global.mode = .observe;

    if (!was_grabbing) {
        return;
    }

    const callback = release_callback orelse return;

    callback();
}

pub fn acquire_grab() void {
    if (!opened) {
        return;
    }

    if (!grab_wanted) {
        return;
    }

    options_global.mode = .grab;

    assert(mode() == .grab);
}

pub fn set_release_callback(callback: ?ReleaseCallback) void {
    release_callback = callback;
}

pub fn is_open() bool {
    return opened;
}

pub fn mode() Mode {
    return options_global.mode;
}

pub fn options() Options {
    return options_global;
}

pub fn opens() u16 {
    return open_count;
}

pub fn closes() u16 {
    return close_count;
}

pub fn reset() void {
    options_global = .{};
    opened = false;
    open_count = 0;
    close_count = 0;
    grab_wanted = false;
    release_callback = null;

    assert(!is_open());
    assert(open_count == 0);
}

const testing = std.testing;

test "the mock runtime records the lifecycle it was driven through" {
    reset();

    try testing.expect(!is_open());
    try testing.expectEqual(Mode.observe, mode());

    try open(.{ .mode = .grab });

    try testing.expect(is_open());
    try testing.expectEqual(Mode.grab, mode());
    try testing.expectError(Error.AlreadyOpen, open(.{}));
    try testing.expectEqual(@as(u16, 1), opens());

    close();

    try testing.expect(!is_open());
    try testing.expectEqual(@as(u16, 1), closes());
    try testing.expectEqual(Mode.observe, mode());

    reset();
}

const Witness = struct {
    var fired: u16 = 0;

    fn on_release() void {
        fired += 1;
    }
};

test "releasing a grab notifies the registered callback exactly once" {
    reset();

    Witness.fired = 0;

    set_release_callback(Witness.on_release);

    try open(.{ .mode = .grab });

    release_grab();

    try testing.expectEqual(@as(u16, 1), Witness.fired);
    try testing.expectEqual(Mode.observe, mode());

    release_grab();

    try testing.expectEqual(@as(u16, 1), Witness.fired);

    acquire_grab();

    try testing.expectEqual(Mode.grab, mode());

    release_grab();

    try testing.expectEqual(@as(u16, 2), Witness.fired);

    reset();
}

test "an observe session never regrabs and never notifies" {
    reset();

    Witness.fired = 0;

    set_release_callback(Witness.on_release);

    try open(.{ .mode = .observe });

    release_grab();
    acquire_grab();

    try testing.expectEqual(@as(u16, 0), Witness.fired);
    try testing.expectEqual(Mode.observe, mode());

    reset();
}

test "opening the mock runtime clears any tape left behind" {
    reset();

    loop.push_advance(10);

    try testing.expectEqual(@as(u16, 1), loop.pending());

    try open(.{});

    try testing.expectEqual(@as(u16, 0), loop.pending());

    reset();
    loop.reset();
}
