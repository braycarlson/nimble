const std = @import("std");

const platform = @import("../platform.zig");

const base = @import("base.zig");
const entry_mod = @import("entry.zig");

const assert = std.debug.assert;

pub const capacity_max: u32 = 128;
pub const interval_ms_min: u32 = 10;
pub const interval_ms_max: u32 = 86400000;
const tick_interval_ms: u32 = 10;
pub const CapacityError = error{TimersExhausted};

pub const RequestError = error{
    HandleUnknown,
    IntervalInvalid,
    TimerRunning,
    TimerStopped,
};

pub const Callback = *const fn (context: *anyopaque) void;

pub const Entry = struct {
    base: entry_mod.BaseEntryType(Callback) = .{},
    interval_ms: u32 = 1000,
    repeat: bool = true,
    fired: bool = false,
    running: bool = false,
    tick_last: i64 = 0,

    pub fn get_id(entry: *const Entry) u32 {
        return entry.base.get_id();
    }

    pub fn get_callback(entry: *const Entry) ?Callback {
        return entry.base.get_callback();
    }

    pub fn get_context(entry: *const Entry) ?*anyopaque {
        return entry.base.get_context();
    }

    pub fn is_active(entry: *const Entry) bool {
        return entry.base.is_active();
    }

    pub fn is_valid(entry: *const Entry) bool {
        if (!entry.is_active()) {
            return true;
        }

        const valid_base = entry.base.is_base_valid();

        const valid_interval = entry.interval_ms >= interval_ms_min and
            entry.interval_ms <= interval_ms_max;

        return valid_base and valid_interval;
    }
};

pub const Options = struct {
    repeat: bool = true,
};

