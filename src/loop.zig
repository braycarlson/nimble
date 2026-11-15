const std = @import("std");

const platform = @import("platform.zig");

const assert = std.debug.assert;

pub const timeout_ms_max: u32 = std.math.maxInt(i32);

pub fn poll(comptime Platform: type, backend: *Platform, timeout_ms: u32) bool {
    const clamped = timeout_clamp(timeout_ms);
    assert(clamped <= timeout_ms_max);

    return backend.loop_poll(clamped);
}

fn timeout_clamp(timeout_ms: u32) u32 {
    const result = @min(timeout_ms, timeout_ms_max);
    assert(result <= timeout_ms_max);

    return result;
}

pub fn run(comptime Platform: type, backend: *Platform) void {
    assert(backend.runtime_mode().is_valid());

    backend.loop_run();
}

pub fn stop(comptime Platform: type, backend: *Platform) void {
    backend.loop_stop();
}

const testing = std.testing;

const Fake = platform.Fake;

test poll {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    fake.loop.push_advance(10);

    try testing.expect(poll(Fake, fake, 0));
    try testing.expect(!poll(Fake, fake, 0));
}

test "a timeout beyond the i32 range is clamped before it reaches a backend" {
    try testing.expectEqual(@as(u32, 0), timeout_clamp(0));
    try testing.expectEqual(timeout_ms_max, timeout_clamp(timeout_ms_max));
    try testing.expectEqual(timeout_ms_max, timeout_clamp(timeout_ms_max + 1));
    try testing.expectEqual(timeout_ms_max, timeout_clamp(std.math.maxInt(u32)));
}

test "a long timeout advances the fake clock by the clamped amount" {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    const before = fake.now_ms();

    try testing.expect(!poll(Fake, fake, std.math.maxInt(u32)));
    try testing.expectEqual(before + timeout_ms_max, fake.now_ms());
}

test run {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    fake.loop.push_advance(10);
    fake.loop.push_advance(10);

    run(Fake, fake);

    try testing.expectEqual(@as(u16, 0), fake.loop.pending());
}

test stop {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    fake.loop.push_advance(10);

    stop(Fake, fake);

    try testing.expect(!poll(Fake, fake, 0));
    try testing.expectEqual(@as(u16, 1), fake.loop.pending());
}
