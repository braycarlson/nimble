const std = @import("std");

const slot_mod = @import("slot.zig");

pub const BaseError = error{
    NotFound,
    RegistryFull,
};

pub fn BaseRegistry(
    comptime Entry: type,
    comptime capacity: u32,
    comptime options: Options,
) type {
    return struct {
        const Self = @This();
        const Slot = slot_mod.SlotManager(Entry, capacity);

        slot: Slot = Slot.init(),
        paused: if (options.has_paused) bool else void = if (options.has_paused) false else {},
        mutex: if (options.has_mutex) std.Thread.Mutex else void = if (options.has_mutex) .{} else {},

        pub fn init() Self {
            return Self{};
        }

        pub fn is_valid(self: *const Self) bool {
            return self.slot.is_valid();
        }

        pub fn count(self: *const Self) u32 {
            return self.slot.count;
        }

        pub fn is_empty(self: *const Self) bool {
            return self.slot.count == 0;
        }

        pub fn set_paused(self: *Self, value: bool) void {
            if (options.has_mutex) {
                self.mutex.lock();
                defer self.mutex.unlock();
            }

            if (options.has_paused) {
                self.paused = value;
            }
        }

        pub fn is_paused(self: *const Self) bool {
            if (options.has_paused) {
                return self.paused;
            }
            return false;
        }

        pub fn allocate(self: *Self) BaseError!struct { slot: u32, id: u32 } {
            if (options.has_mutex) {
                self.mutex.lock();
                defer self.mutex.unlock();
            }

            const allocation = self.slot.allocate() orelse return error.RegistryFull;

            return .{
                .slot = allocation.slot,
                .id = allocation.id,
            };
        }

        pub fn allocate_locked(self: *Self) BaseError!struct { slot: u32, id: u32 } {
            const allocation = self.slot.allocate() orelse return error.RegistryFull;

            return .{
                .slot = allocation.slot,
                .id = allocation.id,
            };
        }

        pub fn free_by_id(self: *Self, id: u32) BaseError!u32 {
            std.debug.assert(id >= 1);

            if (options.has_mutex) {
                self.mutex.lock();
                defer self.mutex.unlock();
            }

            return self.slot.free_by_id(id) orelse return error.NotFound;
        }

        pub fn free_by_id_locked(self: *Self, id: u32) BaseError!u32 {
            std.debug.assert(id >= 1);

            return self.slot.free_by_id(id) orelse return error.NotFound;
        }

        pub fn get_by_id(self: *Self, id: u32) ?*Entry {
            return self.slot.get_by_id(id);
        }

        pub fn get(self: *Self, slot: u32) ?*Entry {
            return self.slot.get(slot);
        }

        pub fn find_by_id(self: *const Self, id: u32) ?u32 {
            return self.slot.find_by_id(id);
        }

        pub fn clear(self: *Self) void {
            if (options.has_mutex) {
                self.mutex.lock();
                defer self.mutex.unlock();
            }

            self.slot.clear();
        }

        pub fn clear_locked(self: *Self) void {
            self.slot.clear();
        }

        pub fn lock(self: *Self) void {
            if (options.has_mutex) {
                self.mutex.lock();
            }
        }

        pub fn unlock(self: *Self) void {
            if (options.has_mutex) {
                self.mutex.unlock();
            }
        }

        pub fn iterator(self: *Self) Slot.Iterator {
            return self.slot.iterator();
        }

        pub fn entries(self: *Self) *[capacity]Entry {
            return &self.slot.entries;
        }
    };
}

pub const Options = struct {
    has_mutex: bool = false,
    has_paused: bool = false,
};
