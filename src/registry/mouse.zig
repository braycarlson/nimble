const std = @import("std");

const response_mod = @import("../response.zig");
const filter_mod = @import("../filter.zig");
const event = @import("../event/mouse.zig");
const base_mod = @import("base.zig");
const entry_mod = @import("entry.zig");

const Response = response_mod.Response;
const Mouse = event.Mouse;
const MouseKind = event.Kind;
const WindowFilter = filter_mod.WindowFilter;

pub const capacity_default: u32 = 128;
pub const capacity_max: u32 = 1024;

pub const Error = base_mod.BaseError || error{
    AlreadyRegistered,
};

pub const Callback = *const fn (context: *anyopaque, mouse: *const Mouse) Response;

pub const Entry = struct {
    base: entry_mod.FilteredEntry(Callback, WindowFilter) = .{},
    kind: MouseKind = .other,

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

    pub fn is_valid(self: *const Entry) bool {
        if (!self.is_active()) {
            return true;
        }

        return self.base.is_valid() and self.kind.is_valid();
    }

    pub fn matches_filter(self: *const Entry) bool {
        return self.base.matches_filter();
    }

    pub fn invoke(self: *const Entry, mouse: *const Mouse) ?Response {
        return self.base.invoke(.{mouse});
    }
};

const Invocation = struct {
    callback: Callback,
    context: *anyopaque,
};

pub const Options = struct {
    filter: WindowFilter = .{},
};

pub fn MouseRegistry(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("MouseRegistry capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("MouseRegistry capacity exceeds maximum");
    }

    return struct {
        const Self = @This();

        const Base = base_mod.BaseRegistry(Entry, capacity, .{
            .has_mutex = true,
            .has_paused = true,
        });

        base: Base = Base.init(),

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
            self.base.clear();
        }

        pub fn process(self: *Self, mouse: *const Mouse) ?Response {
            std.debug.assert(mouse.is_valid());

            const invocation = blk: {
                self.base.lock();
                defer self.base.unlock();

                std.debug.assert(self.is_valid());

                if (self.base.is_paused()) {
                    break :blk null;
                }

                break :blk self.resolve_locked(mouse);
            };

            if (invocation) |inv| {
                return inv.callback(inv.context, mouse);
            }

            return null;
        }

        fn resolve_locked(self: *Self, mouse: *const Mouse) ?Invocation {
            std.debug.assert(mouse.is_valid());

            const entries = self.base.entries();

            for (entries) |*e| {
                if (!e.is_active()) {
                    continue;
                }

                if (e.kind != mouse.kind) {
                    continue;
                }

                if (!e.matches_filter()) {
                    continue;
                }

                const callback = e.get_callback() orelse continue;
                const context = e.get_context() orelse continue;

                return Invocation{
                    .callback = callback,
                    .context = context,
                };
            }

            return null;
        }

        pub fn register(
            self: *Self,
            kind: MouseKind,
            callback: Callback,
            context: ?*anyopaque,
            options: Options,
        ) Error!u32 {
            std.debug.assert(kind.is_valid());

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
                    .filter = options.filter,
                },
                .kind = kind,
            };

            std.debug.assert(self.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(self: *Self, id: u32) Error!void {
            std.debug.assert(id >= 1);

            _ = self.base.free_by_id(id) catch return error.NotFound;
        }
    };
}
