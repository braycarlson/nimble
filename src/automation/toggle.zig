const std = @import("std");

const key_event = @import("../event/key.zig");
const response_mod = @import("../response.zig");
const filter_mod = @import("../filter.zig");
const base_mod = @import("../registry/base.zig");
const entry_mod = @import("../registry/entry.zig");

const Key = key_event.Key;
const Response = response_mod.Response;
const WindowFilter = filter_mod.WindowFilter;

pub const capacity_default: u32 = 32;
pub const capacity_max: u32 = 128;
pub const toggle_count_max: u32 = 1000000;

pub const Error = base_mod.BaseError;

pub const ActionCallback = *const fn (context: *anyopaque, key: *const Key) Response;
pub const ToggleCallback = *const fn (context: *anyopaque, enabled: bool) void;

pub const Options = struct {
    filter: WindowFilter = .{},
    toggle_callback: ?ToggleCallback = null,
};

pub const Entry = struct {
    base: entry_mod.DualBindingFilteredEntry(ActionCallback, WindowFilter) = .{},
    toggle_callback: ?ToggleCallback = null,
    toggle_count: u32 = 0,

    pub fn get_id(self: *const Entry) u32 {
        return self.base.get_id();
    }

    pub fn get_context(self: *const Entry) ?*anyopaque {
        return self.base.get_context();
    }

    pub fn is_active(self: *const Entry) bool {
        return self.base.is_active();
    }

    pub fn is_valid(self: *const Entry) bool {
        if (!self.is_active()) {
            return true;
        }

        const valid_base = self.base.is_valid();
        const valid_count = self.toggle_count <= toggle_count_max;

        return valid_base and valid_count;
    }

    pub fn matches_filter(self: *const Entry) bool {
        return self.base.matches_filter();
    }

    pub fn invoke_action(self: *const Entry, key: *const Key) ?Response {
        return self.base.invoke(.{key});
    }

    pub fn invoke_toggle(self: *Entry) void {
        if (self.toggle_callback) |callback| {
            if (self.base.get_context()) |context| {
                callback(context, self.base.enabled);
            }
        }
    }
};

pub fn ToggleRegistry(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("ToggleRegistry capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("ToggleRegistry capacity exceeds maximum");
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
            action_binding_id: u32,
            toggle_binding_id: u32,
            action_callback: ActionCallback,
            context: ?*anyopaque,
            options: Options,
        ) Error!u32 {
            std.debug.assert(action_binding_id >= 1);
            std.debug.assert(toggle_binding_id >= 1);

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
                        .callback = action_callback,
                        .context = context,
                        .active = true,
                    },
                    .action_binding_id = action_binding_id,
                    .toggle_binding_id = toggle_binding_id,
                    .filter = options.filter,
                    .enabled = false,
                },
                .toggle_callback = options.toggle_callback,
                .toggle_count = 0,
            };

            std.debug.assert(self.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(self: *Self, id: u32) Error!void {
            std.debug.assert(id >= 1);

            self.base.lock();
            defer self.base.unlock();

            std.debug.assert(self.is_valid());

            _ = self.base.free_by_id_locked(id) catch return error.NotFound;
        }

        pub fn process(self: *Self, binding_id: u32, key: *const Key) ?Response {
            std.debug.assert(binding_id >= 1);
            std.debug.assert(key.is_valid());

            self.base.lock();
            defer self.base.unlock();

            std.debug.assert(self.is_valid());

            const entries = self.base.entries();

            for (entries) |*e| {
                if (!e.is_active()) {
                    continue;
                }

                if (e.base.action_binding_id != binding_id) {
                    continue;
                }

                if (!e.base.enabled) {
                    continue;
                }

                if (!e.matches_filter()) {
                    continue;
                }

                if (e.invoke_action(key)) |response| {
                    std.debug.assert(response.is_valid());
                    return response;
                }

                return .consume;
            }

            return null;
        }

        pub fn process_toggle(self: *Self, binding_id: u32) void {
            std.debug.assert(binding_id >= 1);

            self.base.lock();
            defer self.base.unlock();

            std.debug.assert(self.is_valid());

            const entries = self.base.entries();

            for (entries) |*entry| {
                if (!entry.is_active()) {
                    continue;
                }

                if (entry.base.toggle_binding_id != binding_id) {
                    continue;
                }

                entry.base.enabled = !entry.base.enabled;
                entry.toggle_count += 1;
                entry.invoke_toggle();
            }
        }

        pub fn is_enabled(self: *Self, id: u32) ?bool {
            std.debug.assert(id >= 1);

            self.base.lock();
            defer self.base.unlock();

            std.debug.assert(self.is_valid());

            const slot = self.base.find_by_id(id) orelse return null;

            return self.base.slot.entries[slot].base.enabled;
        }

        pub fn get_toggle_count(self: *Self, id: u32) ?u32 {
            std.debug.assert(id >= 1);

            self.base.lock();
            defer self.base.unlock();

            std.debug.assert(self.is_valid());

            const slot = self.base.find_by_id(id) orelse return null;

            return self.base.slot.entries[slot].toggle_count;
        }

        pub fn clear(self: *Self) void {
            self.base.lock();
            defer self.base.unlock();

            std.debug.assert(self.is_valid());

            self.base.clear_locked();
        }
    };
}
