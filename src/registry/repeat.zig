const std = @import("std");

const keycode = @import("../keycode.zig");
const platform = @import("../platform.zig");

const base = @import("../registry/base.zig");
const entry_mod = @import("../registry/entry.zig");

const Condition = @import("../sync.zig").Condition;

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const capacity_max: u32 = 64;
pub const interval_ms_min: u32 = 10;
pub const interval_ms_max: u32 = 60000;
const delay_ms_initial_default: u32 = 0;
pub const delay_ms_initial_max: u32 = 60000;
const count_max: u32 = 1000000;
pub const CapacityError = error{RepeatsExhausted};

pub const RequestError = error{
    DelayInvalid,
    HandleUnknown,
    IntervalInvalid,
};

pub const Callback = *const fn (context: *anyopaque, count: u32) void;

pub const Entry = struct {
    base: entry_mod.BindingEntryType(Callback) = .{},
    key: Keycode = .silent,
    delay_ms_initial: u32 = 0,
    interval_ms: u32 = 100,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

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

    pub fn is_valid(entry: *const Entry) bool {
        if (!entry.is_active()) {
            return true;
        }

        const valid_base = entry.base.is_valid();

        const valid_interval = entry.interval_ms >= interval_ms_min and
            entry.interval_ms <= interval_ms_max;

        const valid_initial_delay = entry.delay_ms_initial <= delay_ms_initial_max;
        const valid_count = entry.count.load(.seq_cst) <= count_max;

        return valid_base and valid_interval and valid_initial_delay and valid_count;
    }
};

pub const Options = struct {
    key: Keycode = .silent,
    interval_ms: u32 = 100,
    delay_ms_initial: u32 = 0,
};

const ThreadContext = struct {
    callback: ?Callback,
    context: ?*anyopaque,
    interval_ms: u32,
    delay_ms_initial: u32,
    stop_flag: *std.atomic.Value(bool),
};

