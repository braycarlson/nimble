const std = @import("std");

pub const capacity_min: u32 = 1;
pub const capacity_max: u32 = 1024;

pub fn RollingBuffer(comptime capacity: u32) type {
    if (capacity < capacity_min) {
        @compileError("RollingBuffer capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("RollingBuffer capacity must be 1024 or less");
    }

    return struct {
        const Self = @This();

        buffer: [capacity]u8 = [_]u8{0} ** capacity,
        len: u32 = 0,

        pub fn init() Self {
            const result = Self{};

            std.debug.assert(result.len == 0);
            std.debug.assert(result.is_empty());

            return result;
        }

        pub fn is_valid(self: *const Self) bool {
            std.debug.assert(capacity >= capacity_min);
            std.debug.assert(capacity <= capacity_max);

            return self.len <= capacity;
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.len = 0;

            std.debug.assert(self.len == 0);
            std.debug.assert(self.is_empty());
        }

        pub fn get(self: *const Self, index: u32) ?u8 {
            std.debug.assert(self.is_valid());

            if (index >= self.len) {
                return null;
            }

            std.debug.assert(index < self.len);
            std.debug.assert(index < capacity);

            return self.buffer[index];
        }

        pub fn is_empty(self: *const Self) bool {
            std.debug.assert(self.is_valid());

            return self.len == 0;
        }

        pub fn length(self: *const Self) u32 {
            std.debug.assert(self.is_valid());

            return self.len;
        }

        pub fn slice(self: *const Self) []const u8 {
            std.debug.assert(self.is_valid());

            return self.buffer[0..self.len];
        }

        pub fn slice_from(self: *const Self, start: u32) []const u8 {
            std.debug.assert(self.is_valid());
            std.debug.assert(start <= self.len);

            return self.buffer[start..self.len];
        }

        pub fn slice_range(self: *const Self, start: u32, end: u32) []const u8 {
            std.debug.assert(self.is_valid());
            std.debug.assert(start <= end);
            std.debug.assert(end <= self.len);

            return self.buffer[start..end];
        }

        pub fn push(self: *Self, value: u8) void {
            std.debug.assert(self.is_valid());

            if (self.len >= capacity) {
                for (0..capacity - 1) |j| {
                    self.buffer[j] = self.buffer[j + 1];
                }

                self.len = capacity - 1;
            }

            self.buffer[self.len] = value;
            self.len += 1;

            std.debug.assert(self.is_valid());
            std.debug.assert(self.len >= 1);
            std.debug.assert(self.buffer[self.len - 1] == value);
        }

        pub fn pop(self: *Self) ?u8 {
            std.debug.assert(self.is_valid());

            if (self.len == 0) {
                return null;
            }

            self.len -= 1;

            const result = self.buffer[self.len];

            std.debug.assert(self.is_valid());

            return result;
        }
    };
}
