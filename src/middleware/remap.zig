const std = @import("std");

const key_event = @import("../event/key.zig");
const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const response = @import("../response.zig");
const base = @import("base.zig");

const Mutex = @import("../mutex.zig").Mutex;

const Key = key_event.Key;
const Response = response.Response;
const Next = base.Next;

pub const Mapping = struct {
    from_key: u8,
    from_modifiers: modifier.Set,
    to_key: u8,
    to_modifiers: modifier.Set,
};

pub fn RemapMiddleware(comptime capacity: u32) type {
    return struct {
        const Self = @This();

        mappings: [capacity]?Mapping = [_]?Mapping{null} ** capacity,
        count: u32 = 0,
        mutex: Mutex = .{},

        pub fn init() Self {
            const result = Self{};

            std.debug.assert(result.count == 0);
            std.debug.assert(capacity > 0);

            return result;
        }

        pub fn add(self: *Self, mapping: Mapping) !u32 {
            std.debug.assert(mapping.from_modifiers.flags <= modifier.flag_all);
            std.debug.assert(mapping.to_modifiers.flags <= modifier.flag_all);

            if (!keycode.is_valid(mapping.from_key)) {
                return error.InvalidKey;
            }

            if (!keycode.is_valid(mapping.to_key)) {
                return error.InvalidKey;
            }

            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);

            if (self.count >= capacity) {
                return error.RemapFull;
            }

            const slot = self.find_empty_slot() orelse return error.RemapFull;

            std.debug.assert(slot < capacity);

            self.mappings[slot] = mapping;
            self.count += 1;

            std.debug.assert(self.count <= capacity);
            std.debug.assert(self.mappings[slot] != null);

            return slot;
        }

        pub fn remove(self: *Self, slot: u32) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);

            if (slot >= capacity) {
                return error.InvalidSlot;
            }

            std.debug.assert(slot < capacity);

            if (self.mappings[slot] == null) {
                return error.NotFound;
            }

            self.mappings[slot] = null;
            self.count -= 1;

            std.debug.assert(self.count <= capacity);
        }

        pub fn process(self: *Self, key: *const Key, next: *const Next) Response {
            std.debug.assert(key.is_valid());

            const found = self.find_mapping(key);

            if (found) |mapping| {
                var remapped = key.*;

                remapped.value = mapping.to_key;
                remapped.modifiers = mapping.to_modifiers;

                std.debug.assert(remapped.is_valid());

                return next.invoke(&remapped);
            }

            return next.invoke(key);
        }

        fn find_mapping(self: *Self, key: *const Key) ?Mapping {
            std.debug.assert(key.is_valid());

            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                if (self.mappings[i]) |mapping| {
                    if (self.matches(key, &mapping)) {
                        return mapping;
                    }
                }
            }

            std.debug.assert(i == capacity);

            return null;
        }

        fn matches(_: *Self, key: *const Key, mapping: *const Mapping) bool {
            std.debug.assert(key.is_valid());
            std.debug.assert(mapping.from_modifiers.flags <= modifier.flag_all);

            if (key.value != mapping.from_key) {
                return false;
            }

            return key.modifiers.eql(&mapping.from_modifiers);
        }

        fn find_empty_slot(self: *const Self) ?u32 {
            std.debug.assert(self.count <= capacity);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                if (self.mappings[i] == null) {
                    return i;
                }
            }

            std.debug.assert(i == capacity);

            return null;
        }

        pub fn clear(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                self.mappings[i] = null;
            }

            self.count = 0;

            std.debug.assert(self.count == 0);
            std.debug.assert(i == capacity);
        }
    };
}
