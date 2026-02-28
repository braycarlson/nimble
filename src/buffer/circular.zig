const std = @import("std");

pub const capacity_min: u32 = 1;
pub const capacity_max: u32 = 1024;

pub const Error = error{
    EmptyPattern,
    PatternTooLarge,
};

pub fn CircularBuffer(comptime capacity: u32) type {
    if (capacity < capacity_min) {
        @compileError("CircularBuffer capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("CircularBuffer capacity must be 1024 or less");
    }

    return struct {
        const Self = @This();

        buffer: [capacity]u8 = [_]u8{0} ** capacity,
        head: u32 = 0,
        tail: u32 = 0,

        pub fn init() Self {
            const result = Self{};

            std.debug.assert(result.head == 0);
            std.debug.assert(result.tail == 0);
            std.debug.assert(result.is_empty());

            return result;
        }

        pub fn is_valid(self: *const Self) bool {
            std.debug.assert(capacity >= capacity_min);
            std.debug.assert(capacity <= capacity_max);

            const head_valid = self.head < capacity;
            const tail_valid = self.tail < capacity;

            return head_valid and tail_valid;
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.head = 0;
            self.tail = 0;

            std.debug.assert(self.head == 0);
            std.debug.assert(self.tail == 0);
            std.debug.assert(self.is_empty());
        }

        pub fn get(self: *const Self, index: u32) ?u8 {
            std.debug.assert(self.is_valid());

            const length_current = self.length();

            if (index >= length_current) {
                return null;
            }

            std.debug.assert(index < length_current);
            std.debug.assert(index < capacity);

            const position = wrap(self.head + index);

            std.debug.assert(position < capacity);

            return self.buffer[position];
        }

        pub fn is_empty(self: *const Self) bool {
            std.debug.assert(self.is_valid());

            return self.head == self.tail;
        }

        pub fn length(self: *const Self) u32 {
            std.debug.assert(self.is_valid());

            var result: u32 = 0;

            if (self.tail >= self.head) {
                result = self.tail - self.head;
            } else {
                result = capacity - self.head + self.tail;
            }

            std.debug.assert(result < capacity);

            return result;
        }

        pub fn match(self: *const Self, pattern: []const u8) Error!bool {
            std.debug.assert(self.is_valid());

            const size: u32 = @intCast(pattern.len);

            if (size == 0) {
                return Error.EmptyPattern;
            }

            if (size > capacity) {
                return Error.PatternTooLarge;
            }

            std.debug.assert(size > 0);
            std.debug.assert(size <= capacity);

            const length_current = self.length();

            if (length_current < size) {
                return false;
            }

            std.debug.assert(length_current >= size);

            return self.compare(pattern, size);
        }

        pub fn push(self: *Self, value: u8) void {
            std.debug.assert(self.is_valid());

            self.buffer[self.tail] = value;
            self.tail = wrap(self.tail + 1);

            if (self.tail == self.head) {
                self.head = wrap(self.head + 1);
            }

            std.debug.assert(self.is_valid());
            std.debug.assert(self.buffer[wrap(self.tail + capacity - 1)] == value);
        }

        pub fn pop(self: *Self) ?u8 {
            std.debug.assert(self.is_valid());

            if (self.is_empty()) {
                return null;
            }

            self.tail = decrement(self.tail);

            const result = self.buffer[self.tail];

            std.debug.assert(self.is_valid());

            return result;
        }

        fn compare(self: *const Self, pattern: []const u8, size: u32) bool {
            std.debug.assert(self.is_valid());
            std.debug.assert(size > 0);
            std.debug.assert(size <= capacity);
            std.debug.assert(self.length() >= size);

            var index: u32 = size;
            var cursor: u32 = self.tail;
            var iteration: u32 = 0;

            while (iteration < capacity) : (iteration += 1) {
                std.debug.assert(iteration < capacity);

                if (index == 0) {
                    break;
                }

                std.debug.assert(index > 0);
                std.debug.assert(index <= size);

                cursor = decrement(cursor);

                std.debug.assert(cursor < capacity);

                const index_pattern = index - 1;

                std.debug.assert(index_pattern < size);

                if (self.buffer[cursor] != pattern[index_pattern]) {
                    return false;
                }

                index -= 1;
            }

            std.debug.assert(index == 0);
            std.debug.assert(iteration <= capacity);

            return true;
        }

        fn decrement(value: u32) u32 {
            std.debug.assert(value < capacity);

            if (value == 0) {
                return capacity - 1;
            }

            return value - 1;
        }

        fn wrap(value: u32) u32 {
            std.debug.assert(capacity > 0);

            const result = value % capacity;

            std.debug.assert(result < capacity);

            return result;
        }
    };
}
