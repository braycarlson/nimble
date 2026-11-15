const std = @import("std");

const platform = @import("platform.zig");

const assert = std.debug.assert;

pub const sleep_ms_max: u32 = 1000 * 60 * 60;

comptime {
    assert(sleep_ms_max <= platform.sleep_ms_max);
}

pub fn now_ms(comptime Platform: type, backend: *const Platform) i64 {
    const result = backend.now_ms();

    assert(result >= 0);

    return result;
}

pub fn sleep_ms(comptime Platform: type, backend: *Platform, duration_ms: u32) void {
    assert(duration_ms <= sleep_ms_max);

    backend.sleep_ms(duration_ms);
}

const testing = std.testing;

const Fake = platform.Fake;

test now_ms {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    const before = now_ms(Fake, fake);

    sleep_ms(Fake, fake, 250);

    try testing.expectEqual(before + 250, now_ms(Fake, fake));
}

test sleep_ms {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    sleep_ms(Fake, fake, 1000);
    sleep_ms(Fake, fake, 0);

    try testing.expectEqual(@as(i64, 1000), now_ms(Fake, fake));
}
