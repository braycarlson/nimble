const std = @import("std");
const input = @import("input");

const timed_mod = input.registry.timed;
const key_event = input.event.key;
const response_mod = input.response;

const Mode = timed_mod.Mode;
const Options = timed_mod.Options;
const Key = key_event.Key;
const Response = response_mod.Response;

const testing = std.testing;

fn timed_callback(_: *anyopaque, _: *const Key) Response {
    return .consume;
}

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
    try testing.expectEqual(@as(u32, 0), opts.count_limit);
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
    try testing.expectEqual(@as(u32, 100), opts.count_limit);
}

test "timed constants" {
    try testing.expect(timed_mod.capacity_default <= timed_mod.capacity_max);
    try testing.expect(timed_mod.duration_max_ms > 0);
    try testing.expect(timed_mod.count_max > 0);
}

test "TimedRegistry: register accepts count_limit at count_max" {
    var registry = timed_mod.TimedRegistry(4).init();
    var context: u32 = 0;

    const id = try registry.register(
        1,
        timed_callback,
        &context,
        Options.count(timed_mod.count_max),
    );

    try testing.expect(id >= 1);
    try testing.expect(registry.is_valid());
}

test "TimedRegistry: register rejects count_limit above count_max" {
    var registry = timed_mod.TimedRegistry(4).init();
    var context: u32 = 0;

    const result = registry.register(
        1,
        timed_callback,
        &context,
        Options.count(timed_mod.count_max + 1),
    );

    try testing.expectError(error.InvalidValue, result);
    try testing.expect(registry.is_valid());
}

test "TimedRegistry: register rejects zero count_limit" {
    var registry = timed_mod.TimedRegistry(4).init();
    var context: u32 = 0;

    const result = registry.register(
        1,
        timed_callback,
        &context,
        Options.count(0),
    );

    try testing.expectError(error.InvalidValue, result);
}
