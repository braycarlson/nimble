const std = @import("std");
const input = @import("input");

const timer_registry = input.registry.timer;

const TimerRegistry = timer_registry.TimerRegistry;
const Options = timer_registry.Options;
const Entry = timer_registry.Entry;

const TestContext = struct {
    invoked: bool = false,
    invoke_count: u32 = 0,

    fn callback(ctx: *anyopaque) void {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.invoked = true;
        self.invoke_count += 1;
    }
};

test "TimerRegistry: init creates valid registry" {
    var registry = TimerRegistry(8).init();

    try std.testing.expect(registry.is_valid());
}

test "TimerRegistry: register timer" {
    var registry = TimerRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(
        1000,
        TestContext.callback,
        &ctx,
        Options{},
    );

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "TimerRegistry: register with options" {
    var registry = TimerRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(
        500,
        TestContext.callback,
        &ctx,
        Options{
            .binding_id = 10,
            .repeat = false,
        },
    );

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "TimerRegistry: register multiple timers" {
    var registry = TimerRegistry(8).init();
    var ctx1 = TestContext{};
    var ctx2 = TestContext{};
    var ctx3 = TestContext{};

    const id1 = try registry.register(100, TestContext.callback, &ctx1, Options{});
    const id2 = try registry.register(200, TestContext.callback, &ctx2, Options{});
    const id3 = try registry.register(300, TestContext.callback, &ctx3, Options{});

    try std.testing.expect(id1 != id2);
    try std.testing.expect(id2 != id3);
    try std.testing.expect(id1 != id3);
    try std.testing.expect(registry.is_valid());
}

test "TimerRegistry: registry full error" {
    var registry = TimerRegistry(2).init();
    var ctx = TestContext{};

    _ = try registry.register(100, TestContext.callback, &ctx, Options{});
    _ = try registry.register(200, TestContext.callback, &ctx, Options{});

    const result = registry.register(300, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.RegistryFull, result);
}

test "TimerRegistry: invalid interval error" {
    var registry = TimerRegistry(8).init();
    var ctx = TestContext{};

    const too_small = registry.register(1, TestContext.callback, &ctx, Options{});
    try std.testing.expectError(error.InvalidValue, too_small);

    const too_large = registry.register(timer_registry.interval_max_ms + 1, TestContext.callback, &ctx, Options{});
    try std.testing.expectError(error.InvalidValue, too_large);
}

test "TimerRegistry: unregister timer" {
    var registry = TimerRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(100, TestContext.callback, &ctx, Options{});

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "TimerRegistry: unregister not found error" {
    var registry = TimerRegistry(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.NotFound, result);
}

test "TimerRegistry: start timer" {
    var registry = TimerRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(100, TestContext.callback, &ctx, Options{});

    try registry.start(id);

    try std.testing.expect(registry.is_running(id) orelse false);
}

test "TimerRegistry: start not found error" {
    var registry = TimerRegistry(8).init();

    const result = registry.start(999);

    try std.testing.expectError(error.NotFound, result);
}

test "TimerRegistry: stop timer" {
    var registry = TimerRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(100, TestContext.callback, &ctx, Options{});

    try registry.start(id);
    try registry.stop(id);

    try std.testing.expect(!(registry.is_running(id) orelse true));
}

test "TimerRegistry: stop not found error" {
    var registry = TimerRegistry(8).init();

    const result = registry.stop(999);

    try std.testing.expectError(error.NotFound, result);
}

test "TimerRegistry: is_running returns correct state" {
    var registry = TimerRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(100, TestContext.callback, &ctx, Options{});

    try std.testing.expect(!(registry.is_running(id) orelse true));

    try registry.start(id);

    try std.testing.expect(registry.is_running(id) orelse false);
}

test "TimerRegistry: is_running returns null for invalid id" {
    var registry = TimerRegistry(8).init();

    try std.testing.expect(registry.is_running(999) == null);
}

test "TimerRegistry: has_fired returns correct state" {
    var registry = TimerRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(100, TestContext.callback, &ctx, Options{});

    try std.testing.expect(!(registry.has_fired(id) orelse true));
}

test "TimerRegistry: has_fired returns null for invalid id" {
    var registry = TimerRegistry(8).init();

    try std.testing.expect(registry.has_fired(999) == null);
}

test "TimerRegistry: clear removes all timers" {
    var registry = TimerRegistry(8).init();
    var ctx = TestContext{};

    const id1 = try registry.register(100, TestContext.callback, &ctx, Options{});
    const id2 = try registry.register(200, TestContext.callback, &ctx, Options{});

    registry.clear();

    try std.testing.expect(registry.is_running(id1) == null);
    try std.testing.expect(registry.is_running(id2) == null);
    try std.testing.expect(registry.is_valid());
}

test "Options: default values" {
    const opts = Options{};

    try std.testing.expectEqual(@as(u32, 0), opts.binding_id);
    try std.testing.expect(opts.repeat);
}

test "Options: custom values" {
    const opts = Options{
        .binding_id = 42,
        .repeat = false,
    };

    try std.testing.expectEqual(@as(u32, 42), opts.binding_id);
    try std.testing.expect(!opts.repeat);
}

test "Entry: default state" {
    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.get_id());
    try std.testing.expect(entry.get_callback() == null);
    try std.testing.expect(entry.get_context() == null);
    try std.testing.expect(!entry.is_active());
    try std.testing.expectEqual(@as(u32, 1000), entry.interval_ms);
    try std.testing.expect(entry.repeat);
    try std.testing.expect(!entry.fired);
    try std.testing.expect(!entry.running);
}

test "Entry: is_valid for inactive entry" {
    const entry = Entry{};

    try std.testing.expect(entry.is_valid());
}

test "Entry: get methods with context" {
    var ctx = TestContext{};

    const entry = Entry{
        .base = .{
            .id = 42,
            .callback = TestContext.callback,
            .context = &ctx,
            .active = true,
        },
        .binding_id = 10,
        .interval_ms = 500,
        .repeat = false,
        .fired = false,
        .running = true,
        .last_tick = 0,
    };

    try std.testing.expectEqual(@as(u32, 42), entry.get_id());
    try std.testing.expect(entry.get_callback() != null);
    try std.testing.expect(entry.get_context() != null);
    try std.testing.expect(entry.is_active());
    try std.testing.expectEqual(@as(u32, 500), entry.interval_ms);
    try std.testing.expect(!entry.repeat);
}

test "constants: valid ranges" {
    try std.testing.expect(timer_registry.capacity_default >= 1);
    try std.testing.expect(timer_registry.capacity_max >= timer_registry.capacity_default);
    try std.testing.expect(timer_registry.interval_min_ms >= 1);
    try std.testing.expect(timer_registry.interval_max_ms > timer_registry.interval_min_ms);
}
