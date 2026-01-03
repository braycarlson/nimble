const std = @import("std");

const key_event = @import("../event/key.zig");
const modifier = @import("../modifier.zig");
const response_mod = @import("../response.zig");
const filter_mod = @import("../filter.zig");
const base_mod = @import("base.zig");
const entry_mod = @import("entry.zig");

const Key = key_event.Key;
const Response = response_mod.Response;
const WindowFilter = filter_mod.WindowFilter;

pub const sequence_max: u32 = 8;
pub const capacity_default: u32 = 32;
pub const capacity_max: u32 = 128;
pub const timeout_default_ms: u32 = 1000;
pub const timeout_min_ms: u32 = 100;
pub const timeout_max_ms: u32 = 5000;

pub const Error = base_mod.BaseError || error{
    InvalidSequence,
    InvalidValue,
};

pub const ChordKey = struct {
    value: u8 = 0,
    modifiers: modifier.Set = .{},

    pub fn is_valid(self: *const ChordKey) bool {
        const valid_value = self.value >= 0x01 and self.value <= 0xFE;
        const valid_modifiers = self.modifiers.flags <= modifier.flag_all;

        return valid_value and valid_modifiers;
    }

    pub fn matches(self: *const ChordKey, key: *const Key) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(key.is_valid());

        if (self.value != key.value) {
            return false;
        }

        return self.modifiers.eql(&key.modifiers);
    }

    pub fn matches_value(self: *const ChordKey, key: *const Key) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(key.is_valid());

        return self.value == key.value;
    }
};

pub const Callback = *const fn (context: *anyopaque) Response;

