const std = @import("std");

const key_event = @import("../event/key.zig");
const modifier = @import("../modifier.zig");
const response = @import("../response.zig");
const base = @import("base.zig");

const Mutex = @import("../mutex.zig").Mutex;

const Key = key_event.Key;
const Response = response.Response;
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
        mutex: Mutex = .{},

        pub fn init() Self {
            const result = Self{};

            std.debug.assert(result.count == 0);
            std.debug.assert(result.enabled);

            return result;
        }

        pub fn add(self: *Self, binding: BlockedBinding) !u32 {
            std.debug.assert(binding.modifiers.flags <= modifier.flag_all);

            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);

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
            self.mutex.lock();
            defer self.mutex.unlock();

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
            std.debug.assert(key.is_valid());

            if (self.is_blocked(key)) {
                return .consume;
            }

            const result = next.invoke(key);

            std.debug.assert(result.is_valid());

            return result;
        }

        fn is_blocked(self: *Self, key: *const Key) bool {
            std.debug.assert(key.is_valid());

            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);

            if (!self.enabled) {
                return false;
            }

            if (!key.down) {
                return false;
            }

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                if (self.blocked[i]) |binding| {
                    if (key.value == binding.key and key.modifiers.eql(&binding.modifiers)) {
                        return true;
                    }
                }
            }

            std.debug.assert(i == capacity);

            return false;
        }

        fn find_empty_slot(self: *const Self) ?u32 {
            std.debug.assert(self.count <= capacity);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                if (self.blocked[i] == null) {
                    return i;
                }
            }

            std.debug.assert(i == capacity);

            return null;
        }

        pub fn set_enabled(self: *Self, value: bool) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);

            self.enabled = value;

            std.debug.assert(self.enabled == value);
        }

        pub fn is_enabled(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);

            return self.enabled;
        }

        pub fn clear(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                self.blocked[i] = null;
            }

            self.count = 0;

            std.debug.assert(self.count == 0);
            std.debug.assert(i == capacity);
        }
    };
}