const Worker = struct {
    executing: bool = false,
    pending: bool = false,
    run: u32 = 0,
    thread: ?std.Thread = null,
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
        changed: Condition = .{},
        shutdown: bool = false,
        workers: [capacity]Worker = @splat(.{}),

        pub fn init() Instance {
            return Instance{};
        }

        pub fn start(instance: *Instance) std.Thread.SpawnError!void {
            assert(instance.is_valid());
            assert(!instance.shutdown);

            for (&instance.workers, 0..) |*worker, slot| {
                assert(worker.thread == null);

                const index: u32 = @intCast(slot);
                const arguments = .{ instance, index };

                worker.thread = std.Thread.spawn(.{}, worker_run, arguments) catch |err| {
                    instance.deinit();

                    return err;
                };
            }
        }

        pub fn deinit(instance: *Instance) void {
            assert(instance.is_valid());

            instance.stop_all();

            {
                instance.base.lock();
                defer instance.base.unlock();

                instance.shutdown = true;

                instance.changed.broadcast();
            }

            for (&instance.workers) |*worker| {
                if (worker.thread) |thread| {
                    thread.join();
                }

                worker.thread = null;
            }
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
        ) (CapacityError || RequestError)!u32 {
            assert(binding_id >= 1);

            if (options.interval_ms < interval_ms_min) return error.IntervalInvalid;
            if (options.interval_ms > interval_ms_max) return error.IntervalInvalid;

            if (options.delay_ms_initial > delay_ms_initial_max) {
                return error.DelayInvalid;
            }

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const allocation = instance.base.allocate_locked() orelse {
                return error.RepeatsExhausted;
            };

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
                .key = options.key,
                .delay_ms_initial = options.delay_ms_initial,
                .interval_ms = options.interval_ms,
                .running = std.atomic.Value(bool).init(false),
                .count = std.atomic.Value(u32).init(0),
                .stop_flag = std.atomic.Value(bool).init(false),
            };

            assert(instance.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(instance: *Instance, id: u32) RequestError!void {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const slot = instance.base.find_by_id(id) orelse return error.HandleUnknown;

            if (instance.stop_slot(slot)) |run| {
                instance.idle_wait(slot, run);
            }

            const freed = instance.base.free_by_id_locked(id) orelse return error.HandleUnknown;

            assert(freed == slot);
        }

        pub fn press(instance: *Instance, binding_id: u32) bool {
            assert(binding_id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            var matched = false;

            for (instance.base.entries(), 0..) |*entry, slot| {
                if (!entry.is_active()) {
                    continue;
                }

                if (entry.get_binding_id() != binding_id) {
                    continue;
                }

                instance.start_slot(@intCast(slot));

                matched = true;
            }

            return matched;
        }

        pub fn release(instance: *Instance, key: Keycode) void {
            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            var runs: [capacity]?u32 = @splat(null);

            for (instance.base.entries(), 0..) |*entry, slot| {
                if (!entry.is_active()) {
                    continue;
                }

                if (entry.key != key) {
                    continue;
                }

                runs[slot] = instance.stop_slot(@intCast(slot));
            }

            instance.idle_wait_all(&runs);
        }

        pub fn stop_all(instance: *Instance) void {
            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            var runs: [capacity]?u32 = @splat(null);

            for (instance.base.entries(), 0..) |*entry, slot| {
                if (!entry.is_active()) {
                    continue;
                }

                runs[slot] = instance.stop_slot(@intCast(slot));
            }

            instance.idle_wait_all(&runs);
        }

        pub fn is_running(instance: *Instance, id: u32) ?bool {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            const entry = instance.base.get_by_id(id) orelse return null;
            return entry.running.load(.seq_cst);
        }

        fn start_slot(instance: *Instance, slot: u32) void {
            assert(slot < capacity);

            const entry = &instance.base.slot.entries[slot];
            const worker = &instance.workers[slot];

            assert(entry.is_active());
            assert(entry.interval_ms >= interval_ms_min);
            assert(worker.thread != null);

            if (entry.running.load(.seq_cst)) {
                return;
            }

            if (worker.executing) {
                return;
            }

            entry.running.store(true, .seq_cst);
            entry.count.store(0, .seq_cst);
            entry.stop_flag.store(false, .seq_cst);
            worker.pending = true;

            instance.changed.broadcast();
        }

        fn stop_slot(instance: *Instance, slot: u32) ?u32 {
            assert(slot < capacity);

            const entry = &instance.base.slot.entries[slot];
            const worker = &instance.workers[slot];

            assert(entry.is_active());

            if (!entry.running.load(.seq_cst)) {
                return null;
            }

            entry.stop_flag.store(true, .seq_cst);
            entry.running.store(false, .seq_cst);
            worker.pending = false;

            if (!worker.executing) {
                return null;
            }

            return worker.run;
        }

        fn idle_wait(instance: *Instance, slot: u32, run: u32) void {
            assert(slot < capacity);

            const worker = &instance.workers[slot];

            while (worker.executing) {
                if (worker.run != run) break;

                instance.changed.wait(&instance.base.mutex);
            }
        }

        fn idle_wait_all(instance: *Instance, runs: *const [capacity]?u32) void {
            for (runs, 0..) |maybe_run, slot| {
                if (maybe_run) |run| {
                    instance.idle_wait(@intCast(slot), run);
                }
            }
        }

        fn worker_run(instance: *Instance, slot: u32) void {
            assert(slot < capacity);

            instance.base.lock();
            defer instance.base.unlock();

            const worker = &instance.workers[slot];

            while (!instance.shutdown) {
                assert(!worker.executing);

                if (!worker.pending) {
                    instance.changed.wait(&instance.base.mutex);

                    continue;
                }

                const entry = &instance.base.slot.entries[slot];

                const thread_context = ThreadContext{
                    .callback = entry.get_callback(),
                    .context = entry.get_context(),
                    .interval_ms = entry.interval_ms,
                    .delay_ms_initial = entry.delay_ms_initial,
                    .stop_flag = &entry.stop_flag,
                };

                worker.pending = false;
                worker.executing = true;
                worker.run +%= 1;

                instance.base.unlock();

                repeat_run(thread_context);

                instance.base.lock();
                worker.executing = false;

                instance.changed.broadcast();
            }
        }

        fn repeat_run(thread_context: ThreadContext) void {
            assert(thread_context.interval_ms >= interval_ms_min);
            assert(thread_context.interval_ms <= interval_ms_max);

            if (thread_context.delay_ms_initial > 0) {
                platform.backend.time.sleep_ms(thread_context.delay_ms_initial);
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
            instance.stop_all();

            instance.base.lock();
            defer instance.base.unlock();

            instance.base.clear_locked();
        }
    };
}

const invoke_wait_attempt_max: u32 = 1_000_000;

const TestContext = struct {
    invoke_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    count_last: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    fn callback(ctx: *anyopaque, count: u32) void {
        const self: *TestContext = @ptrCast(@alignCast(ctx));

        _ = self.invoke_count.fetchAdd(1, .seq_cst);

        self.count_last.store(count, .seq_cst);
    }
};

const ThreadRecord = struct {
    invoke_count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    thread_id: ?std.Thread.Id = null,

    fn callback(context: *anyopaque, count: u32) void {
        const record: *ThreadRecord = @ptrCast(@alignCast(context));

        assert(count < count_max);

        record.thread_id = std.Thread.getCurrentId();
        _ = record.invoke_count.fetchAdd(1, .seq_cst);
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
            .delay_ms_initial = 0,
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

    try std.testing.expectError(error.RepeatsExhausted, result);
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

    try std.testing.expectError(error.HandleUnknown, result);
}

test "an interval below the minimum is an error" {
    var registry = RepeatRegistryType(8).init();
    var ctx = TestContext{};

    const result = registry.register(1, TestContext.callback, &ctx, Options{
        .interval_ms = 1,
    });

    try std.testing.expectError(error.IntervalInvalid, result);
}

test "an interval above the maximum is an error" {
    var registry = RepeatRegistryType(8).init();
    var ctx = TestContext{};

    const result = registry.register(1, TestContext.callback, &ctx, Options{
        .interval_ms = interval_ms_max + 1,
    });

    try std.testing.expectError(error.IntervalInvalid, result);
}

test "an out of range initial delay is an error" {
    var registry = RepeatRegistryType(8).init();
    var ctx = TestContext{};

    const result = registry.register(1, TestContext.callback, &ctx, Options{
        .interval_ms = 100,
        .delay_ms_initial = delay_ms_initial_max + 1,
    });

    try std.testing.expectError(error.DelayInvalid, result);
}

test "a press starts the repeat and a release of its key stops it" {
    var registry = RepeatRegistryType(4).init();

    try registry.start();
    defer registry.deinit();

    var ctx = TestContext{};

    const id = try registry.register(7, TestContext.callback, &ctx, Options{
        .key = .j,
        .interval_ms = interval_ms_min,
    });

    try std.testing.expectEqual(false, registry.is_running(id).?);
    try std.testing.expect(!registry.press(8));
    try std.testing.expect(registry.press(7));
    try std.testing.expectEqual(true, registry.is_running(id).?);

    var attempt: u32 = 0;

    while (attempt < invoke_wait_attempt_max) : (attempt += 1) {
        if (ctx.invoke_count.load(.seq_cst) >= 1) break;

        std.Thread.yield() catch break;
    }

    registry.release(.k);

    try std.testing.expectEqual(true, registry.is_running(id).?);

    registry.release(.j);

    try std.testing.expectEqual(false, registry.is_running(id).?);
    try std.testing.expect(ctx.invoke_count.load(.seq_cst) >= 1);
}

test "a second press of a running repeat starts no second thread" {
    var registry = RepeatRegistryType(4).init();

    try registry.start();
    defer registry.deinit();

    var ctx = TestContext{};

    const id = try registry.register(3, TestContext.callback, &ctx, Options{ .key = .a });

    try std.testing.expect(registry.press(3));
    try std.testing.expect(registry.press(3));
    try std.testing.expectEqual(true, registry.is_running(id).?);

    registry.release(.a);

    try std.testing.expectEqual(false, registry.is_running(id).?);
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
    try std.testing.expectEqual(@as(u32, 0), opts.delay_ms_initial);
    try std.testing.expectEqual(Keycode.silent, opts.key);
}

test "repeat options carry the values they are built with" {
    const opts = Options{
        .interval_ms = 250,
        .delay_ms_initial = 50,
    };

    try std.testing.expectEqual(@as(u32, 250), opts.interval_ms);
    try std.testing.expectEqual(@as(u32, 50), opts.delay_ms_initial);
}

test "a default repeat entry is inactive" {
    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.get_id());
    try std.testing.expect(entry.get_callback() == null);
    try std.testing.expect(entry.get_context() == null);
    try std.testing.expect(!entry.is_active());
    try std.testing.expectEqual(@as(u32, 100), entry.interval_ms);
    try std.testing.expectEqual(@as(u32, 0), entry.delay_ms_initial);
}

test "a default repeat entry is valid" {
    const entry = Entry{};

    try std.testing.expect(entry.is_valid());
}

test "constants: valid ranges" {
    try std.testing.expect(capacity_max >= 1);
    try std.testing.expect(capacity_max <= 64);

    try std.testing.expect(interval_ms_min >= 1);
    try std.testing.expect(interval_ms_max > interval_ms_min);

    try std.testing.expectEqual(@as(u32, 0), delay_ms_initial_default);
    try std.testing.expect(delay_ms_initial_max >= delay_ms_initial_default);

    try std.testing.expect(count_max >= 1);
}

test "each run of a slot executes on the worker that start created" {
    var registry = RepeatRegistryType(4).init();

    try registry.start();
    defer registry.deinit();

    var record = ThreadRecord{};

    _ = try registry.register(5, ThreadRecord.callback, &record, Options{
        .key = .r,
        .interval_ms = interval_ms_min,
    });

    var thread_ids: [2]?std.Thread.Id = @splat(null);

    for (&thread_ids) |*thread_id| {
        record.invoke_count.store(0, .seq_cst);
        record.thread_id = null;

        try std.testing.expect(registry.press(5));

        var attempt: u32 = 0;

        while (attempt < invoke_wait_attempt_max) : (attempt += 1) {
            if (record.invoke_count.load(.seq_cst) >= 1) break;

            std.Thread.yield() catch break;
        }

        registry.release(.r);
        thread_id.* = record.thread_id;
    }

    const first = thread_ids[0] orelse return error.TestRunMissing;
    const second = thread_ids[1] orelse return error.TestRunMissing;

    try std.testing.expectEqual(first, second);
    try std.testing.expect(first != std.Thread.getCurrentId());
}
