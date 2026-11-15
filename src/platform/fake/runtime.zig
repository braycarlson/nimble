const std = @import("std");

const interface = @import("../interface.zig");

const assert = std.debug.assert;

const Mode = interface.Mode;
const Options = interface.Options;
const ReleaseCallback = interface.ReleaseCallback;

options: Options = .{},
grab_wanted: bool = false,
release_callback: ?ReleaseCallback = null,

const Runtime = @This();

pub fn init(options: Options) Runtime {
    assert(options.is_valid());

    const result = Runtime{
        .options = .{
            .mode = options.mode,
            .synthesis = options.synthesis,
            .rescue = options.rescue,
        },
        .grab_wanted = options.mode == .grab,
    };

    assert(result.options.wayland_display == null);
    assert(result.mode() == options.mode);

    return result;
}

pub fn release_grab(runtime: *Runtime) void {
    const was_grabbing = runtime.options.mode == .grab;

    runtime.options.mode = .observe;

    assert(runtime.mode() == .observe);

    if (!was_grabbing) {
        return;
    }

    const callback = runtime.release_callback orelse return;

    callback.invoke(callback.context);
}

pub fn acquire_grab(runtime: *Runtime) void {
    if (!runtime.grab_wanted) {
        return;
    }

    runtime.options.mode = .grab;

    assert(runtime.mode() == .grab);
}

pub fn set_release_callback(runtime: *Runtime, callback: ?ReleaseCallback) void {
    runtime.release_callback = callback;
}

pub fn mode(runtime: *const Runtime) Mode {
    assert(runtime.options.is_valid());

    return runtime.options.mode;
}

const testing = std.testing;

const Witness = struct {
    fired: u16 = 0,

    fn on_release(context: *anyopaque) void {
        const witness: *Witness = @ptrCast(@alignCast(context));

        witness.fired += 1;
    }
};

test "the fake runtime records the mode it was opened with" {
    var runtime = Runtime.init(.{ .mode = .grab, .synthesis = false });

    try testing.expectEqual(Mode.grab, runtime.mode());
    try testing.expect(!runtime.options.synthesis);

    runtime.release_grab();

    try testing.expectEqual(Mode.observe, runtime.mode());
}

test "releasing a grab notifies the registered callback exactly once" {
    var witness = Witness{};
    var runtime = Runtime.init(.{ .mode = .grab });

    runtime.set_release_callback(.{ .context = &witness, .invoke = Witness.on_release });

    runtime.release_grab();

    try testing.expectEqual(@as(u16, 1), witness.fired);
    try testing.expectEqual(Mode.observe, runtime.mode());

    runtime.release_grab();

    try testing.expectEqual(@as(u16, 1), witness.fired);

    runtime.acquire_grab();

    try testing.expectEqual(Mode.grab, runtime.mode());

    runtime.release_grab();

    try testing.expectEqual(@as(u16, 2), witness.fired);
}

test "an observe session never regrabs and never notifies" {
    var witness = Witness{};
    var runtime = Runtime.init(.{ .mode = .observe });

    runtime.set_release_callback(.{ .context = &witness, .invoke = Witness.on_release });

    runtime.release_grab();
    runtime.acquire_grab();

    try testing.expectEqual(@as(u16, 0), witness.fired);
    try testing.expectEqual(Mode.observe, runtime.mode());
}
