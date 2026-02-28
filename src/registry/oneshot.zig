const std = @import("std");

const key_event = @import("../event/key.zig");
const response_mod = @import("../response.zig");
const base_mod = @import("../registry/base.zig");
const entry_mod = @import("../registry/entry.zig");

const Key = key_event.Key;
const Response = response_mod.Response;

pub const capacity_default: u32 = 32;
pub const capacity_max: u32 = 128;

pub const Error = base_mod.BaseError;

pub const Callback = *const fn (context: *anyopaque, key: *const Key) Response;

pub const Entry = struct {
    base: entry_mod.BindingEntry(Callback) = .{},
    fired: bool = false,

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

    pub fn is_valid(self: *const Entry) bool {
        return self.base.is_valid();
    }

    pub fn invoke(self: *const Entry, key: *const Key) ?Response {
        return self.base.invoke(.{key});
    }
};

pub fn OneShotRegistry(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("OneShotRegistry capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("OneShotRegistry capacity exceeds maximum");
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
        ) Error!u32 {
            std.debug.assert(self.is_valid());
            std.debug.assert(binding_id >= 1);

            const allocation = try self.base.allocate();

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
                .fired = false,
            };

            std.debug.assert(self.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            _ = try self.base.free_by_id(id);
        }

        pub fn process(self: *Self, binding_id: u32, key: *const Key) ?Response {
            std.debug.assert(self.is_valid());
            std.debug.assert(key.is_valid());
            std.debug.assert(binding_id >= 1);

            const entries = self.base.entries();

            for (entries) |*e| {
                if (!e.is_active()) {
                    continue;
                }

                if (e.get_binding_id() != binding_id) {
                    continue;
                }

                if (!e.is_enabled() or e.fired) {
                    continue;
                }

                e.fired = true;

                if (e.invoke(key)) |response| {
                    std.debug.assert(response.is_valid());
                    return response;
                }

                return .consume;
            }

            return null;
        }

        pub fn reset(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            const entry = self.base.get_by_id(id) orelse return error.NotFound;

            std.debug.assert(entry.is_active());

            entry.fired = false;
            entry.set_enabled(true);
        }

        pub fn reset_all(self: *Self) void {
            std.debug.assert(self.is_valid());

            const entries = self.base.entries();

            for (entries) |*e| {
                if (e.is_active()) {
                    e.fired = false;
                    e.set_enabled(true);
                }
            }
        }

        pub fn is_fired(self: *const Self, id: u32) ?bool {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            const slot = self.base.find_by_id(id) orelse return null;

            return self.base.slot.entries[slot].fired;
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.base.clear();
        }
    };
}
