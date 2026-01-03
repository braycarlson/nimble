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

pub const lookup_size: u32 = 256 * 16;
pub const capacity_default: u32 = 128;
pub const capacity_max: u32 = 1024;

pub const Error = base_mod.BaseError || error{
    AlreadyRegistered,
    InvalidSlot,
};

pub const Callback = *const fn (context: *anyopaque, key: *const Key) Response;

pub const Entry = struct {
    base: entry_mod.FilteredEntry(Callback, WindowFilter) = .{},
    key: u8 = 0,
    modifiers: modifier.Set = .{},
    pause_exempt: bool = false,

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

    pub fn invoke(self: *const Entry, k: *const Key) ?Response {
        return self.base.invoke(.{k});
    }

    pub fn is_valid(self: *const Entry) bool {
        if (!self.is_active()) {
            return true;
        }

        const valid_base = self.base.is_valid();
        const valid_modifiers = self.modifiers.flags <= modifier.flag_all;

        return valid_base and valid_modifiers;
    }
};

const Invocation = struct {
    callback: Callback,
    context: *anyopaque,
};

pub const Options = struct {
    filter: WindowFilter = .{},
    pause_exempt: bool = false,
};

pub fn KeyRegistry(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("KeyRegistry capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("KeyRegistry capacity exceeds maximum");
    }

    return struct {
        const Self = @This();

        const Base = base_mod.BaseRegistry(Entry, capacity, .{
            .has_mutex = true,
            .has_paused = true,
        });

        base: Base = Base.init(),
        lookup: [lookup_size]?u32 = [_]?u32{null} ** lookup_size,

        pub fn init() Self {
            return Self{};
        }

        pub fn is_valid(self: *const Self) bool {
            return self.base.is_valid();
        }

        pub fn set_paused(self: *Self, value: bool) void {
            self.base.set_paused(value);
        }

        pub fn is_paused(self: *Self) bool {
            return self.base.is_paused();
        }

        pub fn clear(self: *Self) void {
            self.base.lock();
            defer self.base.unlock();

            self.base.clear_locked();

            for (&self.lookup) |*slot| {
                slot.* = null;
            }
        }

        pub fn process(self: *Self, key: *const Key) ?Response {
            std.debug.assert(key.is_valid());

            const invocation = blk: {
                self.base.lock();
                defer self.base.unlock();

                std.debug.assert(self.is_valid());

                if (self.base.is_paused()) {
                    break :blk self.resolve_exempt_locked(key);
                }

                break :blk self.resolve_locked(key);
            };

            if (invocation) |inv| {
                return inv.callback(inv.context, key);
            }

            return null;
        }

        fn resolve_locked(self: *Self, key: *const Key) ?Invocation {
            std.debug.assert(key.is_valid());

            const index = pack_lookup(key.value, key.modifiers);

            std.debug.assert(index < lookup_size);

            const slot = self.lookup[index] orelse return null;

            std.debug.assert(slot < capacity);

            const entry = &self.base.slot.entries[slot];

            if (!entry.is_active()) {
                return null;
            }

            if (!entry.matches_filter()) {
                return null;
            }

            const callback = entry.get_callback() orelse return null;
            const context = entry.get_context() orelse return null;

            return Invocation{
                .callback = callback,
                .context = context,
            };
        }

        fn resolve_exempt_locked(self: *Self, key: *const Key) ?Invocation {
            std.debug.assert(self.is_valid());
            std.debug.assert(key.is_valid());
            std.debug.assert(self.base.is_paused());

            const index = pack_lookup(key.value, key.modifiers);

            std.debug.assert(index < lookup_size);

            const slot = self.lookup[index] orelse return null;

            std.debug.assert(slot < capacity);

            const entry = &self.base.slot.entries[slot];

            if (!entry.is_active()) {
                return null;
            }

            if (!entry.pause_exempt) {
                return null;
            }

            if (!entry.matches_filter()) {
                return null;
            }

            const callback = entry.get_callback() orelse return null;
            const context = entry.get_context() orelse return null;

            return Invocation{
                .callback = callback,
                .context = context,
            };
        }

        pub fn find(self: *Self, key: *const Key) ?*Entry {
            std.debug.assert(key.is_valid());

            self.base.lock();
            defer self.base.unlock();

            std.debug.assert(self.is_valid());

            const index = pack_lookup(key.value, key.modifiers);

            std.debug.assert(index < lookup_size);

            const slot = self.lookup[index] orelse return null;

            std.debug.assert(slot < capacity);

            return &self.base.slot.entries[slot];
        }

        pub fn register(
            self: *Self,
            key: u8,
            modifiers: modifier.Set,
            callback: Callback,
            context: ?*anyopaque,
            options: Options,
        ) Error!u32 {
            std.debug.assert(modifiers.flags <= modifier.flag_all);

            self.base.lock();
            defer self.base.unlock();

            std.debug.assert(self.is_valid());

            const index = pack_lookup(key, modifiers);

            std.debug.assert(index < lookup_size);

            if (self.lookup[index] != null) {
                return error.AlreadyRegistered;
            }

            const allocation = self.base.allocate_locked() catch return error.RegistryFull;

            std.debug.assert(allocation.slot < capacity);
            std.debug.assert(allocation.id >= 1);

            self.base.slot.entries[allocation.slot] = Entry{
                .base = .{
                    .base = .{
                        .id = allocation.id,
                        .callback = callback,
                        .context = @ptrCast(@alignCast(context)),
                        .active = true,
                    },
                    .filter = options.filter,
                },
                .key = key,
                .modifiers = modifiers,
                .pause_exempt = options.pause_exempt,
            };

            self.lookup[index] = allocation.slot;

            std.debug.assert(self.base.slot.entries[allocation.slot].is_valid());
            std.debug.assert(self.lookup[index] != null);

            return allocation.id;
        }

        pub fn unregister(self: *Self, id: u32) Error!void {
            std.debug.assert(id >= 1);

            self.base.lock();
            defer self.base.unlock();

            std.debug.assert(self.is_valid());

            const slot = self.base.find_by_id(id) orelse return error.NotFound;

            std.debug.assert(slot < capacity);

            const entry = &self.base.slot.entries[slot];
            const index = pack_lookup(entry.key, entry.modifiers);

            std.debug.assert(index < lookup_size);

            self.lookup[index] = null;

            _ = self.base.free_by_id_locked(id) catch return error.NotFound;
        }

        fn pack_lookup(key: u8, modifiers: modifier.Set) u32 {
            std.debug.assert(modifiers.flags <= modifier.flag_all);

            const bits: u4 = modifiers.to_bits();
            const result = (@as(u32, key) << 4) | bits;

            std.debug.assert(result < lookup_size);

            return result;
        }
    };
}
