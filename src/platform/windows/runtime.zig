const std = @import("std");

const interface = @import("../interface.zig");

const assert = std.debug.assert;

const Mode = interface.Mode;
const Options = interface.Options;
const ReleaseCallback = interface.ReleaseCallback;

opened: std.atomic.Value(bool) = .init(false),
mode_raw: std.atomic.Value(u8) = .init(@backingInt(Mode.observe)),
synthesis: std.atomic.Value(bool) = .init(true),
rescue: std.atomic.Value(bool) = .init(true),
grab_wanted: std.atomic.Value(bool) = .init(false),
release_callback: ?ReleaseCallback = null,

const Runtime = @This();

pub fn open(runtime: *Runtime, requested: Options) void {
    assert(requested.is_valid());
    assert(!runtime.is_open());

    runtime.mode_raw.store(@backingInt(requested.mode), .seq_cst);
    runtime.synthesis.store(requested.synthesis, .seq_cst);
    runtime.rescue.store(requested.rescue, .seq_cst);
    runtime.grab_wanted.store(requested.mode == .grab, .seq_cst);
    runtime.opened.store(true, .seq_cst);

    assert(runtime.is_open());
    assert(runtime.mode() == requested.mode);
}

pub fn close(runtime: *Runtime) void {
    runtime.mode_raw.store(@backingInt(Mode.observe), .seq_cst);
    runtime.synthesis.store(true, .seq_cst);
    runtime.rescue.store(true, .seq_cst);
    runtime.grab_wanted.store(false, .seq_cst);
    runtime.opened.store(false, .seq_cst);

    assert(!runtime.is_open());
}

pub fn release_grab(runtime: *Runtime) void {
    const was_grabbing = runtime.is_open() and runtime.mode() == .grab;

    runtime.mode_raw.store(@backingInt(Mode.observe), .seq_cst);

    assert(runtime.mode() == .observe);

    if (!was_grabbing) {
        return;
    }

    const callback = runtime.release_callback orelse return;

    callback.invoke(callback.context);
}

pub fn acquire_grab(runtime: *Runtime) void {
    if (!runtime.is_open()) {
        return;
    }

    if (!runtime.grab_wanted.load(.seq_cst)) {
        return;
    }

    runtime.mode_raw.store(@backingInt(Mode.grab), .seq_cst);

    assert(runtime.mode() == .grab);
}

pub fn set_release_callback(runtime: *Runtime, callback: ?ReleaseCallback) void {
    runtime.release_callback = callback;
}

pub fn is_open(runtime: *const Runtime) bool {
    return runtime.opened.load(.seq_cst);
}

pub fn mode(runtime: *const Runtime) Mode {
    return @fromBackingInt(runtime.mode_raw.load(.seq_cst));
}

pub fn options(runtime: *const Runtime) Options {
    return Options{
        .mode = runtime.mode(),
        .synthesis = runtime.synthesis.load(.seq_cst),
        .rescue = runtime.rescue.load(.seq_cst),
    };
}

const testing = std.testing;

test "the runtime opens once and records what it was asked for" {
    var runtime: Runtime = .{};

    try testing.expect(!runtime.is_open());
    try testing.expectEqual(Mode.observe, runtime.mode());

    runtime.open(.{ .mode = .grab, .synthesis = false });

    try testing.expect(runtime.is_open());
    try testing.expectEqual(Mode.grab, runtime.mode());
    try testing.expect(!runtime.options().synthesis);

    runtime.close();

    try testing.expect(!runtime.is_open());
    try testing.expectEqual(Mode.observe, runtime.mode());
}
