const std = @import("std");

const platform = @import("platform.zig");
const response_mod = @import("response.zig");

const assert = std.debug.assert;

const backend = platform.backend.runtime;

const Response = response_mod.Response;

pub const Mode = backend.Mode;
pub const Options = backend.Options;
pub const Error = backend.Error;
pub const ReleaseCallback = *const fn () void;

pub fn open(options: Options) Error!void {
    assert(options.is_valid());

    return backend.open(options);
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

test "observe mode cannot eat input" {
    close();

    try testing.expect(observes());
    try testing.expectEqual(Response.pass, clamp(.pass));
    try testing.expectEqual(Response.pass, clamp(.consume));
    try testing.expectEqual(Response.pass, clamp(.replace));
}

test "a closed runtime reports itself closed and observing" {
    close();

    try testing.expect(!is_open());
    try testing.expectEqual(Mode.observe, mode());
}

test "the public runtime speaks the backend vocabulary" {
    try testing.expectEqual(backend.Mode, Mode);
    try testing.expectEqual(backend.Options, Options);
}
