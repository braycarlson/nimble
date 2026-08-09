const std = @import("std");

const platform = @import("../platform.zig");

const base = @import("../registry/base.zig");
const entry_mod = @import("../registry/entry.zig");

const assert = std.debug.assert;

pub const capacity_default: u32 = 16;
pub const capacity_max: u32 = 64;
pub const interval_min_ms: u32 = 10;
pub const interval_max_ms: u32 = 60000;
pub const initial_delay_default_ms: u32 = 0;
pub const initial_delay_max_ms: u32 = 60000;
pub const count_max: u32 = 1000000;

pub const Error = base.BaseError || error{
    AlreadyActive,
    InvalidValue,
};

pub const Callback = *const fn (context: *anyopaque, count: u32) void;

pub const Entry = struct {
    base: entry_mod.BindingEntryType(Callback) = .{},
    initial_delay_ms: u32 = 0,
    interval_ms: u32 = 100,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,

    pub fn get_id(entry: *const Entry) u32 {
        return entry.base.get_id();
    }

    pub fn get_callback(entry: *const Entry) ?Callback {
        return entry.base.get_callback();
    }

    pub fn get_context(entry: *const Entry) ?*anyopaque {
        return entry.base.get_context();
    }

    pub fn get_binding_id(entry: *const Entry) u32 {
        return entry.base.get_binding_id();
    }

    pub fn is_active(entry: *const Entry) bool {
        return entry.base.is_active();
    }

    pub fn invoke(entry: *Entry, count_value: u32) void {
        _ = entry.base.invoke(.{count_value});
    }

    pub fn is_valid(entry: *const Entry) bool {
        if (!entry.is_active()) {
            return true;
        }

        const valid_base = entry.base.is_valid();
        const valid_interval = entry.interval_ms >= interval_min_ms and
            entry.interval_ms <= interval_max_ms;
        const valid_initial_delay = entry.initial_delay_ms <= initial_delay_max_ms;
        const valid_count = entry.count.load(.seq_cst) <= count_max;

        return valid_base and valid_interval and valid_initial_delay and valid_count;
    }
};

pub const Options = struct {
    interval_ms: u32 = 100,
    initial_delay_ms: u32 = 0,
};

const ThreadContext = struct {
    callback: ?Callback,
    context: ?*anyopaque,
    interval_ms: u32,
    initial_delay_ms: u32,
    stop_flag: *std.atomic.Value(bool),
};