pub const Entry = struct {
    base: entry_mod.FilteredEntry(Callback, WindowFilter) = .{},
    keys: [sequence_max]ChordKey = [_]ChordKey{.{}} ** sequence_max,
    length: u32 = 0,
    timeout_ms: u32 = timeout_default_ms,

    pub fn get_id(self: *const Entry) u32 {
        return self.base.get_id();
    }

    pub fn get_callback(self: *const Entry) ?Callback {
        return self.base.get_callback();
    }

    pub fn get_context(self: *const Entry) ?*anyopaque {
        return self.base.get_context();
    }

    pub fn is_active(self: *const Entry) bool {
        return self.base.is_active();
    }

    pub fn matches_filter(self: *const Entry) bool {
        return self.base.matches_filter();
    }

    pub fn invoke(self: *const Entry) ?Response {
        return self.base.invoke(.{});
    }

    pub fn is_valid(self: *const Entry) bool {
        if (!self.is_active()) {
            return true;
        }

        const valid_base = self.base.is_valid();
        const valid_length = self.length >= 2 and self.length <= sequence_max;
        const valid_timeout = self.timeout_ms >= timeout_min_ms and
            self.timeout_ms <= timeout_max_ms;

        return valid_base and valid_length and valid_timeout;
    }

    pub fn get_key(self: *const Entry, index: u32) ?ChordKey {
        std.debug.assert(self.is_active());

        if (index >= self.length) {
            return null;
        }

        return self.keys[index];
    }

    pub fn matches_at(self: *const Entry, index: u32, key: *const Key) bool {
        std.debug.assert(self.is_active());
        std.debug.assert(key.is_valid());

        if (index >= self.length) {
            return false;
        }

        const chord_key = self.keys[index];

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

pub fn ChordRegistry(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("ChordRegistry capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("ChordRegistry capacity exceeds maximum");
    }

    return struct {
        const Self = @This();

        const Base = base_mod.BaseRegistry(Entry, capacity, .{
            .has_mutex = true,
        });

        base: Base = Base.init(),
        progress: [capacity]u32 = [_]u32{0} ** capacity,
        timestamps: [capacity]i64 = [_]i64{0} ** capacity,
        enabled: bool = true,

        pub fn init() Self {
            return Self{};
        }

        pub fn is_valid(self: *const Self) bool {
            return self.base.is_valid();
        }

        pub fn register(
            self: *Self,
            sequence: []const u8,
            callback: Callback,
            context: ?*anyopaque,
            options: Options,
        ) Error!u32 {
            std.debug.assert(self.is_valid());

            if (sequence.len < 2 or sequence.len > sequence_max) {
                return Error.InvalidSequence;
            }

            if (options.timeout_ms < timeout_min_ms or options.timeout_ms > timeout_max_ms) {
                return Error.InvalidValue;
            }

            self.base.lock();
            defer self.base.unlock();

            const allocation = self.base.allocate_locked() catch return Error.RegistryFull;

            std.debug.assert(allocation.slot < capacity);
            std.debug.assert(allocation.id >= 1);

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
                .keys = [_]ChordKey{.{}} ** sequence_max,
                .length = @intCast(sequence.len),
                .timeout_ms = options.timeout_ms,
            };

            for (sequence, 0..) |char, i| {
                entry.keys[i] = ChordKey{
                    .value = std.ascii.toUpper(char),
                    .modifiers = .{},
                };
            }

            self.base.slot.entries[allocation.slot] = entry;

            std.debug.assert(self.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            self.base.lock();
            defer self.base.unlock();

            _ = self.base.free_by_id_locked(id) catch return error.NotFound;
        }

        pub fn process(self: *Self, key: *const Key, now_ms: i64) ?Response {
            std.debug.assert(self.is_valid());
            std.debug.assert(key.is_valid());

            const invocation = blk: {
                self.base.lock();
                defer self.base.unlock();

                if (!self.enabled) {
                    break :blk null;
                }

                break :blk self.resolve_locked(key, now_ms);
            };

            if (invocation) |inv| {
                return inv.callback(inv.context);
            }

            return null;
        }

        fn resolve_locked(self: *Self, key: *const Key, now_ms: i64) ?Invocation {
            std.debug.assert(key.is_valid());

            const entries = self.base.entries();

            for (entries, 0..) |*e, slot| {
                if (!e.is_active()) {
                    continue;
                }

                if (!e.matches_filter()) {
                    self.progress[slot] = 0;
                    self.timestamps[slot] = 0;
                    continue;
                }

                self.check_timeout(slot, e, now_ms);

                const current_progress = self.progress[slot];

                if (e.matches_at(current_progress, key)) {
                    self.progress[slot] = current_progress + 1;
                    self.timestamps[slot] = now_ms;

                    if (self.progress[slot] >= e.length) {
                        self.progress[slot] = 0;
                        self.timestamps[slot] = 0;

                        const callback = e.get_callback() orelse continue;
                        const context = e.get_context() orelse continue;

                        return Invocation{
                            .callback = callback,
                            .context = context,
                        };
                    }
                }
            }

            return null;
        }

        fn check_timeout(self: *Self, slot: usize, entry: *const Entry, now_ms: i64) void {
            std.debug.assert(entry.is_active());
            std.debug.assert(slot < capacity);

            const last_time = self.timestamps[slot];

            if (last_time == 0) {
                return;
            }

            if (now_ms > last_time) {
                const elapsed: u64 = @intCast(now_ms - last_time);

                if (elapsed > entry.timeout_ms) {
                    self.progress[slot] = 0;
                    self.timestamps[slot] = 0;
                }
            }
        }

        pub fn set_enabled(self: *Self, value: bool) void {
            self.base.lock();
            defer self.base.unlock();

            self.enabled = value;
        }

        pub fn reset_progress(self: *Self) void {
            self.base.lock();
            defer self.base.unlock();

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                self.progress[i] = 0;
                self.timestamps[i] = 0;
            }
        }

        pub fn clear(self: *Self) void {
            self.base.lock();
            defer self.base.unlock();

            self.base.clear_locked();

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                self.progress[i] = 0;
                self.timestamps[i] = 0;
            }
        }
    };
}
