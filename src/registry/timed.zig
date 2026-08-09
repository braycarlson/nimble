const std = @import("std");

const platform = @import("../platform.zig");

const key_event = @import("../event/key.zig");
const response_mod = @import("../response.zig");
const base = @import("../registry/base.zig");
const entry_mod = @import("../registry/entry.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Response = response_mod.Response;

pub const capacity_default: u32 = 32;
pub const capacity_max: u32 = 128;
pub const duration_max_ms: u64 = 86400000;
pub const count_max: u32 = 1000000;

pub const Error = base.BaseError || error{
    AlreadyActive,
    InvalidValue,
    NotActive,
};

pub const Callback = *const fn (context: *anyopaque, key: *const Key) Response;

pub const Mode = enum(u8) {
    duration = 0,
    until_time = 1,
    toggle = 2,
    count_limited = 3,

    pub fn is_valid(mode: Mode) bool {
        const value = @intFromEnum(mode);

        return value <= 3;
    }
};

pub const Entry = struct {
    base: entry_mod.BindingEntryType(Callback) = .{},
    duration_ms: u64 = 0,
    end_time: i64 = 0,
    count_limit: u32 = 0,
    mode: Mode = .duration,
    expired: bool = false,
    count_current: u32 = 0,
    start_time: i64 = 0,

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

    pub fn is_enabled(entry: *const Entry) bool {
        return entry.base.is_enabled();
    }

    pub fn set_enabled(entry: *Entry, value: bool) void {
        entry.base.set_enabled(value);
    }

    pub fn get_binding_id(entry: *const Entry) u32 {
        return entry.base.get_binding_id();
    }

    pub fn invoke(entry: *const Entry, key: *const Key) ?Response {
        assert(entry.is_active());
        assert(key.is_valid());

        return entry.base.invoke(.{key});
    }

    pub fn is_valid(entry: *const Entry) bool {
        if (!entry.is_active()) {
            return true;
        }

        const valid_base = entry.base.is_valid();
        const valid_mode = entry.mode.is_valid();
        const valid_count = entry.count_current <= count_max;

        return valid_base and valid_mode and valid_count;
    }

    pub fn is_within_time(entry: *const Entry) bool {
        assert(entry.is_active());

        if (!entry.is_enabled()) {
            return false;
        }

        switch (entry.mode) {
            .duration => {
                if (entry.start_time == 0) {
                    return false;
                }

                const now: i64 = platform.backend.time.now_ms();

                if (now <= entry.start_time) {
                    return true;
                }

                const elapsed: u64 = @intCast(now - entry.start_time);

                return elapsed < entry.duration_ms;
            },
            .until_time => {
                const now: i64 = platform.backend.time.now_ms();

                return now < entry.end_time;
            },
            .toggle => {
                return true;
            },
            .count_limited => {
                return entry.count_current < entry.count_limit;
            },
        }
    }
};

pub const Options = struct {
    mode: Mode = .toggle,
    duration_ms: u64 = 0,
    end_time: i64 = 0,
    count_limit: u32 = 0,

    pub fn duration(ms: u64) Options {
        return .{
            .mode = .duration,
            .duration_ms = ms,
        };
    }

    pub fn until(end_time_ms: i64) Options {
        return .{
            .mode = .until_time,
            .end_time = end_time_ms,
        };
    }

    pub fn toggle_mode() Options {
        return .{
            .mode = .toggle,
        };
    }

    pub fn count(max: u32) Options {
        return .{
            .mode = .count_limited,
            .count_limit = max,
        };
    }
};

const Invocation = struct {
    callback: ?Callback,
    context: ?*anyopaque,
};

pub fn TimedRegistryType(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("TimedRegistryType capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("TimedRegistryType capacity exceeds maximum");
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

            const duration_invalid = options.duration_ms == 0 or
                options.duration_ms > duration_max_ms;

            if (options.mode == .duration and duration_invalid) {
                return Error.InvalidValue;
            }

            const count_invalid = options.count_limit == 0 or options.count_limit > count_max;

            if (options.mode == .count_limited and count_invalid) {
                return Error.InvalidValue;
            }

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const allocation = instance.base.allocate_locked() catch return Error.RegistryFull;

            assert(allocation.slot < capacity);
            assert(allocation.id >= 1);

            const initial_enabled = options.mode != .duration and options.mode != .toggle;

            instance.base.slot.entries[allocation.slot] = Entry{
                .base = .{
                    .base = .{
                        .id = allocation.id,
                        .callback = callback,
                        .context = context,
                        .active = true,
                    },
                    .binding_id = binding_id,
                    .enabled = initial_enabled,
                },
                .mode = options.mode,
                .duration_ms = options.duration_ms,
                .end_time = options.end_time,
                .count_limit = options.count_limit,
                .expired = false,
                .start_time = if (options.mode == .until_time)
                    platform.backend.time.now_ms()
                else
                    0,
                .count_current = 0,
            };

            assert(instance.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(instance: *Instance, id: u32) Error!void {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            _ = instance.base.free_by_id_locked(id) catch return error.NotFound;
        }

        pub fn process(instance: *Instance, binding_id: u32, key: *const Key) ?Response {
            assert(binding_id >= 1);
            assert(key.is_valid());

            const match = blk: {
                instance.base.lock();
                defer instance.base.unlock();

                assert(instance.is_valid());

                break :blk instance.resolve_locked(binding_id);
            };

            if (match) |m| {
                if (m.callback) |callback| {
                    if (m.context) |context| {
                        const response = callback(context, key);

                        assert(response.is_valid());

                        return response;
                    }
                }

                return .consume;
            }

            return null;
        }

        fn resolve_locked(instance: *Instance, binding_id: u32) ?Invocation {
            assert(binding_id >= 1);

            const entries = instance.base.entries();

            for (entries) |*e| {
                if (!e.is_active()) {
                    continue;
                }

                if (e.get_binding_id() != binding_id) {
                    continue;
                }

                if (!e.is_within_time()) {
                    continue;
                }

                if (e.mode == .count_limited) {
                    e.count_current += 1;

                    if (e.count_current >= e.count_limit) {
                        e.expired = true;
                    }
                }

                assert(e.count_current <= count_max);

                return Invocation{
                    .callback = e.get_callback(),
                    .context = e.get_context(),
                };
            }

            return null;
        }

        pub fn start(instance: *Instance, id: u32) Error!void {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const entry = instance.base.get_by_id(id) orelse return error.NotFound;

            assert(entry.is_active());

            if (entry.mode == .duration) {
                entry.start_time = platform.backend.time.now_ms();
            }

            entry.set_enabled(true);
            entry.expired = false;
            entry.count_current = 0;
        }

        pub fn stop(instance: *Instance, id: u32) Error!void {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const entry = instance.base.get_by_id(id) orelse return error.NotFound;

            assert(entry.is_active());

            entry.set_enabled(false);
        }

        pub fn toggle(instance: *Instance, id: u32) Error!void {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const entry = instance.base.get_by_id(id) orelse return error.NotFound;

            assert(entry.is_active());

            if (entry.is_enabled()) {
                entry.set_enabled(false);
            } else {
                if (entry.mode == .duration) {
                    entry.start_time = platform.backend.time.now_ms();
                }

                entry.set_enabled(true);
                entry.expired = false;
                entry.count_current = 0;
            }
        }

        pub fn is_enabled(instance: *Instance, id: u32) ?bool {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const slot = instance.base.find_by_id(id) orelse return null;

            return instance.base.slot.entries[slot].is_enabled();
        }

        pub fn is_expired(instance: *Instance, id: u32) ?bool {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const slot = instance.base.find_by_id(id) orelse return null;

            return instance.base.slot.entries[slot].expired;
        }

        pub fn get_remaining_count(instance: *Instance, id: u32) ?u32 {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const slot = instance.base.find_by_id(id) orelse return null;

            const entry = &instance.base.slot.entries[slot];

            if (entry.mode != .count_limited) {
                return null;
            }

            if (entry.count_current >= entry.count_limit) {
                return 0;
            }

            return entry.count_limit - entry.count_current;
        }

        pub fn clear(instance: *Instance) void {
            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            instance.base.clear_locked();
        }
    };
}

const testing = std.testing;

fn timed_callback(_: *anyopaque, _: *const Key) Response {
    return .consume;
}

test "a duration mode is valid" {
    try testing.expect(Mode.duration.is_valid());
}

test "an until time mode is valid" {
    try testing.expect(Mode.until_time.is_valid());
}

test "a toggle mode is valid" {
    try testing.expect(Mode.toggle.is_valid());
}

test "a count limited mode is valid" {
    try testing.expect(Mode.count_limited.is_valid());
}

test "the timed modes are stable" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(Mode.duration));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(Mode.until_time));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(Mode.toggle));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(Mode.count_limited));
}

