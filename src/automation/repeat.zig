const std = @import("std");

const key_event = @import("../event/key.zig");
const response_mod = @import("../response.zig");
const base_mod = @import("../registry/base.zig");
const entry_mod = @import("../registry/entry.zig");

const Key = key_event.Key;
const Response = response_mod.Response;

pub const capacity_default: u32 = 16;
pub const capacity_max: u32 = 64;
pub const interval_min_ms: u32 = 10;
pub const interval_max_ms: u32 = 60000;
pub const initial_delay_default_ms: u32 = 0;
pub const initial_delay_max_ms: u32 = 60000;
pub const count_max: u32 = 1000000;

pub const Error = base_mod.BaseError || error{
    AlreadyActive,
    InvalidValue,
};

pub const Callback = *const fn (context: *anyopaque, count: u32) void;

pub const Entry = struct {
    base: entry_mod.BindingEntry(Callback) = .{},
    initial_delay_ms: u32 = 0,
    interval_ms: u32 = 100,
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    count: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    stop_flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    thread: ?std.Thread = null,

    pub fn get_id(self: *const Entry) u32 {
        return self.base.get_id();
    }

    pub fn get_callback(self: *const Entry) ?Callback {
        return self.base.get_callback();
    }

    pub fn get_context(self: *const Entry) ?*anyopaque {
        return self.base.get_context();
    }

    pub fn get_binding_id(self: *const Entry) u32 {
        return self.base.get_binding_id();
    }

    pub fn is_active(self: *const Entry) bool {
        return self.base.is_active();
    }

    pub fn invoke(self: *Entry, count_value: u32) void {
        _ = self.base.invoke(.{count_value});
    }

    pub fn is_valid(self: *const Entry) bool {
        if (!self.is_active()) {
            return true;
        }

        const valid_base = self.base.is_valid();
        const valid_interval = self.interval_ms >= interval_min_ms and
            self.interval_ms <= interval_max_ms;
        const valid_initial_delay = self.initial_delay_ms <= initial_delay_max_ms;
        const valid_count = self.count.load(.acquire) <= count_max;

        return valid_base and valid_interval and valid_initial_delay and valid_count;
    }
};

pub const Options = struct {
    interval_ms: u32 = 100,
    initial_delay_ms: u32 = 0,
};

pub fn RepeatRegistry(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("RepeatRegistry capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("RepeatRegistry capacity exceeds maximum");
    }

    return struct {
        const Self = @This();

        const Base = base_mod.BaseRegistry(Entry, capacity, .{
            .has_mutex = true,
        });

        base: Base = Base.init(),

        pub fn init() Self {
            return Self{};
        }

        pub fn is_valid(self: *const Self) bool {
            return self.base.is_valid();
        }

        pub fn register(
            self: *Self,
            binding_id: u32,
            callback: Callback,
            context: ?*anyopaque,
            options: Options,
        ) Error!u32 {
            std.debug.assert(binding_id >= 1);

            if (options.interval_ms < interval_min_ms or options.interval_ms > interval_max_ms) {
                return Error.InvalidValue;
            }

            if (options.initial_delay_ms > initial_delay_max_ms) {
                return Error.InvalidValue;
            }

            self.base.lock();
            defer self.base.unlock();

            std.debug.assert(self.is_valid());

            const allocation = self.base.allocate_locked() catch return error.RegistryFull;

            std.debug.assert(allocation.slot < capacity);
            std.debug.assert(allocation.id >= 1);

            self.base.slot.entries[allocation.slot] = Entry{
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

            std.debug.assert(self.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(self: *Self, id: u32) Error!void {
            std.debug.assert(id >= 1);

            var thread_to_join: ?std.Thread = null;

            {
                self.base.lock();
                defer self.base.unlock();

                std.debug.assert(self.is_valid());

                if (self.base.get_by_id(id)) |entry| {
                    thread_to_join = self.stop_entry(entry);
                }

                _ = self.base.free_by_id_locked(id) catch return error.NotFound;
            }

            if (thread_to_join) |t| {
                t.join();
            }
        }

        pub fn process(self: *Self, binding_id: u32, down: bool) void {
            std.debug.assert(binding_id >= 1);

            var thread_to_join: ?std.Thread = null;

            {
                self.base.lock();
                defer self.base.unlock();

                std.debug.assert(self.is_valid());

                const entries = self.base.entries();

                for (entries, 0..) |*e, slot| {
                    if (!e.is_active()) {
                        continue;
                    }

                    if (e.get_binding_id() != binding_id) {
                        continue;
                    }

                    if (down) {
                        self.start_entry(e, @intCast(slot));
                    } else {
                        thread_to_join = self.stop_entry(e);
                    }
                }
            }

            if (thread_to_join) |t| {
                t.join();
            }
        }

        pub fn stop_all(self: *Self) void {
            var threads_to_join: [capacity]?std.Thread = [_]?std.Thread{null} ** capacity;
            var thread_count: u32 = 0;

            {
                self.base.lock();
                defer self.base.unlock();

                std.debug.assert(self.is_valid());

                const entries = self.base.entries();

                for (entries) |*e| {
                    if (!e.is_active()) {
                        continue;
                    }

                    if (self.stop_entry(e)) |t| {
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

        fn start_entry(self: *Self, entry: *Entry, slot: u32) void {
            _ = self;

            std.debug.assert(entry.is_active());

            if (entry.running.load(.acquire)) {
                return;
            }

            entry.running.store(true, .release);
            entry.count.store(0, .release);
            entry.stop_flag.store(false, .release);

            entry.thread = std.Thread.spawn(.{}, repeat_thread, .{ entry, slot }) catch null;
        }

        fn stop_entry(self: *Self, entry: *Entry) ?std.Thread {
            _ = self;

            std.debug.assert(entry.is_active());

            if (!entry.running.load(.acquire)) {
                return null;
            }

            entry.stop_flag.store(true, .release);

            const thread = entry.thread;
            entry.thread = null;
            entry.running.store(false, .release);

            return thread;
        }

        fn repeat_thread(entry: *Entry, slot: u32) void {
            _ = slot;

            std.debug.assert(entry.is_active());

            if (entry.initial_delay_ms > 0) {
                std.Thread.sleep(entry.initial_delay_ms * std.time.ns_per_ms);
            }

            while (!entry.stop_flag.load(.acquire)) {
                const current_count = entry.count.fetchAdd(1, .acq_rel);

                entry.invoke(current_count);

                if (entry.stop_flag.load(.acquire)) {
                    break;
                }

                std.Thread.sleep(entry.interval_ms * std.time.ns_per_ms);
            }
        }

        pub fn clear(self: *Self) void {
            var threads_to_join: [capacity]?std.Thread = [_]?std.Thread{null} ** capacity;
            var thread_count: u32 = 0;

            {
                self.base.lock();
                defer self.base.unlock();

                std.debug.assert(self.is_valid());

                const entries = self.base.entries();

                for (entries) |*e| {
                    if (e.is_active()) {
                        if (self.stop_entry(e)) |t| {
                            threads_to_join[thread_count] = t;
                            thread_count += 1;
                        }
                    }
                }

                self.base.clear_locked();
            }

            for (threads_to_join[0..thread_count]) |maybe_thread| {
                if (maybe_thread) |t| {
                    t.join();
                }
            }
        }
    };
}
