const std = @import("std");
const input = @import("input");

const repeat = input.automation.repeat;

const RepeatRegistry = repeat.RepeatRegistry;
const Entry = repeat.Entry;
const Options = repeat.Options;

const TestContext = struct {
    invoke_count: u32 = 0,
    last_count: u32 = 0,

    fn callback(ctx: *anyopaque, count: u32) void {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.invoke_count += 1;
        self.last_count = count;
    }
};

test "RepeatRegistry: init creates valid registry" {
    var registry = RepeatRegistry(8).init();

    try std.testing.expect(registry.is_valid());
}

test "RepeatRegistry: register with valid options" {
    var registry = RepeatRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(
        1,
        TestContext.callback,
        &ctx,
        Options{
            .interval_ms = 100,
            .initial_delay_ms = 0,
        },
    );

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "RepeatRegistry: register multiple entries" {
    var registry = RepeatRegistry(8).init();
    var ctx1 = TestContext{};
    var ctx2 = TestContext{};

    const id1 = try registry.register(1, TestContext.callback, &ctx1, Options{});
    const id2 = try registry.register(2, TestContext.callback, &ctx2, Options{});

    try std.testing.expect(id1 != id2);
    try std.testing.expect(registry.is_valid());
}

test "RepeatRegistry: registry full error" {
    var registry = RepeatRegistry(2).init();
    var ctx = TestContext{};

    _ = try registry.register(1, TestContext.callback, &ctx, Options{});
    _ = try registry.register(2, TestContext.callback, &ctx, Options{});

    const result = registry.register(3, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.RegistryFull, result);
}

test "RepeatRegistry: unregister entry" {
    var registry = RepeatRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, TestContext.callback, &ctx, Options{});

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "RepeatRegistry: unregister not found error" {
    var registry = RepeatRegistry(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.NotFound, result);
}

test "RepeatRegistry: invalid interval error - too small" {
    var registry = RepeatRegistry(8).init();
    var ctx = TestContext{};

    const result = registry.register(1, TestContext.callback, &ctx, Options{
        .interval_ms = 1,
    });

    try std.testing.expectError(error.InvalidValue, result);
}

test "RepeatRegistry: invalid interval error - too large" {
    var registry = RepeatRegistry(8).init();
    var ctx = TestContext{};

    const result = registry.register(1, TestContext.callback, &ctx, Options{
        .interval_ms = repeat.interval_max_ms + 1,
    });

    try std.testing.expectError(error.InvalidValue, result);
}

test "RepeatRegistry: invalid initial delay error" {
    var registry = RepeatRegistry(8).init();
    var ctx = TestContext{};

    const result = registry.register(1, TestContext.callback, &ctx, Options{
        .interval_ms = 100,
        .initial_delay_ms = repeat.initial_delay_max_ms + 1,
    });

    try std.testing.expectError(error.InvalidValue, result);
}

test "RepeatRegistry: stop_all clears all entries" {
    var registry = RepeatRegistry(8).init();
    var ctx = TestContext{};

    _ = try registry.register(1, TestContext.callback, &ctx, Options{});
    _ = try registry.register(2, TestContext.callback, &ctx, Options{});

    registry.stop_all();

    try std.testing.expect(registry.is_valid());
}

test "Options: default values" {
    const opts = Options{};

    try std.testing.expectEqual(@as(u32, 100), opts.interval_ms);
    try std.testing.expectEqual(@as(u32, 0), opts.initial_delay_ms);
}

test "Options: custom values" {
    const opts = Options{
        .interval_ms = 250,
        .initial_delay_ms = 50,
    };

    try std.testing.expectEqual(@as(u32, 250), opts.interval_ms);
    try std.testing.expectEqual(@as(u32, 50), opts.initial_delay_ms);
}

test "Entry: default state" {
    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.get_id());
    try std.testing.expect(entry.get_callback() == null);
    try std.testing.expect(entry.get_context() == null);
    try std.testing.expect(!entry.is_active());
    try std.testing.expectEqual(@as(u32, 100), entry.interval_ms);
    try std.testing.expectEqual(@as(u32, 0), entry.initial_delay_ms);
}

test "Entry: is_valid for inactive entry" {
    const entry = Entry{};

    try std.testing.expect(entry.is_valid());
}

test "constants: valid ranges" {
    try std.testing.expect(repeat.capacity_default >= 1);
    try std.testing.expect(repeat.capacity_max >= repeat.capacity_default);
    try std.testing.expect(repeat.capacity_max <= 64);

    try std.testing.expect(repeat.interval_min_ms >= 1);
    try std.testing.expect(repeat.interval_max_ms > repeat.interval_min_ms);

    try std.testing.expectEqual(@as(u32, 0), repeat.initial_delay_default_ms);
    try std.testing.expect(repeat.initial_delay_max_ms >= repeat.initial_delay_default_ms);

    try std.testing.expect(repeat.count_max >= 1);
}
