const std = @import("std");

const assert = std.debug.assert;

pub const capacity_min: u32 = 1;
pub const capacity_max: u32 = 1024;

pub const Error = error{
    EmptyPattern,
    PatternTooLarge,
};

pub fn CircularBufferType(comptime capacity: u32) type {
    if (capacity < capacity_min) {
        @compileError("CircularBufferType capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("CircularBufferType capacity must be 1024 or less");
    }

    return struct {
        const Instance = @This();

        buffer: [capacity]u8 = [_]u8{0} ** capacity,
        head: u32 = 0,
        tail: u32 = 0,
        count: u32 = 0,

        pub fn init() Instance {
            const result = Instance{};

            assert(result.head == 0);
            assert(result.tail == 0);
            assert(result.count == 0);
            assert(result.is_empty());

            return result;
        }

        pub fn is_valid(instance: *const Instance) bool {
            assert(capacity >= capacity_min);
            assert(capacity <= capacity_max);

            const head_valid = instance.head < capacity;
            const tail_valid = instance.tail < capacity;
            const count_valid = instance.count <= capacity;

            return head_valid and tail_valid and count_valid;
        }

        pub fn clear(instance: *Instance) void {
            assert(instance.is_valid());

            instance.head = 0;
            instance.tail = 0;
            instance.count = 0;

            assert(instance.head == 0);
            assert(instance.tail == 0);
            assert(instance.count == 0);
            assert(instance.is_empty());
        }

        pub fn get(instance: *const Instance, index: u32) ?u8 {
            assert(instance.is_valid());

            const length_current = instance.length();

            if (index >= length_current) {
                return null;
            }

            assert(index < length_current);
            assert(index < capacity);

            const position = wrap(instance.head + index);

            assert(position < capacity);

            return instance.buffer[position];
        }

        pub fn is_empty(instance: *const Instance) bool {
            assert(instance.is_valid());

            return instance.count == 0;
        }

        pub fn length(instance: *const Instance) u32 {
            assert(instance.is_valid());
            assert(instance.count <= capacity);

            return instance.count;
        }

        pub fn match(instance: *const Instance, pattern: []const u8) Error!bool {
            assert(instance.is_valid());

            const size: u32 = @intCast(pattern.len);

            if (size == 0) {
                return Error.EmptyPattern;
            }

            if (size > capacity) {
                return Error.PatternTooLarge;
            }

            assert(size > 0);
            assert(size <= capacity);

            const length_current = instance.length();

            if (length_current < size) {
                return false;
            }

            assert(length_current >= size);

            return instance.compare(pattern, size);
        }

        pub fn push(instance: *Instance, value: u8) void {
            assert(instance.is_valid());

            instance.buffer[instance.tail] = value;
            instance.tail = wrap(instance.tail + 1);

            if (instance.count == capacity) {
                instance.head = wrap(instance.head + 1);
            } else {
                instance.count += 1;
            }

            assert(instance.is_valid());
            assert(instance.count <= capacity);
            assert(instance.buffer[wrap(instance.tail + capacity - 1)] == value);
        }

        pub fn pop(instance: *Instance) ?u8 {
            assert(instance.is_valid());

            if (instance.is_empty()) {
                return null;
            }

            instance.tail = decrement(instance.tail);
            instance.count -= 1;

            const result = instance.buffer[instance.tail];

            assert(instance.is_valid());

            return result;
        }

        fn compare(instance: *const Instance, pattern: []const u8, size: u32) bool {
            assert(instance.is_valid());
            assert(size > 0);
            assert(size <= capacity);
            assert(instance.length() >= size);

            var index: u32 = size;
            var cursor: u32 = instance.tail;
            var iteration: u32 = 0;

            while (iteration < capacity) : (iteration += 1) {
                if (index == 0) {
                    break;
                }

                assert(index > 0);
                assert(index <= size);

                cursor = decrement(cursor);

                assert(cursor < capacity);

                const index_pattern = index - 1;

                assert(index_pattern < size);

                if (instance.buffer[cursor] != pattern[index_pattern]) {
                    return false;
                }

                index -= 1;
            }

            assert(index == 0);
            assert(iteration <= capacity);

            return true;
        }

        fn decrement(value: u32) u32 {
            assert(value < capacity);

            if (value == 0) {
                return capacity - 1;
            }

            return value - 1;
        }

        fn wrap(value: u32) u32 {
            assert(capacity > 0);

            const result = value % capacity;

            assert(result < capacity);

            return result;
        }
    };
}

test "a new buffer starts empty" {
    const buffer = CircularBufferType(16).init();

    try std.testing.expect(buffer.is_empty());
    try std.testing.expectEqual(@as(u32, 0), buffer.length());
    try std.testing.expectEqual(@as(u32, 0), buffer.head);
    try std.testing.expectEqual(@as(u32, 0), buffer.tail);
}

test "a new buffer is valid" {
    const buffer = CircularBufferType(16).init();

    try std.testing.expect(buffer.is_valid());
}

test "a pushed value lands in the buffer" {
    var buffer = CircularBufferType(16).init();

    buffer.push('A');

    try std.testing.expect(!buffer.is_empty());
    try std.testing.expectEqual(@as(u32, 1), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "pushed values keep their order" {
    var buffer = CircularBufferType(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    try std.testing.expectEqual(@as(u32, 3), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "clearing empties the buffer" {
    var buffer = CircularBufferType(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    buffer.clear();

    try std.testing.expect(buffer.is_empty());
    try std.testing.expectEqual(@as(u32, 0), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "pushing past capacity wraps around" {
    var buffer = CircularBufferType(4).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');
    buffer.push('D');
    buffer.push('E');

    try std.testing.expectEqual(@as(u32, 4), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "get returns the value at an index" {
    var buffer = CircularBufferType(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    try std.testing.expectEqual(@as(?u8, 'A'), buffer.get(0));
    try std.testing.expectEqual(@as(?u8, 'B'), buffer.get(1));
    try std.testing.expectEqual(@as(?u8, 'C'), buffer.get(2));
}

test "get returns null past the end" {
    var buffer = CircularBufferType(16).init();

    buffer.push('A');
    buffer.push('B');

    try std.testing.expect(buffer.get(2) == null);
    try std.testing.expect(buffer.get(100) == null);
}

test "a single character pattern matches" {
    var buffer = CircularBufferType(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    try std.testing.expect(try buffer.match("C"));
    try std.testing.expect(!try buffer.match("A"));
    try std.testing.expect(!try buffer.match("D"));
}

test "a multi character pattern matches" {
    var buffer = CircularBufferType(16).init();

    buffer.push('H');
    buffer.push('E');
    buffer.push('L');
    buffer.push('L');
    buffer.push('O');

    try std.testing.expect(try buffer.match("LO"));
    try std.testing.expect(try buffer.match("LLO"));
    try std.testing.expect(try buffer.match("ELLO"));
    try std.testing.expect(try buffer.match("HELLO"));
    try std.testing.expect(!try buffer.match("WORLD"));
}

test "an empty pattern is an error" {
    var buffer = CircularBufferType(16).init();

    buffer.push('A');
    buffer.push('B');

    const result = buffer.match("");

    try std.testing.expectError(Error.EmptyPattern, result);
}

test "a pattern larger than the capacity is an error" {
    var buffer = CircularBufferType(4).init();

    buffer.push('A');
    buffer.push('B');

    const result = buffer.match("ABCDE");

    try std.testing.expectError(Error.PatternTooLarge, result);
}

test "an empty buffer matches nothing" {
    const buffer = CircularBufferType(16).init();

    try std.testing.expect(!try buffer.match("A"));
}

test "a pattern still matches after a wrap around" {
    var buffer = CircularBufferType(4).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');
    buffer.push('D');
    buffer.push('E');
    buffer.push('F');

    try std.testing.expect(try buffer.match("F"));
    try std.testing.expect(try buffer.match("EF"));
    try std.testing.expect(try buffer.match("DEF"));
}

test "the length is capped at the capacity" {
    var buffer = CircularBufferType(4).init();

    for (0..10) |_| {
        buffer.push('X');
    }

    try std.testing.expectEqual(@as(u32, 4), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "buffers of different capacities behave alike" {
    var buf1 = CircularBufferType(1).init();
    var buf8 = CircularBufferType(8).init();
    var buf64 = CircularBufferType(64).init();
    var buf1024 = CircularBufferType(1024).init();

    buf1.push('A');
    buf8.push('A');
    buf64.push('A');
    buf1024.push('A');

    try std.testing.expect(buf1.is_valid());
    try std.testing.expect(buf8.is_valid());
    try std.testing.expect(buf64.is_valid());
    try std.testing.expect(buf1024.is_valid());
}

test "a cleared buffer is empty" {
    var buffer = CircularBufferType(16).init();

    buffer.push('A');
    buffer.push('B');

    try std.testing.expect(!buffer.is_empty());

    buffer.clear();

    try std.testing.expect(buffer.is_empty());
}

test "pattern matching is case sensitive" {
    var buffer = CircularBufferType(16).init();

    buffer.push('H');
    buffer.push('i');

    try std.testing.expect(try buffer.match("Hi"));
    try std.testing.expect(!try buffer.match("HI"));
    try std.testing.expect(!try buffer.match("hi"));
}

test "a pattern builds up one push at a time" {
    var buffer = CircularBufferType(32).init();

    const text = "hello world";

    for (text) |c| {
        buffer.push(c);
    }

    try std.testing.expect(try buffer.match("world"));
    try std.testing.expect(try buffer.match("o world"));
    try std.testing.expect(try buffer.match("hello world"));
}

test "constants: valid ranges" {
    try std.testing.expectEqual(@as(u32, 1), capacity_min);
    try std.testing.expectEqual(@as(u32, 1024), capacity_max);
}

test "pushing at capacity drops the oldest value" {
    var buffer = CircularBufferType(4).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');
    buffer.push('D');
    buffer.push('E');

    try std.testing.expectEqual(@as(u32, 4), buffer.length());
    try std.testing.expectEqual(@as(?u8, 'B'), buffer.get(0));
    try std.testing.expectEqual(@as(?u8, 'E'), buffer.get(3));
    try std.testing.expect(buffer.get(4) == null);
}

test "pop removes the newest value" {
    var buffer = CircularBufferType(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    try std.testing.expectEqual(@as(?u8, 'C'), buffer.pop());
    try std.testing.expectEqual(@as(u32, 2), buffer.length());
    try std.testing.expectEqual(@as(?u8, 'A'), buffer.get(0));
    try std.testing.expectEqual(@as(?u8, 'B'), buffer.get(1));
}

test "pop returns null once the buffer is empty" {
    var buffer = CircularBufferType(16).init();

    buffer.push('A');
    buffer.push('B');

    try std.testing.expectEqual(@as(?u8, 'B'), buffer.pop());
    try std.testing.expectEqual(@as(?u8, 'A'), buffer.pop());
    try std.testing.expect(buffer.is_empty());
    try std.testing.expect(buffer.pop() == null);
}
