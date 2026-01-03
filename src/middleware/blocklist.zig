const std = @import("std");

const key_event = @import("../event/key.zig");
const modifier = @import("../modifier.zig");
const response_mod = @import("../response.zig");
const base = @import("base.zig");

const Key = key_event.Key;
const Response = response_mod.Response;
const Next = base.Next;

pub const BlockedBinding = struct {
    key: u8,
    modifiers: modifier.Set,
};

pub fn BlockListMiddleware(comptime capacity: u32) type {
    return struct {
        const Self = @This();

        blocked: [capacity]?BlockedBinding = [_]?BlockedBinding{null} ** capacity,
        count: u32 = 0,
        enabled: bool = true,

        pub fn init() Self {
            const result = Self{};

            std.debug.assert(result.count == 0);
            std.debug.assert(result.enabled);

            return result;
        }

        pub fn add(self: *Self, binding: BlockedBinding) !u32 {
            std.debug.assert(self.count <= capacity);
            std.debug.assert(binding.modifiers.flags <= modifier.flag_all);

            if (self.count >= capacity) {
                return error.BlockListFull;
            }

            const slot = self.find_empty_slot() orelse return error.BlockListFull;

            std.debug.assert(slot < capacity);

            self.blocked[slot] = binding;
            self.count += 1;

            std.debug.assert(self.count <= capacity);
            std.debug.assert(self.blocked[slot] != null);

            return slot;
        }

        pub fn remove(self: *Self, slot: u32) !void {
            std.debug.assert(self.count <= capacity);

            if (slot >= capacity) {
                return error.InvalidSlot;
            }

            std.debug.assert(slot < capacity);

            if (self.blocked[slot] == null) {
                return error.NotFound;
            }

            self.blocked[slot] = null;
            self.count -= 1;

            std.debug.assert(self.count <= capacity);
        }

        pub fn process(self: *Self, key: *const Key, next: *const Next) Response {
            std.debug.assert(self.count <= capacity);
            std.debug.assert(key.is_valid());

            if (!self.enabled) {
                return next.invoke(key);
            }

            if (!key.down) {
                return next.invoke(key);
            }

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                std.debug.assert(i < capacity);

                if (self.blocked[i]) |binding| {
                    if (key.value == binding.key) {
                        return .consume;
                    }
                }
            }

            std.debug.assert(i == capacity);

            return next.invoke(key);
        }

        fn find_empty_slot(self: *const Self) ?u32 {
            std.debug.assert(self.count <= capacity);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                std.debug.assert(i < capacity);

                if (self.blocked[i] == null) {
                    return i;
                }
            }

            std.debug.assert(i == capacity);

            return null;
        }

        pub fn set_enabled(self: *Self, value: bool) void {
            std.debug.assert(self.count <= capacity);

            self.enabled = value;
        }

        pub fn is_enabled(self: *const Self) bool {
            std.debug.assert(self.count <= capacity);

            return self.enabled;
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.count <= capacity);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                std.debug.assert(i < capacity);

                self.blocked[i] = null;
            }

            self.count = 0;

            std.debug.assert(self.count == 0);
            std.debug.assert(i == capacity);
        }
    };
}
