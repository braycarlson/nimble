const std = @import("std");

const platform = @import("../platform.zig");

const base = @import("base.zig");
const entry_mod = @import("entry.zig");

const assert = std.debug.assert;

pub const capacity_default: u32 = 32;
pub const capacity_max: u32 = 128;
pub const interval_min_ms: u32 = 10;
pub const interval_max_ms: u32 = 86400000;
pub const tick_interval_ms: u32 = 10;

pub const Error = base.BaseError || error{
    AlreadyActive,
    InvalidValue,
    NotActive,
    SetupFailed,
};

var global_instance: std.atomic.Value(?*anyopaque) = std.atomic.Value(?*anyopaque).init(null);
var global_timer_id: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
pub const Callback = *const fn (context: *anyopaque) void;

pub const Entry = struct {
    base: entry_mod.BaseEntryType(Callback) = .{},
    binding_id: u32 = 0,
    interval_ms: u32 = 1000,
    repeat: bool = true,
    fired: bool = false,
    running: bool = false,
    last_tick: i64 = 0,

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

    pub fn invoke(entry: *const Entry) void {
        _ = entry.base.invoke(.{});
    }

    pub fn is_valid(entry: *const Entry) bool {
        if (!entry.is_active()) {
            return true;
        }

        const valid_base = entry.base.is_base_valid();
        const valid_interval = entry.interval_ms >= interval_min_ms and
            entry.interval_ms <= interval_max_ms;

        return valid_base and valid_interval;
    }
};

pub const Options = struct {
    binding_id: u32 = 0,
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

        pub fn init() Instance {
            return Instance{};
        }

        pub fn is_valid(instance: *const Instance) bool {
            return instance.base.is_valid();
        }

        pub fn set_global(instance: *Instance) void {
            const owner = global_instance.load(.seq_cst);
            const self_ptr: *anyopaque = @ptrCast(instance);

            assert(owner == null or owner == self_ptr);

            global_instance.store(self_ptr, .seq_cst);

            if (global_timer_id.load(.seq_cst) == 0) {
                const started = platform.backend.timer.start(
                    tick_interval_ms,
                    &Instance.tick_static,
                );

                const timer_id = started orelse 0;

                global_timer_id.store(timer_id, .seq_cst);
            }

            assert(global_instance.load(.seq_cst) == self_ptr);
        }

        fn tick_static() void {
            const instance = global_instance.load(.seq_cst);

            if (instance) |ptr| {
                const self: *Instance = @ptrCast(@alignCast(ptr));

                self.tick();
            }
        }

        pub fn clear_global(instance: *Instance) void {
            const owner = global_instance.load(.seq_cst);

            if (owner == null) {
                return;
            }

            const self_ptr: *anyopaque = @ptrCast(instance);

            assert(owner == self_ptr);

            const timer_id = global_timer_id.load(.seq_cst);

            if (timer_id != 0) {
                _ = platform.backend.timer.stop(timer_id);
            }

            global_timer_id.store(0, .seq_cst);
            global_instance.store(null, .seq_cst);
        }

        pub fn register(
            instance: *Instance,
            interval_ms: u32,
            callback: Callback,
            context: ?*anyopaque,
            options: Options,
        ) Error!u32 {
            if (interval_ms < interval_min_ms or interval_ms > interval_max_ms) {
                return Error.InvalidValue;
            }

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const allocation = instance.base.allocate_locked() catch return error.RegistryFull;

            assert(allocation.slot < capacity);
            assert(allocation.id >= 1);

            instance.base.slot.entries[allocation.slot] = Entry{
                .base = .{
                    .id = allocation.id,
                    .callback = callback,
                    .context = context,
                    .active = true,
                },
                .binding_id = options.binding_id,
                .interval_ms = interval_ms,
                .repeat = options.repeat,
                .fired = false,
                .running = false,
                .last_tick = 0,
            };

            assert(instance.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(instance: *Instance, id: u32) Error!void {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            _ = instance.base.free_by_id_locked(id) catch return error.NotFound;
        }

        pub fn start(instance: *Instance, id: u32) Error!void {
            assert(instance.is_valid());
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            const slot = instance.base.find_by_id(id) orelse return error.NotFound;

            if (instance.base.slot.entries[slot].running) {
                return error.AlreadyActive;
            }

            instance.base.slot.entries[slot].running = true;
            instance.base.slot.entries[slot].last_tick = platform.backend.time.now_ms();
        }

        pub fn stop(instance: *Instance, id: u32) Error!void {
            assert(instance.is_valid());
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            const slot = instance.base.find_by_id(id) orelse return error.NotFound;

            if (!instance.base.slot.entries[slot].running) {
                return error.NotActive;
            }

            instance.base.slot.entries[slot].running = false;
        }

        pub fn stop_all(instance: *Instance) void {
            assert(instance.is_valid());

            instance.base.lock();
            defer instance.base.unlock();

            const entries = instance.base.entries();

            for (entries) |*e| {
                if (e.is_active() and e.running) {
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

        pub fn process_binding(instance: *Instance, binding_id: u32, down: bool) void {
            assert(instance.is_valid());
            assert(binding_id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            const entries = instance.base.entries();

            for (entries) |*e| {
                if (!e.is_active()) {
                    continue;
                }

                if (e.binding_id != binding_id) {
                    continue;
                }

                if (down) {
                    if (!e.running) {
                        e.running = true;
                        e.fired = false;
                        e.last_tick = platform.backend.time.now_ms();
                    }
                } else {
                    e.running = false;
                }
            }
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

                    if (now < e.last_tick) {
                        e.last_tick = now;
                        continue;
                    }

                    const elapsed: u64 = @intCast(now - e.last_tick);

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
                        e.last_tick = now;

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
            .binding_id = 10,
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

    try std.testing.expectError(error.RegistryFull, result);
}

test "an out of range interval is an error" {
    var registry = TimerRegistryType(8).init();
    var ctx = TestContext{};

    const too_small = registry.register(1, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.InvalidValue, too_small);

    const too_large = registry.register(interval_max_ms + 1, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.InvalidValue, too_large);
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

    try std.testing.expectError(error.NotFound, result);
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

    try std.testing.expectError(error.NotFound, result);
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

    try std.testing.expectError(error.NotFound, result);
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

test "timer options default to a repeating timer with no binding" {
    const opts = Options{};

    try std.testing.expectEqual(@as(u32, 0), opts.binding_id);
    try std.testing.expect(opts.repeat);
}

test "timer options carry the values they are built with" {
    const opts = Options{
        .binding_id = 42,
        .repeat = false,
    };

    try std.testing.expectEqual(@as(u32, 42), opts.binding_id);
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
        .binding_id = 10,
        .interval_ms = 500,
        .repeat = false,
        .fired = false,
        .running = true,
        .last_tick = 0,
    };

    try std.testing.expectEqual(@as(u32, 42), entry_context.get_id());
    try std.testing.expect(entry_context.get_callback() != null);
    try std.testing.expect(entry_context.get_context() != null);
    try std.testing.expect(entry_context.is_active());
    try std.testing.expectEqual(@as(u32, 500), entry_context.interval_ms);
    try std.testing.expect(!entry_context.repeat);
}

test "constants: valid ranges" {
    try std.testing.expect(capacity_default >= 1);
    try std.testing.expect(capacity_max >= capacity_default);
    try std.testing.expect(interval_min_ms >= 1);
    try std.testing.expect(interval_max_ms > interval_min_ms);
}
