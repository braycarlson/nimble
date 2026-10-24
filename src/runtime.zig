const std = @import("std");

const platform = @import("platform.zig");
const response_mod = @import("response.zig");

const assert = std.debug.assert;

const backend = platform.backend.runtime;

const Response = response_mod.Response;

pub const Mode = backend.Mode;
pub const Options = backend.Options;
pub const ReleaseCallback = *const fn () void;

pub const PlatformError = error{
    DevicesMissing,
    EpollFailed,
    InputGroupMissing,
    SynthesisUnavailable,
    UinputInaccessible,
};

pub const RequestError = error{
    DisplayInvalid,
    RuntimeOpen,
};

pub fn open(options: Options) (PlatformError || RequestError)!void {
    assert(options.is_valid());

    try backend.open(options);

    assert(is_open());
    assert(mode() == options.mode);
}

pub fn close() void {
    backend.close();

    assert(!is_open());
}

pub fn is_open() bool {
    return backend.is_open();
}

pub fn mode() Mode {
    return backend.mode();
}

pub fn observes() bool {
    return backend.mode() == .observe;
}

pub fn release_grab() void {
    backend.release_grab();

    assert(observes());
}

pub fn acquire_grab() void {
    backend.acquire_grab();
}

pub fn set_release_callback(callback: ?ReleaseCallback) void {
    backend.set_release_callback(callback);
}

pub fn clamp(response: Response) Response {
    assert(response.is_valid());

    if (observes()) {
        return .pass;
    }

    return response;
}

const testing = std.testing;

const mock = platform.mock;

test Mode {
    mock.reset();

    try open(.{ .mode = .observe });
    defer close();

    try testing.expectEqual(Mode.observe, mode());
    try testing.expectEqual(Response.pass, clamp(.consume));
}

test Options {
    const defaults = Options{};

    try testing.expectEqual(Mode.observe, defaults.mode);
    try testing.expect(defaults.synthesis);
    try testing.expect(defaults.rescue);
    try testing.expect(defaults.wayland_display == null);
    try testing.expect(defaults.is_valid());
}

test open {
    mock.reset();

    try open(.{ .mode = .grab });
    defer close();

    try testing.expect(is_open());
    try testing.expectEqual(Mode.grab, mode());
    try testing.expectError(error.RuntimeOpen, open(.{}));
}

test close {
    mock.reset();

    try open(.{});

    close();

    try testing.expect(!is_open());
    try testing.expectEqual(Mode.observe, mode());
}

test is_open {
    mock.reset();

    try testing.expect(!is_open());

    try open(.{});
    defer close();

    try testing.expect(is_open());
}

test mode {
    mock.reset();

    try open(.{ .mode = .grab });
    defer close();

    try testing.expectEqual(Mode.grab, mode());

    release_grab();

    try testing.expectEqual(Mode.observe, mode());
}

test release_grab {
    mock.reset();

    try open(.{ .mode = .grab });
    defer close();

    release_grab();

    try testing.expectEqual(Mode.observe, mode());
    try testing.expectEqual(Response.pass, clamp(.consume));
}

test acquire_grab {
    mock.reset();

    try open(.{ .mode = .grab });
    defer close();

    release_grab();
    acquire_grab();

    try testing.expectEqual(Mode.grab, mode());
    try testing.expectEqual(Response.consume, clamp(.consume));
}

test set_release_callback {
    mock.reset();

    const Released = struct {
        var count: u32 = 0;

        fn on_released() void {
            count += 1;
        }
    };

    Released.count = 0;

    set_release_callback(Released.on_released);
    defer set_release_callback(null);

    try open(.{ .mode = .grab });
    defer close();

    release_grab();

    try testing.expectEqual(@as(u32, 1), Released.count);
}

test "observe mode cannot eat input" {
    mock.reset();

    try testing.expect(observes());
    try testing.expectEqual(Response.pass, clamp(.pass));
    try testing.expectEqual(Response.pass, clamp(.consume));
}

test "the public runtime speaks the backend vocabulary" {
    try testing.expectEqual(backend.Mode, Mode);
    try testing.expectEqual(backend.Options, Options);
}
