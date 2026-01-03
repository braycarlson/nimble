const std = @import("std");

pub const id_min: u32 = 1;
pub const id_max: u32 = 0xFFFFFFFF;

pub fn SlotManager(comptime Entry: type, comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("SlotManager capacity must be at least 1");
    }

    return struct {
        const Self = @This();

        entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
        count: u32 = 0,
        id_next: u32 = id_min,

        pub fn init() Self {
            const result = Self{};

            std.debug.assert(result.count == 0);
            std.debug.assert(result.id_next == id_min);
            std.debug.assert(result.entries.len == capacity);

            return result;
        }

        pub fn is_valid(self: *const Self) bool {
            std.debug.assert(self.entries.len == capacity);

            const valid_count = self.count <= capacity;
            const valid_id = self.id_next >= id_min;
            const valid_entries = self.validate_entries();

            return valid_count and valid_id and valid_entries;
        }

        fn validate_entries(self: *const Self) bool {
            var active_count: u32 = 0;
            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                if (self.entries[i].is_active()) {
                    active_count += 1;

                    if (!self.entries[i].is_valid()) {
                        return false;
                    }
                }
            }

            return active_count == self.count;
        }

        pub fn allocate(self: *Self) ?struct { slot: u32, id: u32 } {
            std.debug.assert(self.is_valid());

            if (self.count >= capacity) {
                return null;
            }

            const slot = self.find_empty() orelse return null;

            std.debug.assert(slot < capacity);
            std.debug.assert(!self.entries[slot].is_active());

            const id = self.id_next;

            self.id_next = if (self.id_next < id_max) self.id_next + 1 else id_min;
            self.count += 1;

            std.debug.assert(self.count <= capacity);
            std.debug.assert(self.count >= 1);
            std.debug.assert(id >= id_min);

            return .{
                .slot = slot,
                .id = id,
            };
        }

        pub fn free_by_id(self: *Self, id: u32) ?u32 {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= id_min);

            const slot = self.find_by_id(id) orelse return null;

            std.debug.assert(slot < capacity);
            std.debug.assert(self.entries[slot].is_active());

            self.entries[slot] = .{};
            self.count -= 1;

            std.debug.assert(!self.entries[slot].is_active());
            std.debug.assert(self.count < capacity or self.count == 0);

            return slot;
        }

        pub fn get_by_id(self: *Self, id: u32) ?*Entry {
            std.debug.assert(id >= id_min);

            const slot = self.find_by_id(id) orelse return null;

            std.debug.assert(slot < capacity);

            return &self.entries[slot];
        }

        pub fn get(self: *Self, slot: u32) ?*Entry {
            if (slot >= capacity) {
                return null;
            }

            std.debug.assert(slot < capacity);

            if (!self.entries[slot].is_active()) {
                return null;
            }

            return &self.entries[slot];
        }

        pub fn find_by_id(self: *const Self, id: u32) ?u32 {
            std.debug.assert(id >= id_min);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                std.debug.assert(i < capacity);

                if (self.entries[i].is_active() and self.entries[i].get_id() == id) {
                    return i;
                }
            }

            return null;
        }

        fn find_empty(self: *const Self) ?u32 {
            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                std.debug.assert(i < capacity);

                if (!self.entries[i].is_active()) {
                    return i;
                }
            }

            return null;
        }

        pub fn clear(self: *Self) void {
            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                std.debug.assert(i < capacity);

                self.entries[i] = .{};
            }

            self.count = 0;

            std.debug.assert(self.count == 0);
        }

        pub const Iterator = struct {
            slot: *Self,
            index: u32 = 0,

            pub fn next(self: *Iterator) ?*Entry {
                while (self.index < capacity) {
                    const i = self.index;
                    self.index += 1;

                    if (self.slot.entries[i].is_active()) {
                        return &self.slot.entries[i];
                    }
                }

                return null;
            }

            pub fn reset(self: *Iterator) void {
                self.index = 0;
            }
        };

        pub fn iterator(self: *Self) Iterator {
            return Iterator{ .slot = self };
        }
    };
}
