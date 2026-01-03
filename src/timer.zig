const std = @import("std");

const slot_mod = @import("registry/slot.zig");

pub const capacity_default: u8 = 16;
pub const capacity_max: u8 = 64;
pub const interval_min_ms: u32 = 10;
pub const interval_max_ms: u32 = 86400000;
pub const fired_max: u8 = 255;

pub const Error = error{
    AlreadyActive,
    InvalidValue,
    NotActive,
    NotFound,
    RegistryFull,
};

pub const Callback = *const fn (context: *anyopaque, timer_id: u32) void;

pub const Entry = struct {
    id: u32 = 0,
    callback: ?Callback = null,
    context: ?*anyopaque = null,
    interval_ms: u32 = 1000,
    repeat: bool = true,
    active: bool = false,
    fired: bool = false,
    running: bool = false,
    last_tick: i64 = 0,

    pub fn get_id(self: *const Entry) u32 {
        return self.id;
    }

    pub fn is_active(self: *const Entry) bool {
        return self.active;
    }

    pub fn is_valid(self: *const Entry) bool {
        if (!self.active) {
            return true;
        }

        const valid_callback = self.callback != null;
        const valid_interval = self.interval_ms >= interval_min_ms and
            self.interval_ms <= interval_max_ms;
        const valid_id = self.id >= 1;

        return valid_callback and valid_interval and valid_id;
    }
};

pub fn TimerRegistry(comptime capacity: u8) type {
    if (capacity == 0) {
        @compileError("TimerRegistry capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("TimerRegistry capacity exceeds maximum");
    }

    return struct {
        const Self = @This();

        const Slot = slot_mod.SlotManager(Entry, capacity);

        slot: Slot = Slot.init(),
        enabled: bool = true,

        pub fn init() Self {
            return Self{};
        }

        pub fn is_valid(self: *const Self) bool {
            return self.slot.is_valid();
        }

        pub fn register(
            self: *Self,
            interval_ms: u32,
            callback: Callback,
            context: ?*anyopaque,
            repeat_timer: bool,
        ) Error!u32 {
            std.debug.assert(self.is_valid());

            if (interval_ms < interval_min_ms or interval_ms > interval_max_ms) {
                return Error.InvalidValue;
            }

            const allocation = self.slot.allocate() orelse return error.RegistryFull;

            std.debug.assert(allocation.slot < capacity);
            std.debug.assert(allocation.id >= 1);

            self.slot.entries[allocation.slot] = Entry{
                .id = allocation.id,
                .callback = callback,
                .context = context,
                .interval_ms = interval_ms,
                .repeat = repeat_timer,
                .active = true,
                .fired = false,
                .running = false,
                .last_tick = 0,
            };

            std.debug.assert(self.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            _ = self.slot.free_by_id(id) orelse return error.NotFound;
        }

        pub fn start(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            const entry = self.slot.get_by_id(id) orelse return error.NotFound;

            if (entry.running) {
                return error.AlreadyActive;
            }

            entry.running = true;
            entry.fired = false;
            entry.last_tick = std.time.milliTimestamp();
        }

        pub fn stop(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            const entry = self.slot.get_by_id(id) orelse return error.NotFound;

            if (!entry.running) {
                return error.NotActive;
            }

            entry.running = false;
        }

        pub fn tick(self: *Self) u8 {
            std.debug.assert(self.is_valid());

            if (!self.enabled) {
                return 0;
            }

            const now = std.time.milliTimestamp();
            var fired: u8 = 0;

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                std.debug.assert(i < capacity);

                const entry = &self.slot.entries[i];

                if (!entry.active or !entry.running) {
                    continue;
                }

                if (!entry.repeat and entry.fired) {
                    continue;
                }

                const should_fire = self.check_elapsed(entry, now);

                if (should_fire) {
                    entry.last_tick = now;
                    entry.fired = true;

                    if (fired < fired_max) {
                        fired += 1;
                    }

                    self.invoke_callback(entry);
                }
            }

            return fired;
        }

        fn check_elapsed(self: *const Self, entry: *const Entry, now: i64) bool {
            _ = self;

            if (entry.last_tick == 0) {
                return false;
            }

            if (now < entry.last_tick) {
                return false;
            }

            const elapsed: i64 = now - entry.last_tick;

            return elapsed >= entry.interval_ms;
        }

        fn invoke_callback(self: *Self, entry: *Entry) void {
            _ = self;

            if (entry.callback) |callback| {
                const context = entry.context orelse return;

                callback(context, entry.id);
            }
        }

        pub fn get_remaining(self: *const Self, id: u32) ?u32 {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            const slot = self.slot.find_by_id(id) orelse return null;

            std.debug.assert(slot < capacity);

            const entry = &self.slot.entries[slot];

            if (!entry.running) {
                return null;
            }

            const now = std.time.milliTimestamp();

            if (now < entry.last_tick) {
                return entry.interval_ms;
            }

            const elapsed: i64 = now - entry.last_tick;

            if (elapsed >= entry.interval_ms) {
                return 0;
            }

            const remaining: i64 = entry.interval_ms - elapsed;

            return @intCast(remaining);
        }

        pub fn is_running(self: *const Self, id: u32) ?bool {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            const slot = self.slot.find_by_id(id) orelse return null;

            std.debug.assert(slot < capacity);

            return self.slot.entries[slot].running;
        }

        pub fn set_enabled(self: *Self, value: bool) void {
            self.enabled = value;
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.slot.clear();
        }
    };
}
