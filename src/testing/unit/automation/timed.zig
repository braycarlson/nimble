const std = @import("std");
const input = @import("input");

const timed_mod = input.automation.timed;

const Mode = timed_mod.Mode;
const Options = timed_mod.Options;

const testing = std.testing;

test "Mode.is_valid duration" {
    try testing.expect(Mode.duration.is_valid());
}

test "Mode.is_valid until_time" {
    try testing.expect(Mode.until_time.is_valid());
}

test "Mode.is_valid toggle" {
    try testing.expect(Mode.toggle.is_valid());
}

test "Mode.is_valid count_limited" {
    try testing.expect(Mode.count_limited.is_valid());
}

test "Mode enum values" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(Mode.duration));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(Mode.until_time));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(Mode.toggle));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(Mode.count_limited));
}

test "Options default" {
    const opts = Options{};

    try testing.expectEqual(Mode.toggle, opts.mode);
    try testing.expectEqual(@as(u64, 0), opts.duration_ms);
    try testing.expectEqual(@as(i64, 0), opts.end_time);
    try testing.expectEqual(@as(u32, 0), opts.max_count);
}

test "Options.duration" {
    const opts = Options.duration(5000);

    try testing.expectEqual(Mode.duration, opts.mode);
    try testing.expectEqual(@as(u64, 5000), opts.duration_ms);
}

test "Options.until" {
    const end_time: i64 = 1234567890;
    const opts = Options.until(end_time);

    try testing.expectEqual(Mode.until_time, opts.mode);
    try testing.expectEqual(end_time, opts.end_time);
}

test "Options.toggle_mode" {
    const opts = Options.toggle_mode();

    try testing.expectEqual(Mode.toggle, opts.mode);
}

test "Options.count" {
    const opts = Options.count(100);

    try testing.expectEqual(Mode.count_limited, opts.mode);
    try testing.expectEqual(@as(u32, 100), opts.max_count);
}

test "timed constants" {
    try testing.expect(timed_mod.capacity_default <= timed_mod.capacity_max);
    try testing.expect(timed_mod.duration_max_ms > 0);
    try testing.expect(timed_mod.count_max > 0);
}
