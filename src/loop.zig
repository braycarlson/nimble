const std = @import("std");

const platform = @import("platform.zig");
const runtime = @import("runtime.zig");

const assert = std.debug.assert;

const backend = platform.backend.loop;

pub fn poll(timeout_ms: u32) bool {
    return backend.poll(timeout_ms);
}

pub fn run() void {
    assert(runtime.is_open());

    backend.run();
}

pub fn stop() void {
    backend.stop();
}

const testing = std.testing;

const mock = platform.mock;

test poll {
    mock.reset();

    try runtime.open(.{});
    defer runtime.close();

    mock.loop.push_advance(10);

    try testing.expect(poll(0));
    try testing.expect(!poll(0));
}

test run {
    mock.reset();

    try runtime.open(.{});
    defer runtime.close();

    mock.loop.push_advance(10);
    mock.loop.push_advance(10);

    run();

    try testing.expectEqual(@as(u16, 0), mock.loop.pending());
}

test stop {
    mock.reset();

    try runtime.open(.{});
    defer runtime.close();

    mock.loop.push_advance(10);

    stop();

    try testing.expect(!poll(0));
    try testing.expectEqual(@as(u16, 1), mock.loop.pending());
}