pub fn RepeatRegistryType(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("RepeatRegistryType capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("RepeatRegistryType capacity exceeds maximum");
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

        pub fn register(
            instance: *Instance,
            binding_id: u32,
            callback: Callback,
            context: ?*anyopaque,
            options: Options,
        ) Error!u32 {
            assert(binding_id >= 1);

            if (options.interval_ms < interval_min_ms or options.interval_ms > interval_max_ms) {
                return Error.InvalidValue;
            }

            if (options.initial_delay_ms > initial_delay_max_ms) {
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
                    .base = .{
                        .id = allocation.id,
                        .callback = callback,
                        .context = context,
                        .active = true,
                    },
                    .binding_id = binding_id,
                    .enabled = true,
                },
                .initial_delay_ms = options.initial_delay_ms,
                .interval_ms = options.interval_ms,
                .running = std.atomic.Value(bool).init(false),
                .count = std.atomic.Value(u32).init(0),
                .stop_flag = std.atomic.Value(bool).init(false),
                .thread = null,
            };

            assert(instance.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(instance: *Instance, id: u32) Error!void {
            assert(id >= 1);

            var thread_to_join: ?std.Thread = null;

            {
                instance.base.lock();
                defer instance.base.unlock();

                assert(instance.is_valid());

                const entry = instance.base.get_by_id(id) orelse return error.NotFound;

                thread_to_join = instance.stop_entry(entry);
            }

            if (thread_to_join) |t| {
                t.join();
            }

            instance.base.lock();
            defer instance.base.unlock();

            _ = instance.base.free_by_id_locked(id) catch return error.NotFound;
        }

        pub fn process(instance: *Instance, binding_id: u32, down: bool) void {
            assert(binding_id >= 1);

            var threads_to_join: [capacity]?std.Thread = [_]?std.Thread{null} ** capacity;
            var thread_count: u32 = 0;

            {
                instance.base.lock();
                defer instance.base.unlock();

                assert(instance.is_valid());

                const entries = instance.base.entries();

                for (entries) |*e| {
                    if (!e.is_active()) {
                        continue;
                    }

                    if (e.get_binding_id() != binding_id) {
                        continue;
                    }

                    if (down) {
                        instance.start_entry(e);
                    } else {
                        if (instance.stop_entry(e)) |t| {
                            assert(thread_count < capacity);

                            threads_to_join[thread_count] = t;
                            thread_count += 1;
                        }
                    }
                }
            }

            assert(thread_count <= capacity);

            for (threads_to_join[0..thread_count]) |maybe_thread| {
                if (maybe_thread) |t| {
                    t.join();
                }
            }
        }

        pub fn stop_all(instance: *Instance) void {
            var threads_to_join: [capacity]?std.Thread = [_]?std.Thread{null} ** capacity;
            var thread_count: u32 = 0;

            {
                instance.base.lock();
                defer instance.base.unlock();

                assert(instance.is_valid());

                const entries = instance.base.entries();

                for (entries) |*e| {
                    if (!e.is_active()) {
                        continue;
                    }

                    if (instance.stop_entry(e)) |t| {
                        assert(thread_count < capacity);

                        threads_to_join[thread_count] = t;
                        thread_count += 1;
                    }
                }
            }

            for (threads_to_join[0..thread_count]) |maybe_thread| {
                if (maybe_thread) |t| {
                    t.join();
                }
            }
        }

        fn start_entry(instance: *Instance, entry: *Entry) void {
            _ = instance;

            assert(entry.is_active());
            assert(entry.interval_ms >= interval_min_ms);

            if (entry.running.load(.seq_cst)) {
                return;
            }

            entry.running.store(true, .seq_cst);
            entry.count.store(0, .seq_cst);
            entry.stop_flag.store(false, .seq_cst);

            const thread_context = ThreadContext{
                .callback = entry.get_callback(),
                .context = entry.get_context(),
                .interval_ms = entry.interval_ms,
                .initial_delay_ms = entry.initial_delay_ms,
                .stop_flag = &entry.stop_flag,
            };

            entry.thread = std.Thread.spawn(.{}, repeat_thread, .{thread_context}) catch {
                entry.running.store(false, .seq_cst);
                entry.thread = null;

                return;
            };
        }

        fn stop_entry(instance: *Instance, entry: *Entry) ?std.Thread {
            _ = instance;

            assert(entry.is_active());

            if (!entry.running.load(.seq_cst)) {
                return null;
            }

            entry.stop_flag.store(true, .seq_cst);

            const thread = entry.thread;
            entry.thread = null;
            entry.running.store(false, .seq_cst);

            return thread;
        }

        fn repeat_thread(thread_context: ThreadContext) void {
            assert(thread_context.interval_ms >= interval_min_ms);
            assert(thread_context.interval_ms <= interval_max_ms);

            if (thread_context.initial_delay_ms > 0) {
                platform.backend.time.sleep_ms(thread_context.initial_delay_ms);
            }

            var count_current: u32 = 0;

            while (!thread_context.stop_flag.load(.seq_cst)) {
                assert(count_current < count_max);

                if (thread_context.callback) |callback| {
                    if (thread_context.context) |context| {
                        callback(context, count_current);
                    }
                }

                count_current += 1;

                if (thread_context.stop_flag.load(.seq_cst)) {
                    break;
                }

                if (count_current >= count_max) {
                    break;
                }

                platform.backend.time.sleep_ms(thread_context.interval_ms);
            }
        }

        pub fn clear(instance: *Instance) void {
            var threads_to_join: [capacity]?std.Thread = [_]?std.Thread{null} ** capacity;
            var thread_count: u32 = 0;

            {
                instance.base.lock();
                defer instance.base.unlock();

                assert(instance.is_valid());

                const entries = instance.base.entries();

                for (entries) |*e| {
                    if (e.is_active()) {
                        if (instance.stop_entry(e)) |t| {
                            assert(thread_count < capacity);

                            threads_to_join[thread_count] = t;
                            thread_count += 1;
                        }
                    }
                }
            }

            assert(thread_count <= capacity);

            for (threads_to_join[0..thread_count]) |maybe_thread| {
                if (maybe_thread) |t| {
                    t.join();
                }
            }

            instance.base.lock();
            defer instance.base.unlock();

            instance.base.clear_locked();
        }
    };
}

const TestContext = struct {
    invoke_count: u32 = 0,
    last_count: u32 = 0,

    fn callback(ctx: *anyopaque, count: u32) void {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.invoke_count += 1;
        self.last_count = count;
    }
};

test "a new repeat registry is valid and empty" {
    var registry = RepeatRegistryType(8).init();

    try std.testing.expect(registry.is_valid());
}

test "registering with valid options stores the entry" {
    var registry = RepeatRegistryType(8).init();
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

test "several repeats register side by side" {
    var registry = RepeatRegistryType(8).init();
    var ctx1 = TestContext{};
    var ctx2 = TestContext{};

    const id1 = try registry.register(1, TestContext.callback, &ctx1, Options{});
    const id2 = try registry.register(2, TestContext.callback, &ctx2, Options{});

    try std.testing.expect(id1 != id2);
    try std.testing.expect(registry.is_valid());
}

test "registering past capacity is an error" {
    var registry = RepeatRegistryType(2).init();
    var ctx = TestContext{};

    _ = try registry.register(1, TestContext.callback, &ctx, Options{});
    _ = try registry.register(2, TestContext.callback, &ctx, Options{});

    const result = registry.register(3, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.RegistryFull, result);
}

test "unregistering a repeat drops it" {
    var registry = RepeatRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, TestContext.callback, &ctx, Options{});

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "unregistering an unknown repeat is an error" {
    var registry = RepeatRegistryType(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.NotFound, result);
}

test "an interval below the minimum is an error" {
    var registry = RepeatRegistryType(8).init();
    var ctx = TestContext{};

    const result = registry.register(1, TestContext.callback, &ctx, Options{
        .interval_ms = 1,
    });

    try std.testing.expectError(error.InvalidValue, result);
}

test "an interval above the maximum is an error" {
    var registry = RepeatRegistryType(8).init();
    var ctx = TestContext{};

    const result = registry.register(1, TestContext.callback, &ctx, Options{
        .interval_ms = interval_max_ms + 1,
    });

    try std.testing.expectError(error.InvalidValue, result);
}

test "an out of range initial delay is an error" {
    var registry = RepeatRegistryType(8).init();
    var ctx = TestContext{};

    const result = registry.register(1, TestContext.callback, &ctx, Options{
        .interval_ms = 100,
        .initial_delay_ms = initial_delay_max_ms + 1,
    });

    try std.testing.expectError(error.InvalidValue, result);
}

test "stopping all removes every repeat" {
    var registry = RepeatRegistryType(8).init();
    var ctx = TestContext{};

    _ = try registry.register(1, TestContext.callback, &ctx, Options{});
    _ = try registry.register(2, TestContext.callback, &ctx, Options{});

    registry.stop_all();

    try std.testing.expect(registry.is_valid());
}

test "repeat options start at their default values" {
    const opts = Options{};

    try std.testing.expectEqual(@as(u32, 100), opts.interval_ms);
    try std.testing.expectEqual(@as(u32, 0), opts.initial_delay_ms);
}

test "repeat options carry the values they are built with" {
    const opts = Options{
        .interval_ms = 250,
        .initial_delay_ms = 50,
    };

    try std.testing.expectEqual(@as(u32, 250), opts.interval_ms);
    try std.testing.expectEqual(@as(u32, 50), opts.initial_delay_ms);
}

test "a default repeat entry is inactive" {
    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.get_id());
    try std.testing.expect(entry.get_callback() == null);
    try std.testing.expect(entry.get_context() == null);
    try std.testing.expect(!entry.is_active());
    try std.testing.expectEqual(@as(u32, 100), entry.interval_ms);
    try std.testing.expectEqual(@as(u32, 0), entry.initial_delay_ms);
}

test "a default repeat entry is valid" {
    const entry = Entry{};

    try std.testing.expect(entry.is_valid());
}

test "constants: valid ranges" {
    try std.testing.expect(capacity_default >= 1);
    try std.testing.expect(capacity_max >= capacity_default);
    try std.testing.expect(capacity_max <= 64);

    try std.testing.expect(interval_min_ms >= 1);
    try std.testing.expect(interval_max_ms > interval_min_ms);

    try std.testing.expectEqual(@as(u32, 0), initial_delay_default_ms);
    try std.testing.expect(initial_delay_max_ms >= initial_delay_default_ms);

    try std.testing.expect(count_max >= 1);
}
