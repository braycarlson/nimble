const std = @import("std");
const input = @import("input");

const timer_mod = input.timer;

const Entry = timer_mod.Entry;
const Error = timer_mod.Error;

const testing = std.testing;

test "Entry default" {
    const entry = Entry{};

    try testing.expectEqual(@as(u32, 0), entry.id);
    try testing.expect(entry.callback == null);
    try testing.expect(entry.context == null);
    try testing.expectEqual(@as(u32, 1000), entry.interval_ms);
    try testing.expect(entry.repeat);
    try testing.expect(!entry.active);
    try testing.expect(!entry.fired);
    try testing.expect(!entry.running);
}

test "Entry.is_active" {
    const inactive = Entry{};
    const active = Entry{ .active = true };

    try testing.expect(!inactive.is_active());
    try testing.expect(active.is_active());
}

test "Entry.get_id" {
    const entry = Entry{ .id = 42 };

    try testing.expectEqual(@as(u32, 42), entry.get_id());
}

test "Entry.is_valid inactive" {
    const entry = Entry{};

    try testing.expect(entry.is_valid());
}

fn dummy_callback(_: *anyopaque, _: u32) void {}

test "Entry.is_valid active valid" {
    var ctx: u32 = 0;
    const entry = Entry{
        .id = 1,
        .callback = dummy_callback,
        .context = &ctx,
        .interval_ms = 100,
        .active = true,
    };

    try testing.expect(entry.is_valid());
}

test "Entry.is_valid active no callback" {
    const entry = Entry{
        .id = 1,
        .callback = null,
        .interval_ms = 100,
        .active = true,
    };

    try testing.expect(!entry.is_valid());
}

test "Entry.is_valid interval too low" {
    var ctx: u32 = 0;
    const entry = Entry{
        .id = 1,
        .callback = dummy_callback,
        .context = &ctx,
        .interval_ms = 1,
        .active = true,
    };

    try testing.expect(!entry.is_valid());
}

test "Entry.is_valid interval too high" {
    var ctx: u32 = 0;
    const entry = Entry{
        .id = 1,
        .callback = dummy_callback,
        .context = &ctx,
        .interval_ms = timer_mod.interval_max_ms + 1,
        .active = true,
    };

    try testing.expect(!entry.is_valid());
}

test "Entry.is_valid id zero" {
    var ctx: u32 = 0;
    const entry = Entry{
        .id = 0,
        .callback = dummy_callback,
        .context = &ctx,
        .interval_ms = 100,
        .active = true,
    };

    try testing.expect(!entry.is_valid());
}

test "TimerRegistry.init" {
    const Registry = timer_mod.TimerRegistry(8);
    const reg = Registry.init();

    try testing.expect(reg.is_valid());
    try testing.expect(reg.enabled);
}

test "TimerRegistry.register" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();
    var ctx: u32 = 0;

    const id = try reg.register(100, dummy_callback, &ctx, true);

    try testing.expect(id >= 1);
    try testing.expect(reg.is_valid());
}

test "TimerRegistry.register invalid interval low" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();
    var ctx: u32 = 0;

    const result = reg.register(1, dummy_callback, &ctx, true);

    try testing.expectError(Error.InvalidValue, result);
}

test "TimerRegistry.register invalid interval high" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();
    var ctx: u32 = 0;

    const result = reg.register(timer_mod.interval_max_ms + 1, dummy_callback, &ctx, true);

    try testing.expectError(Error.InvalidValue, result);
}

test "TimerRegistry.unregister" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();
    var ctx: u32 = 0;

    const id = try reg.register(100, dummy_callback, &ctx, true);
    try reg.unregister(id);

    try testing.expect(reg.is_valid());
}

test "TimerRegistry.unregister not found" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();

    const result = reg.unregister(999);

    try testing.expectError(Error.NotFound, result);
}

test "TimerRegistry.start" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();
    var ctx: u32 = 0;

    const id = try reg.register(100, dummy_callback, &ctx, true);
    try reg.start(id);

    const running = reg.is_running(id);

    try testing.expect(running != null);
    try testing.expect(running.?);
}

test "TimerRegistry.start not found" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();

    const result = reg.start(999);

    try testing.expectError(Error.NotFound, result);
}

test "TimerRegistry.start already active" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();
    var ctx: u32 = 0;

    const id = try reg.register(100, dummy_callback, &ctx, true);
    try reg.start(id);

    const result = reg.start(id);

    try testing.expectError(Error.AlreadyActive, result);
}

test "TimerRegistry.stop" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();
    var ctx: u32 = 0;

    const id = try reg.register(100, dummy_callback, &ctx, true);
    try reg.start(id);
    try reg.stop(id);

    const running = reg.is_running(id);

    try testing.expect(running != null);
    try testing.expect(!running.?);
}

test "TimerRegistry.stop not found" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();

    const result = reg.stop(999);

    try testing.expectError(Error.NotFound, result);
}

test "TimerRegistry.stop not active" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();
    var ctx: u32 = 0;

    const id = try reg.register(100, dummy_callback, &ctx, true);

    const result = reg.stop(id);

    try testing.expectError(Error.NotActive, result);
}

test "TimerRegistry.is_running" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();
    var ctx: u32 = 0;

    const id = try reg.register(100, dummy_callback, &ctx, true);

    try testing.expect(!(reg.is_running(id).?));

    try reg.start(id);

    try testing.expect(reg.is_running(id).?);
}

test "TimerRegistry.is_running not found" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();

    try testing.expect(reg.is_running(999) == null);
}

test "TimerRegistry.set_enabled" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();

    try testing.expect(reg.enabled);

    reg.set_enabled(false);

    try testing.expect(!reg.enabled);

    reg.set_enabled(true);

    try testing.expect(reg.enabled);
}

test "TimerRegistry.clear" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();
    var ctx: u32 = 0;

    _ = try reg.register(100, dummy_callback, &ctx, true);
    _ = try reg.register(200, dummy_callback, &ctx, false);

    reg.clear();

    try testing.expect(reg.is_valid());
}

test "TimerRegistry capacity" {
    const Registry = timer_mod.TimerRegistry(2);
    var reg = Registry.init();
    var ctx: u32 = 0;

    _ = try reg.register(100, dummy_callback, &ctx, true);
    _ = try reg.register(200, dummy_callback, &ctx, true);

    const result = reg.register(300, dummy_callback, &ctx, true);

    try testing.expectError(Error.RegistryFull, result);
}

test "TimerRegistry multiple registers and unregisters" {
    const Registry = timer_mod.TimerRegistry(4);
    var reg = Registry.init();
    var ctx: u32 = 0;

    const id1 = try reg.register(100, dummy_callback, &ctx, true);
    const id2 = try reg.register(200, dummy_callback, &ctx, true);
    const id3 = try reg.register(300, dummy_callback, &ctx, true);

    try reg.unregister(id2);

    const id4 = try reg.register(400, dummy_callback, &ctx, true);

    try testing.expect(id1 != id4);
    try testing.expect(id2 != id4);
    try testing.expect(id3 != id4);
}

test "TimerRegistry register with repeat false" {
    const Registry = timer_mod.TimerRegistry(8);
    var reg = Registry.init();
    var ctx: u32 = 0;

    const id = try reg.register(100, dummy_callback, &ctx, false);

    try testing.expect(id >= 1);
}
