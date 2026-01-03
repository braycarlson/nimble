const std = @import("std");

const w32 = @import("win32").everything;

const base_mod = @import("base.zig");
const entry_mod = @import("entry.zig");

pub const capacity_default: u32 = 32;
pub const capacity_max: u32 = 128;
pub const interval_min_ms: u32 = 10;
pub const interval_max_ms: u32 = 86400000;
pub const tick_interval_ms: u32 = 10;

pub const Error = base_mod.BaseError || error{
    AlreadyActive,
    InvalidValue,
    NotActive,
    SetupFailed,
};

var global_instance: ?*anyopaque = null;
var global_timer_id: ?usize = null;
var global_tick_fn: ?*const fn () void = null;

fn timer_callback(_: w32.HWND, _: u32, _: usize, _: u32) callconv(.c) void {
    if (global_tick_fn) |tick_fn| {
        tick_fn();
    }
}

pub const Callback = *const fn (context: *anyopaque) void;

pub const Entry = struct {
    base: entry_mod.BaseEntry(Callback) = .{},
    binding_id: u32 = 0,
    interval_ms: u32 = 1000,
    repeat: bool = true,
    fired: bool = false,
    running: bool = false,
    last_tick: i64 = 0,

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

    pub fn invoke(self: *const Entry) void {
        _ = self.base.invoke(.{});
    }

    pub fn is_valid(self: *const Entry) bool {
        if (!self.is_active()) {
            return true;
        }

        const valid_base = self.base.is_base_valid();
        const valid_interval = self.interval_ms >= interval_min_ms and
            self.interval_ms <= interval_max_ms;

        return valid_base and valid_interval;
    }
};

pub const Options = struct {
    binding_id: u32 = 0,
    repeat: bool = true,
};

pub fn TimerRegistry(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("TimerRegistry capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("TimerRegistry capacity exceeds maximum");
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

        pub fn set_global(self: *Self) void {
            global_instance = self;
            global_tick_fn = @ptrCast(&Self.tick_static);

            if (global_timer_id == null) {
                global_timer_id = w32.SetTimer(null, 0, tick_interval_ms, @ptrCast(&timer_callback));
            }
        }

        fn tick_static() void {
            if (global_instance) |ptr| {
                const self: *Self = @ptrCast(@alignCast(ptr));
                self.tick();
            }
        }

        pub fn clear_global(_: *Self) void {
            if (global_timer_id) |id| {
                _ = w32.KillTimer(null, id);
                global_timer_id = null;
            }

            global_instance = null;
            global_tick_fn = null;
        }

        pub fn register(
            self: *Self,
            interval_ms: u32,
            callback: Callback,
            context: ?*anyopaque,
            options: Options,
        ) Error!u32 {
            std.debug.assert(self.is_valid());

            if (interval_ms < interval_min_ms or interval_ms > interval_max_ms) {
                return Error.InvalidValue;
            }

            self.base.lock();
            defer self.base.unlock();

            const allocation = self.base.allocate_locked() catch return error.RegistryFull;

            std.debug.assert(allocation.slot < capacity);
            std.debug.assert(allocation.id >= 1);

            self.base.slot.entries[allocation.slot] = Entry{
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

            std.debug.assert(self.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(self: *Self, id: u32) Error!void {
            std.debug.assert(id >= 1);

            self.base.lock();
            defer self.base.unlock();

            _ = self.base.free_by_id_locked(id) catch return error.NotFound;
        }

        pub fn start(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            self.base.lock();
            defer self.base.unlock();

            const slot = self.base.find_by_id(id) orelse return error.NotFound;

            if (self.base.slot.entries[slot].running) {
                return error.AlreadyActive;
            }

            self.base.slot.entries[slot].running = true;
            self.base.slot.entries[slot].last_tick = std.time.milliTimestamp();
        }

        pub fn stop(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            self.base.lock();
            defer self.base.unlock();

            const slot = self.base.find_by_id(id) orelse return error.NotFound;

            if (!self.base.slot.entries[slot].running) {
                return error.NotActive;
            }

            self.base.slot.entries[slot].running = false;
        }

        pub fn stop_all(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.base.lock();
            defer self.base.unlock();

            const entries = self.base.entries();

            for (entries) |*e| {
                if (e.is_active() and e.running) {
                    e.running = false;
                }
            }
        }

        pub fn is_running(self: *Self, id: u32) ?bool {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            self.base.lock();
            defer self.base.unlock();

            const slot = self.base.find_by_id(id) orelse return null;

            return self.base.slot.entries[slot].running;
        }

        pub fn has_fired(self: *Self, id: u32) ?bool {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            self.base.lock();
            defer self.base.unlock();

            const slot = self.base.find_by_id(id) orelse return null;

            return self.base.slot.entries[slot].fired;
        }

        pub fn process_binding(self: *Self, binding_id: u32, down: bool) void {
            std.debug.assert(self.is_valid());
            std.debug.assert(binding_id >= 1);

            self.base.lock();
            defer self.base.unlock();

            const entries = self.base.entries();

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
                        e.last_tick = std.time.milliTimestamp();
                    }
                } else {
                    e.running = false;
                }
            }
        }

        pub fn tick(self: *Self) void {
            std.debug.assert(self.is_valid());

            var pending: [capacity_max]struct { callback: Callback, context: ?*anyopaque } = undefined;
            var pending_count: u32 = 0;

            {
                self.base.lock();
                defer self.base.unlock();

                const now = std.time.milliTimestamp();
                const entries = self.base.entries();

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
                            if (pending_count < capacity_max) {
                                pending[pending_count] = .{
                                    .callback = cb,
                                    .context = e.get_context(),
                                };
                                pending_count += 1;
                            }
                        }

                        e.fired = true;
                        e.last_tick = now;

                        if (!e.repeat) {
                            e.running = false;
                        }
                    }
                }
            }

            for (pending[0..pending_count]) |p| {
                if (p.context) |ctx| {
                    p.callback(ctx);
                }
            }
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.base.clear();
        }
    };
}