pub fn TimerRegistryType(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("TimerRegistryType capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("TimerRegistryType capacity exceeds maximum");
    }

    return struct {
        const Instance = @This();

        const Base = base.BaseRegistryType(Entry, capacity, .{
            .has_mutex = true,
        });

        base: Base = Base.init(),
        timer_id: platform.backend.timer.Id = 0,

        pub fn init() Instance {
            return Instance{};
        }

        pub fn is_valid(instance: *const Instance) bool {
            return instance.base.is_valid();
        }

        pub fn arm(instance: *Instance) void {
            if (instance.timer_id != 0) {
                return;
            }

            const started = platform.backend.timer.start(
                tick_interval_ms,
                &Instance.tick_static,
                instance,
            );

            instance.timer_id = started orelse 0;
        }

        fn tick_static(context: *anyopaque) void {
            const instance: *Instance = @ptrCast(@alignCast(context));

            instance.tick();
        }

        pub fn disarm(instance: *Instance) void {
            const timer_id = instance.timer_id;

            if (timer_id == 0) {
                return;
            }

            _ = platform.backend.timer.stop(timer_id);

            instance.timer_id = 0;
        }

        pub fn register(
            instance: *Instance,
            interval_ms: u32,
            callback: Callback,
            context: ?*anyopaque,
            options: Options,
        ) (CapacityError || RequestError)!u32 {
            if (interval_ms < interval_ms_min) return error.IntervalInvalid;
            if (interval_ms > interval_ms_max) return error.IntervalInvalid;

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const allocation = instance.base.allocate_locked() orelse {
                return error.TimersExhausted;
            };

            assert(allocation.slot < capacity);
            assert(allocation.id >= 1);

            instance.base.slot.entries[allocation.slot] = Entry{
                .base = .{
                    .id = allocation.id,
                    .callback = callback,
                    .context = context,
                    .active = true,
                },
                .interval_ms = interval_ms,
                .repeat = options.repeat,
                .fired = false,
                .running = false,
                .tick_last = 0,
            };

            assert(instance.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(instance: *Instance, id: u32) RequestError!void {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            const slot = instance.base.free_by_id_locked(id) orelse return error.HandleUnknown;

            assert(slot < capacity);
        }

        pub fn start(instance: *Instance, id: u32) RequestError!void {
            assert(instance.is_valid());
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            const slot = instance.base.find_by_id(id) orelse return error.HandleUnknown;

            if (instance.base.slot.entries[slot].running) {
                return error.TimerRunning;
            }

            instance.base.slot.entries[slot].running = true;
            instance.base.slot.entries[slot].tick_last = platform.backend.time.now_ms();
        }

        pub fn stop(instance: *Instance, id: u32) RequestError!void {
            assert(instance.is_valid());
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            const slot = instance.base.find_by_id(id) orelse return error.HandleUnknown;

            if (!instance.base.slot.entries[slot].running) {
                return error.TimerStopped;
            }

            instance.base.slot.entries[slot].running = false;
        }

        pub fn stop_all(instance: *Instance) void {
            assert(instance.is_valid());

            instance.base.lock();
            defer instance.base.unlock();

            const entries = instance.base.entries();

            for (entries) |*e| {
                if (!e.is_active()) continue;

                if (e.running) {
                    e.running = false;
                }
            }
        }

        pub fn is_running(instance: *Instance, id: u32) ?bool {
            assert(instance.is_valid());
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            const slot = instance.base.find_by_id(id) orelse return null;
            return instance.base.slot.entries[slot].running;
        }

        pub fn has_fired(instance: *Instance, id: u32) ?bool {
            assert(instance.is_valid());
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            const slot = instance.base.find_by_id(id) orelse return null;
            return instance.base.slot.entries[slot].fired;
        }

        pub fn tick(instance: *Instance) void {
            assert(instance.is_valid());

            var pending: [capacity]struct { callback: Callback, context: ?*anyopaque } = undefined;
            var pending_count: u32 = 0;

            {
                instance.base.lock();
                defer instance.base.unlock();

                const now: i64 = platform.backend.time.now_ms();
                const entries = instance.base.entries();

                for (entries) |*e| {
                    if (!e.is_active()) {
                        continue;
                    }

                    if (!e.running) {
                        continue;
                    }

                    if (now < e.tick_last) {
                        e.tick_last = now;

                        continue;
                    }

                    const elapsed: u64 = @intCast(now - e.tick_last);

                    if (elapsed >= e.interval_ms) {
                        if (e.get_callback()) |cb| {
                            assert(pending_count < capacity);

                            pending[pending_count] = .{
                                .callback = cb,
                                .context = e.get_context(),
                            };

                            pending_count += 1;
                        }

                        e.fired = true;
                        e.tick_last = now;

                        if (!e.repeat) {
                            e.running = false;
                        }
                    }
                }
            }

            assert(pending_count <= capacity);

            for (pending[0..pending_count]) |p| {
                if (p.context) |ctx| {
                    p.callback(ctx);
                }
            }
        }

        pub fn clear(instance: *Instance) void {
            assert(instance.is_valid());

            instance.base.clear();
        }
    };
}

const TestContext = struct {
    invoked: bool = false,
    invoke_count: u32 = 0,

    fn callback(ctx: *anyopaque) void {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.invoked = true;
        self.invoke_count += 1;
    }
};

test "a new timer registry is valid and empty" {
    var registry = TimerRegistryType(8).init();

    try std.testing.expect(registry.is_valid());
}

test "registering a timer stores it" {
    var registry = TimerRegistryType(8).init();
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

test "a registered timer keeps the options it was given" {
    var registry = TimerRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(
        500,
        TestContext.callback,
        &ctx,
        Options{
            .repeat = false,
        },
    );

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "several timers register side by side" {
    var registry = TimerRegistryType(8).init();
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

test "registering past capacity is an error" {
    var registry = TimerRegistryType(2).init();
    var ctx = TestContext{};

    _ = try registry.register(100, TestContext.callback, &ctx, Options{});
    _ = try registry.register(200, TestContext.callback, &ctx, Options{});

    const result = registry.register(300, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.TimersExhausted, result);
}

test "an out of range interval is an error" {
    var registry = TimerRegistryType(8).init();
    var ctx = TestContext{};

    const too_small = registry.register(1, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.IntervalInvalid, too_small);

    const too_large = registry.register(interval_ms_max + 1, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.IntervalInvalid, too_large);
}

test "starting a running timer and stopping an idle one are request errors" {
    var registry = TimerRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(100, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.TimerStopped, registry.stop(id));

    try registry.start(id);

    try std.testing.expectError(error.TimerRunning, registry.start(id));
}

test "unregistering a timer drops it" {
    var registry = TimerRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(100, TestContext.callback, &ctx, Options{});

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "unregistering an unknown timer is an error" {
    var registry = TimerRegistryType(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.HandleUnknown, result);
}

test "starting a timer marks it running" {
    var registry = TimerRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(100, TestContext.callback, &ctx, Options{});

    try registry.start(id);

    try std.testing.expect(registry.is_running(id) orelse false);
}

test "starting an unknown timer is an error" {
    var registry = TimerRegistryType(8).init();

    const result = registry.start(999);

    try std.testing.expectError(error.HandleUnknown, result);
}

test "stopping a timer marks it idle" {
    var registry = TimerRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(100, TestContext.callback, &ctx, Options{});

    try registry.start(id);
    try registry.stop(id);

    try std.testing.expect(!(registry.is_running(id) orelse true));
}

test "stopping an unknown timer is an error" {
    var registry = TimerRegistryType(8).init();

    const result = registry.stop(999);

    try std.testing.expectError(error.HandleUnknown, result);
}

test "is_running follows whether a timer is running" {
    var registry = TimerRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(100, TestContext.callback, &ctx, Options{});

    try std.testing.expect(!(registry.is_running(id) orelse true));

    try registry.start(id);

    try std.testing.expect(registry.is_running(id) orelse false);
}

test "is_running returns null for an unknown id" {
    var registry = TimerRegistryType(8).init();

    try std.testing.expect(registry.is_running(999) == null);
}

test "has_fired follows whether a timer has fired" {
    var registry = TimerRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(100, TestContext.callback, &ctx, Options{});

    try std.testing.expect(!(registry.has_fired(id) orelse true));
}

test "has_fired returns null for an unknown id" {
    var registry = TimerRegistryType(8).init();

    try std.testing.expect(registry.has_fired(999) == null);
}

test "clearing removes every timer" {
    var registry = TimerRegistryType(8).init();
    var ctx = TestContext{};

    const id1 = try registry.register(100, TestContext.callback, &ctx, Options{});
    const id2 = try registry.register(200, TestContext.callback, &ctx, Options{});

    registry.clear();

    try std.testing.expect(registry.is_running(id1) == null);
    try std.testing.expect(registry.is_running(id2) == null);
    try std.testing.expect(registry.is_valid());
}

test "timer options default to a repeating timer" {
    const opts = Options{};

    try std.testing.expect(opts.repeat);
}

test "timer options carry the values they are built with" {
    const opts = Options{
        .repeat = false,
    };

    try std.testing.expect(!opts.repeat);
}

test "a default timer entry_mod is inactive, idle, and unfired" {
    const entry_default = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry_default.get_id());
    try std.testing.expect(entry_default.get_callback() == null);
    try std.testing.expect(entry_default.get_context() == null);
    try std.testing.expect(!entry_default.is_active());
    try std.testing.expectEqual(@as(u32, 1000), entry_default.interval_ms);
    try std.testing.expect(entry_default.repeat);
    try std.testing.expect(!entry_default.fired);
    try std.testing.expect(!entry_default.running);
}

test "a default timer entry_mod is valid" {
    const entry_inactive = Entry{};

    try std.testing.expect(entry_inactive.is_valid());
}

test "a timer entry_mod reports the id, callback, and context it carries" {
    var ctx = TestContext{};

    const entry_context = Entry{
        .base = .{
            .id = 42,
            .callback = TestContext.callback,
            .context = &ctx,
            .active = true,
        },
        .interval_ms = 500,
        .repeat = false,
        .fired = false,
        .running = true,
        .tick_last = 0,
    };

    try std.testing.expectEqual(@as(u32, 42), entry_context.get_id());
    try std.testing.expect(entry_context.get_callback() != null);
    try std.testing.expect(entry_context.get_context() != null);
    try std.testing.expect(entry_context.is_active());
    try std.testing.expectEqual(@as(u32, 500), entry_context.interval_ms);
    try std.testing.expect(!entry_context.repeat);
}

test "constants: valid ranges" {
    try std.testing.expect(capacity_max >= 1);
    try std.testing.expect(interval_ms_min >= 1);
    try std.testing.expect(interval_ms_max > interval_ms_min);
}
