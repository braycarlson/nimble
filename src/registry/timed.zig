const std = @import("std");

const w32 = @import("win32").everything;

const key_event = @import("../event/key.zig");
const response_mod = @import("../response.zig");
const base_mod = @import("../registry/base.zig");
const entry_mod = @import("../registry/entry.zig");

const Key = key_event.Key;
const Response = response_mod.Response;

pub const capacity_default: u32 = 32;
pub const capacity_max: u32 = 128;
pub const duration_max_ms: u64 = 86400000;
pub const count_max: u32 = 1000000;

pub const Error = base_mod.BaseError || error{
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

    pub fn is_valid(self: Mode) bool {
        const value = @intFromEnum(self);
        return value <= 3;
    }
};

pub const Entry = struct {
    base: entry_mod.BindingEntry(Callback) = .{},
    duration_ms: u64 = 0,
    end_time: i64 = 0,
    count_limit: u32 = 0,
    mode: Mode = .duration,
    expired: bool = false,
    count_current: u32 = 0,
    start_time: i64 = 0,

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

    pub fn is_enabled(self: *const Entry) bool {
        return self.base.is_enabled();
    }

    pub fn set_enabled(self: *Entry, value: bool) void {
        self.base.set_enabled(value);
    }

    pub fn get_binding_id(self: *const Entry) u32 {
        return self.base.get_binding_id();
    }

    pub fn invoke(self: *const Entry, key: *const Key) ?Response {
        std.debug.assert(self.is_active());
        std.debug.assert(key.is_valid());

        return self.base.invoke(.{key});
    }

    pub fn is_valid(self: *const Entry) bool {
        if (!self.is_active()) {
            return true;
        }

        const valid_base = self.base.is_valid();
        const valid_mode = self.mode.is_valid();
        const valid_count = self.count_current <= count_max;

        return valid_base and valid_mode and valid_count;
    }

    pub fn is_within_time(self: *const Entry) bool {
        std.debug.assert(self.is_active());

        if (!self.is_enabled()) {
            return false;
        }

        switch (self.mode) {
            .duration => {
                if (self.start_time == 0) {
                    return false;
                }

                const now: i64 = @intCast(w32.GetTickCount64());
                const elapsed: u64 = @intCast(now - self.start_time);

                return elapsed < self.duration_ms;
            },
            .until_time => {
                const now: i64 = @intCast(w32.GetTickCount64());
                return now < self.end_time;
            },
            .toggle => {
                return true;
            },
            .count_limited => {
                return self.count_current < self.count_limit;
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

pub fn TimedRegistry(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("TimedRegistry capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("TimedRegistry capacity exceeds maximum");
    }

    return struct {
        const Self = @This();

        const Base = base_mod.BaseRegistry(Entry, capacity, .{});

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
            std.debug.assert(self.is_valid());
            std.debug.assert(binding_id >= 1);

            if (options.mode == .duration and (options.duration_ms == 0 or options.duration_ms > duration_max_ms)) {
                return Error.InvalidValue;
            }

            if (options.mode == .count_limited and options.count_limit == 0) {
                return Error.InvalidValue;
            }

            const allocation = try self.base.allocate();

            std.debug.assert(allocation.slot < capacity);
            std.debug.assert(allocation.id >= 1);

            const initial_enabled = options.mode != .duration and options.mode != .toggle;

            self.base.slot.entries[allocation.slot] = Entry{
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
                .start_time = if (options.mode == .until_time) @intCast(w32.GetTickCount64()) else 0,
                .count_current = 0,
            };

            std.debug.assert(self.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            _ = self.base.free_by_id(id) catch return error.NotFound;
        }

        pub fn process(self: *Self, binding_id: u32, key: *const Key) ?Response {
            std.debug.assert(self.is_valid());
            std.debug.assert(binding_id >= 1);
            std.debug.assert(key.is_valid());

            const entries = self.base.entries();

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

                if (e.invoke(key)) |response| {
                    std.debug.assert(response.is_valid());
                    return response;
                }

                return .consume;
            }

            return null;
        }

        pub fn start(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            const entry = self.base.get_by_id(id) orelse return error.NotFound;

            std.debug.assert(entry.is_active());

            if (entry.mode == .duration) {
                entry.start_time = @intCast(w32.GetTickCount64());
            }

            entry.set_enabled(true);
            entry.expired = false;
            entry.count_current = 0;
        }

        pub fn stop(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            const entry = self.base.get_by_id(id) orelse return error.NotFound;

            std.debug.assert(entry.is_active());

            entry.set_enabled(false);
        }

        pub fn toggle(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            const entry = self.base.get_by_id(id) orelse return error.NotFound;

            std.debug.assert(entry.is_active());

            if (entry.is_enabled()) {
                entry.set_enabled(false);
            } else {
                if (entry.mode == .duration) {
                    entry.start_time = @intCast(w32.GetTickCount64());
                }

                entry.set_enabled(true);
                entry.expired = false;
                entry.count_current = 0;
            }
        }

        pub fn is_enabled(self: *const Self, id: u32) ?bool {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            const slot = self.base.find_by_id(id) orelse return null;

            return self.base.slot.entries[slot].is_enabled();
        }

        pub fn is_expired(self: *const Self, id: u32) ?bool {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            const slot = self.base.find_by_id(id) orelse return null;

            return self.base.slot.entries[slot].expired;
        }

        pub fn get_remaining_count(self: *const Self, id: u32) ?u32 {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            const slot = self.base.find_by_id(id) orelse return null;

            const entry = &self.base.slot.entries[slot];

            if (entry.mode != .count_limited) {
                return null;
            }

            if (entry.count_current >= entry.count_limit) {
                return 0;
            }

            return entry.count_limit - entry.count_current;
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.base.clear();
        }
    };
}
