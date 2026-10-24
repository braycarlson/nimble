const Keycode = @import("../keycode.zig").Keycode;
const std = @import("std");

const key_event = @import("../event/key.zig");
const modifier = @import("../modifier.zig");
const response = @import("../response.zig");
const filter_mod = @import("../filter.zig");
const base = @import("base.zig");
const entry_mod = @import("entry.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Response = response.Response;
const WindowFilter = filter_mod.Active;

pub const sequence_max: u32 = 8;
pub const capacity_max: u32 = 128;
pub const timeout_default_ms: u32 = 1000;
pub const timeout_ms_min: u32 = 100;
pub const timeout_ms_max: u32 = 5000;
pub const CapacityError = error{ChordsExhausted};

pub const RequestError = error{
    ChordInvalid,
    HandleUnknown,
    TimeoutInvalid,
};

pub const ChordKey = struct {
    value: Keycode = .silent,
    modifiers: modifier.Set = .{},

    pub fn is_valid(key: *const ChordKey) bool {
        return key.modifiers.flags <= modifier.flag_all;
    }

    pub fn matches(chord_key: *const ChordKey, key: *const Key) bool {
        assert(chord_key.is_valid());
        assert(key.is_valid());

        if (chord_key.value != key.value) {
            return false;
        }

        return chord_key.modifiers.eql(&key.modifiers);
    }

    pub fn matches_value(chord_key: *const ChordKey, key: *const Key) bool {
        assert(chord_key.is_valid());
        assert(key.is_valid());

        return chord_key.value == key.value;
    }
};

pub const Callback = *const fn (context: *anyopaque) Response;

pub const Entry = struct {
    base: entry_mod.FilteredEntryType(Callback, WindowFilter) = .{},
    keys: [sequence_max]ChordKey = @splat(.{}),
    length: u32 = 0,
    timeout_ms: u32 = timeout_default_ms,

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

    pub fn matches_filter(entry: *const Entry) bool {
        return entry.base.matches_filter();
    }

    pub fn is_valid(entry: *const Entry) bool {
        if (!entry.is_active()) {
            return true;
        }

        const valid_base = entry.base.is_valid();
        const valid_length = entry.length >= 2 and entry.length <= sequence_max;

        const valid_timeout = entry.timeout_ms >= timeout_ms_min and
            entry.timeout_ms <= timeout_ms_max;

        return valid_base and valid_length and valid_timeout;
    }

    pub fn get_key(entry: *const Entry, index: u32) ?ChordKey {
        assert(entry.is_active());

        if (index >= entry.length) {
            return null;
        }

        return entry.keys[index];
    }

    pub fn matches_at(entry: *const Entry, index: u32, key: *const Key) bool {
        assert(entry.is_active());
        assert(key.is_valid());

        if (index >= entry.length) {
            return false;
        }

        const chord_key = entry.keys[index];
        return chord_key.matches_value(key);
    }
};

pub const Options = struct {
    timeout_ms: u32 = timeout_default_ms,
    filter: WindowFilter = .{},
};

const Invocation = struct {
    callback: Callback,
    context: *anyopaque,
};

pub fn ChordRegistryType(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("ChordRegistryType capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("ChordRegistryType capacity exceeds maximum");
    }

    return struct {
        const Instance = @This();

        const Base = base.BaseRegistryType(Entry, capacity, .{
            .has_mutex = true,
        });

        base: Base = Base.init(),
        progress: [capacity]u32 = @splat(0),
        timestamps: [capacity]i64 = @splat(0),
        enabled: bool = true,

        pub fn init() Instance {
            return Instance{};
        }

        pub fn is_valid(instance: *const Instance) bool {
            return instance.base.is_valid();
        }

        pub fn register(
            instance: *Instance,
            sequence: []const Keycode,
            callback: Callback,
            context: ?*anyopaque,
            options: Options,
        ) (CapacityError || RequestError)!u32 {
            if (sequence.len < 2) return error.ChordInvalid;
            if (sequence.len > sequence_max) return error.ChordInvalid;
            if (options.timeout_ms < timeout_ms_min) return error.TimeoutInvalid;
            if (options.timeout_ms > timeout_ms_max) return error.TimeoutInvalid;

            for (sequence) |value| {
                if (value == .silent) {
                    return error.ChordInvalid;
                }
            }

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const allocation = instance.base.allocate_locked() orelse {
                return error.ChordsExhausted;
            };

            assert(allocation.slot < capacity);
            assert(allocation.id >= 1);

            var entry = Entry{
                .base = .{
                    .base = .{
                        .id = allocation.id,
                        .callback = callback,
                        .context = context,
                        .active = true,
                    },
                    .filter = options.filter,
                },
                .keys = @splat(.{}),
                .length = @intCast(sequence.len),
                .timeout_ms = options.timeout_ms,
            };

            for (sequence, 0..) |value, index| {
                assert(index < sequence_max);

                entry.keys[index] = ChordKey{
                    .value = value,
                    .modifiers = .{},
                };
            }

            instance.base.slot.entries[allocation.slot] = entry;

            assert(instance.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(instance: *Instance, id: u32) RequestError!void {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const slot = instance.base.free_by_id_locked(id) orelse return error.HandleUnknown;

            assert(slot < capacity);

            instance.progress[slot] = 0;
            instance.timestamps[slot] = 0;
        }

        pub fn process(instance: *Instance, key: *const Key, now_ms: i64) ?Response {
            assert(key.is_valid());

            const invocation = blk: {
                instance.base.lock();
                defer instance.base.unlock();

                assert(instance.is_valid());

                if (!instance.enabled) {
                    break :blk null;
                }

                break :blk instance.resolve_locked(key, now_ms);
            };

            if (invocation) |inv| {
                return inv.callback(inv.context);
            }

            return null;
        }

        fn resolve_locked(instance: *Instance, key: *const Key, now_ms: i64) ?Invocation {
            assert(key.is_valid());

            const entries = instance.base.entries();

            for (entries, 0..) |*e, slot| {
                if (!e.is_active()) {
                    continue;
                }

                assert(slot < capacity);

                if (!e.matches_filter()) {
                    instance.progress[slot] = 0;
                    instance.timestamps[slot] = 0;

                    continue;
                }

                instance.check_timeout(slot, e, now_ms);

                const progress_current = instance.progress[slot];

                if (e.matches_at(progress_current, key)) {
                    instance.progress[slot] = progress_current + 1;
                    instance.timestamps[slot] = now_ms;

                    if (instance.progress[slot] >= e.length) {
                        instance.progress[slot] = 0;
                        instance.timestamps[slot] = 0;

                        const callback = e.get_callback() orelse continue;
                        const context = e.get_context() orelse continue;

                        return Invocation{
                            .callback = callback,
                            .context = context,
                        };
                    }
                } else {
                    instance.progress[slot] = 0;
                    instance.timestamps[slot] = 0;
                }
            }

            return null;
        }

        fn check_timeout(instance: *Instance, slot: usize, entry: *const Entry, now_ms: i64) void {
            assert(entry.is_active());
            assert(slot < capacity);

            const time_last = instance.timestamps[slot];

            if (time_last == 0) {
                return;
            }

            if (now_ms > time_last) {
                const elapsed: u64 = @intCast(now_ms - time_last);

                if (elapsed > entry.timeout_ms) {
                    instance.progress[slot] = 0;
                    instance.timestamps[slot] = 0;
                }
            }
        }

        pub fn set_enabled(instance: *Instance, value: bool) void {
            instance.base.lock();
            defer instance.base.unlock();

            instance.enabled = value;
        }

        pub fn reset_progress(instance: *Instance) void {
            instance.base.lock();
            defer instance.base.unlock();

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                instance.progress[i] = 0;
                instance.timestamps[i] = 0;
            }
        }

        pub fn clear(instance: *Instance) void {
            instance.base.lock();
            defer instance.base.unlock();

            instance.base.clear_locked();

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                instance.progress[i] = 0;
                instance.timestamps[i] = 0;
            }
        }
    };
}

const testing = std.testing;

fn make_test_key(value: Keycode) Key {
    return Key{
        .value = value,
        .down = true,
        .injected = false,
        .modifiers = modifier.Set{},
    };
}

const CountContext = struct {
    count: u32 = 0,

    fn callback(context: *anyopaque) Response {
        const self: *CountContext = @ptrCast(@alignCast(context));
        self.count += 1;

        return .consume;
    }
};

test "a default chord key is empty" {
    const ck = ChordKey{};

    try testing.expectEqual(Keycode.silent, ck.value);
    try testing.expect(ck.modifiers.none());
}

test "every representable keycode makes a valid chord key" {
    const letter = ChordKey{ .value = .a, .modifiers = modifier.Set{} };
    const sentinel = ChordKey{ .value = .silent, .modifiers = modifier.Set{} };
    const function = ChordKey{ .value = .f24, .modifiers = modifier.Set{} };

    try testing.expect(letter.is_valid());
    try testing.expect(sentinel.is_valid());
    try testing.expect(function.is_valid());
}

test "a chord key with modifiers is valid" {
    const ck = ChordKey{
        .value = .b,
        .modifiers = modifier.Set.from(.{ .ctrl = true, .alt = true }),
    };

    try testing.expect(ck.is_valid());
}

test "a chord key matches the same value with no modifiers" {
    const ck = ChordKey{ .value = .a, .modifiers = modifier.Set{} };

    const key = Key{
        .value = .a,
        .down = true,
        .injected = false,
        .modifiers = modifier.Set{},
    };

    try testing.expect(ck.matches(&key));
}

test "a chord key matches the same value and modifiers" {
    const ck = ChordKey{
        .value = .a,
        .modifiers = modifier.Set.from(.{ .ctrl = true }),
    };

    const key = Key{
        .value = .a,
        .down = true,
        .injected = false,
        .modifiers = modifier.Set.from(.{ .ctrl = true }),
    };

    try testing.expect(ck.matches(&key));
}

test "a chord key does not match a different value" {
    const ck = ChordKey{ .value = .a, .modifiers = modifier.Set{} };

    const key = Key{
        .value = .b,
        .down = true,
        .injected = false,
        .modifiers = modifier.Set{},
    };

    try testing.expect(!ck.matches(&key));
}

test "a chord key does not match different modifiers" {
    const ck = ChordKey{
        .value = .a,
        .modifiers = modifier.Set.from(.{ .ctrl = true }),
    };

    const key = Key{
        .value = .a,
        .down = true,
        .injected = false,
        .modifiers = modifier.Set.from(.{ .alt = true }),
    };

    try testing.expect(!ck.matches(&key));
}

test "a chord key matches an equal value" {
    const ck = ChordKey{ .value = .x, .modifiers = modifier.Set{} };

    const key = Key{
        .value = .x,
        .down = true,
        .injected = false,
        .modifiers = modifier.Set.from(.{ .ctrl = true }),
    };

    try testing.expect(ck.matches_value(&key));
}

test "a chord key does not match an unequal value" {
    const ck = ChordKey{ .value = .x, .modifiers = modifier.Set{} };

    const key = Key{
        .value = .y,
        .down = true,
        .injected = false,
        .modifiers = modifier.Set{},
    };

    try testing.expect(!ck.matches_value(&key));
}

test "matching on value alone ignores the modifiers" {
    const ck = ChordKey{
        .value = .z,
        .modifiers = modifier.Set.from(.{ .shift = true }),
    };

    const key = Key{
        .value = .z,
        .down = true,
        .injected = false,
        .modifiers = modifier.Set{},
    };

    try testing.expect(ck.matches_value(&key));
}

test "chord constants" {
    try testing.expect(sequence_max >= 2);
    try testing.expect(sequence_max <= 16);
    try testing.expect(timeout_ms_min <= timeout_default_ms);
    try testing.expect(timeout_default_ms <= timeout_ms_max);
}

test "a chord registered into a freed slot starts with no progress" {
    var reg = ChordRegistryType(1).init();
    var context = CountContext{};

    const key_a = make_test_key(.a);
    const key_b = make_test_key(.b);
    const first = try reg.register(&.{ .a, .b }, CountContext.callback, &context, .{});

    try testing.expect(reg.process(&key_a, 1000) == null);

    try reg.unregister(first);

    _ = try reg.register(&.{ .c, .b }, CountContext.callback, &context, .{});

    try testing.expect(reg.process(&key_b, 1010) == null);
    try testing.expectEqual(@as(u32, 0), context.count);
    try testing.expectError(error.HandleUnknown, reg.unregister(first));
}

test "a chord completes on its ordered sequence" {
    var reg = ChordRegistryType(4).init();
    var context = CountContext{};

    _ = try reg.register(&.{ .a, .b }, CountContext.callback, &context, .{});

    const key_a = make_test_key(.a);
    const key_b = make_test_key(.b);

    try testing.expect(reg.process(&key_a, 1000) == null);

    const result = reg.process(&key_b, 1010);

    try testing.expect(result != null);
    try testing.expectEqual(Response.consume, result.?);
    try testing.expectEqual(@as(u32, 1), context.count);
}

test "a foreign key resets chord progress" {
    var reg = ChordRegistryType(4).init();
    var context = CountContext{};

    _ = try reg.register(&.{ .a, .b }, CountContext.callback, &context, .{});

    const key_a = make_test_key(.a);
    const key_x = make_test_key(.x);
    const key_b = make_test_key(.b);

    try testing.expect(reg.process(&key_a, 1000) == null);
    try testing.expect(reg.process(&key_x, 1010) == null);
    try testing.expect(reg.process(&key_b, 1020) == null);
    try testing.expectEqual(@as(u32, 0), context.count);
}

test "a chord sequence restarts after a reset" {
    var reg = ChordRegistryType(4).init();
    var context = CountContext{};

    _ = try reg.register(&.{ .a, .b }, CountContext.callback, &context, .{});

    const key_a = make_test_key(.a);
    const key_x = make_test_key(.x);
    const key_b = make_test_key(.b);

    try testing.expect(reg.process(&key_a, 1000) == null);
    try testing.expect(reg.process(&key_x, 1010) == null);
    try testing.expect(reg.process(&key_a, 1020) == null);

    const result = reg.process(&key_b, 1030);

    try testing.expect(result != null);
    try testing.expectEqual(@as(u32, 1), context.count);
}

test "a chord completes on keys no character can spell" {
    var reg = ChordRegistryType(4).init();
    var context = CountContext{};

    const sequence = [_]Keycode{ .page_up, .page_down };

    _ = try reg.register(&sequence, CountContext.callback, &context, .{});

    const key_up = make_test_key(.page_up);
    const key_down = make_test_key(.page_down);

    try testing.expect(reg.process(&key_up, 1000) == null);

    const result = reg.process(&key_down, 1010);

    try testing.expect(result != null);
    try testing.expectEqual(Response.consume, result.?);
    try testing.expectEqual(@as(u32, 1), context.count);
}

test "a key sequence resets on a foreign key like any other" {
    var reg = ChordRegistryType(4).init();
    var context = CountContext{};

    const sequence = [_]Keycode{ .page_up, .page_down };

    _ = try reg.register(&sequence, CountContext.callback, &context, .{});

    const key_up = make_test_key(.page_up);
    const key_x = make_test_key(.x);
    const key_down = make_test_key(.page_down);

    try testing.expect(reg.process(&key_up, 1000) == null);
    try testing.expect(reg.process(&key_x, 1010) == null);
    try testing.expect(reg.process(&key_down, 1020) == null);
    try testing.expectEqual(@as(u32, 0), context.count);
}

test "registering rejects the silent keycode" {
    var reg = ChordRegistryType(4).init();
    var context = CountContext{};

    const sequence = [_]Keycode{ .page_up, .silent };

    try testing.expectError(
        error.ChordInvalid,
        reg.register(&sequence, CountContext.callback, &context, .{}),
    );

    try testing.expectEqual(@as(u32, 0), reg.base.count());
}

test "registering rejects a sequence shorter than two keys" {
    var reg = ChordRegistryType(4).init();
    var context = CountContext{};

    const sequence = [_]Keycode{.page_up};

    try testing.expectError(
        error.ChordInvalid,
        reg.register(&sequence, CountContext.callback, &context, .{}),
    );

    try testing.expectEqual(@as(u32, 0), reg.base.count());
}