test "timed options start at their defaults" {
    const opts = Options{};

    try testing.expectEqual(Mode.toggle, opts.mode);
    try testing.expectEqual(@as(u64, 0), opts.duration_ms);
    try testing.expectEqual(@as(i64, 0), opts.end_time);
    try testing.expectEqual(@as(u32, 0), opts.count_limit);
}

test "timed options carry their duration" {
    const opts = Options.duration(5000);

    try testing.expectEqual(Mode.duration, opts.mode);
    try testing.expectEqual(@as(u64, 5000), opts.duration_ms);
}

test "timed options carry their end time" {
    const end_time: i64 = 1234567890;
    const opts = Options.until(end_time);

    try testing.expectEqual(Mode.until_time, opts.mode);
    try testing.expectEqual(end_time, opts.end_time);
}

test "timed options carry their toggle mode" {
    const opts = Options.toggle_mode();

    try testing.expectEqual(Mode.toggle, opts.mode);
}

test "timed options carry their count" {
    const opts = Options.count(100);

    try testing.expectEqual(Mode.count_limited, opts.mode);
    try testing.expectEqual(@as(u32, 100), opts.count_limit);
}

test "timed constants" {
    try testing.expect(capacity_default <= capacity_max);
    try testing.expect(duration_max_ms > 0);
    try testing.expect(count_max > 0);
}

test "registering accepts a count_limit at the maximum" {
    var registry = TimedRegistryType(4).init();
    var context: u32 = 0;

    const id = try registry.register(
        1,
        timed_callback,
        &context,
        Options.count(count_max),
    );

    try testing.expect(id >= 1);
    try testing.expect(registry.is_valid());
}

test "registering rejects a count_limit above the maximum" {
    var registry = TimedRegistryType(4).init();
    var context: u32 = 0;

    const result = registry.register(
        1,
        timed_callback,
        &context,
        Options.count(count_max + 1),
    );

    try testing.expectError(error.InvalidValue, result);
    try testing.expect(registry.is_valid());
}

test "registering rejects a zero count_limit" {
    var registry = TimedRegistryType(4).init();
    var context: u32 = 0;

    const result = registry.register(
        1,
        timed_callback,
        &context,
        Options.count(0),
    );

    try testing.expectError(error.InvalidValue, result);
}
