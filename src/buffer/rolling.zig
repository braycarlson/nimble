const std = @import("std");

const assert = std.debug.assert;

pub const capacity_min: u32 = 1;
pub const capacity_max: u32 = 1024;

pub fn RollingBufferType(comptime capacity: u32) type {
    if (capacity < capacity_min) {
        @compileError("RollingBufferType capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("RollingBufferType capacity must be 1024 or less");
    }

    return struct {
        const Instance = @This();

        buffer: [capacity]u8 = [_]u8{0} ** capacity,
        len: u32 = 0,

        pub fn init() Instance {
            const result = Instance{};

            assert(result.len == 0);
            assert(result.is_empty());

            return result;
        }

        pub fn is_valid(instance: *const Instance) bool {
            assert(capacity >= capacity_min);
            assert(capacity <= capacity_max);

            return instance.len <= capacity;
        }

        pub fn clear(instance: *Instance) void {
            assert(instance.is_valid());

            instance.len = 0;

            assert(instance.len == 0);
            assert(instance.is_empty());
        }

        pub fn get(instance: *const Instance, index: u32) ?u8 {
            assert(instance.is_valid());

            if (index >= instance.len) {
                return null;
            }

            assert(index < instance.len);
            assert(index < capacity);

            return instance.buffer[index];
        }

        pub fn is_empty(instance: *const Instance) bool {
            assert(instance.is_valid());

            return instance.len == 0;
        }

        pub fn length(instance: *const Instance) u32 {
            assert(instance.is_valid());

            return instance.len;
        }

        pub fn slice(instance: *const Instance) []const u8 {
            assert(instance.is_valid());

            return instance.buffer[0..instance.len];
        }

        pub fn slice_from(instance: *const Instance, start: u32) []const u8 {
            assert(instance.is_valid());
            assert(start <= instance.len);

            return instance.buffer[start..instance.len];
        }

        pub fn slice_range(instance: *const Instance, start: u32, end: u32) []const u8 {
            assert(instance.is_valid());
            assert(start <= end);
            assert(end <= instance.len);

            return instance.buffer[start..end];
        }

        pub fn push(instance: *Instance, value: u8) void {
            assert(instance.is_valid());

            if (instance.len >= capacity) {
                for (0..capacity - 1) |j| {
                    instance.buffer[j] = instance.buffer[j + 1];
                }

                instance.len = capacity - 1;
            }

            instance.buffer[instance.len] = value;
            instance.len += 1;

            assert(instance.is_valid());
            assert(instance.len >= 1);
            assert(instance.buffer[instance.len - 1] == value);
        }

        pub fn pop(instance: *Instance) ?u8 {
            assert(instance.is_valid());

            if (instance.len == 0) {
                return null;
            }

            instance.len -= 1;

            const result = instance.buffer[instance.len];

            assert(instance.is_valid());

            return result;
        }
    };
}

test "a new buffer starts empty" {
    const buffer = RollingBufferType(16).init();

    try std.testing.expect(buffer.is_empty());
    try std.testing.expectEqual(@as(u32, 0), buffer.length());
    try std.testing.expectEqual(@as(u32, 0), buffer.len);
}

test "a new buffer is valid" {
    const buffer = RollingBufferType(16).init();

    try std.testing.expect(buffer.is_valid());
}

test "a pushed value lands in the buffer" {
    var buffer = RollingBufferType(16).init();

    buffer.push('A');

    try std.testing.expect(!buffer.is_empty());
    try std.testing.expectEqual(@as(u32, 1), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "pushed values keep their order" {
    var buffer = RollingBufferType(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    try std.testing.expectEqual(@as(u32, 3), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "clearing empties the buffer" {
    var buffer = RollingBufferType(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    buffer.clear();

    try std.testing.expect(buffer.is_empty());
    try std.testing.expectEqual(@as(u32, 0), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "pushing at capacity rolls off the oldest value" {
    var buffer = RollingBufferType(4).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');
    buffer.push('D');
    buffer.push('E');

    try std.testing.expectEqual(@as(u32, 4), buffer.length());
    try std.testing.expect(buffer.is_valid());

    try std.testing.expectEqual(@as(?u8, 'B'), buffer.get(0));
    try std.testing.expectEqual(@as(?u8, 'E'), buffer.get(3));
}

test "get returns the value at an index" {
    var buffer = RollingBufferType(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    try std.testing.expectEqual(@as(?u8, 'A'), buffer.get(0));
    try std.testing.expectEqual(@as(?u8, 'B'), buffer.get(1));
    try std.testing.expectEqual(@as(?u8, 'C'), buffer.get(2));
}

test "get returns null past the end" {
    var buffer = RollingBufferType(16).init();

    buffer.push('A');
    buffer.push('B');

    try std.testing.expect(buffer.get(2) == null);
    try std.testing.expect(buffer.get(100) == null);
}

test "get returns null on an empty buffer" {
    const buffer = RollingBufferType(16).init();

    try std.testing.expect(buffer.get(0) == null);
}

test "pop removes and returns the last value" {
    var buffer = RollingBufferType(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    try std.testing.expectEqual(@as(?u8, 'C'), buffer.pop());
    try std.testing.expectEqual(@as(u32, 2), buffer.length());

    try std.testing.expectEqual(@as(?u8, 'B'), buffer.pop());
    try std.testing.expectEqual(@as(u32, 1), buffer.length());

    try std.testing.expectEqual(@as(?u8, 'A'), buffer.pop());
    try std.testing.expect(buffer.is_empty());
}

test "pop returns null on an empty buffer" {
    var buffer = RollingBufferType(16).init();

    try std.testing.expect(buffer.pop() == null);
}

test "a slice covers the whole buffer" {
    var buffer = RollingBufferType(16).init();

    buffer.push('H');
    buffer.push('E');
    buffer.push('L');
    buffer.push('L');
    buffer.push('O');

    const s = buffer.slice();

    try std.testing.expectEqualStrings("HELLO", s);
}

test "a slice of an empty buffer is empty" {
    const buffer = RollingBufferType(16).init();

    const s = buffer.slice();

    try std.testing.expectEqual(@as(usize, 0), s.len);
}

test "slice_from starts at the index it is given" {
    var buffer = RollingBufferType(16).init();

    buffer.push('H');
    buffer.push('E');
    buffer.push('L');
    buffer.push('L');
    buffer.push('O');

    try std.testing.expectEqualStrings("HELLO", buffer.slice_from(0));
    try std.testing.expectEqualStrings("ELLO", buffer.slice_from(1));
    try std.testing.expectEqualStrings("LLO", buffer.slice_from(2));
    try std.testing.expectEqualStrings("LO", buffer.slice_from(3));
    try std.testing.expectEqualStrings("O", buffer.slice_from(4));
    try std.testing.expectEqualStrings("", buffer.slice_from(5));
}

test "slice_range covers only the range it is given" {
    var buffer = RollingBufferType(16).init();

    buffer.push('H');
    buffer.push('E');
    buffer.push('L');
    buffer.push('L');
    buffer.push('O');

    try std.testing.expectEqualStrings("HE", buffer.slice_range(0, 2));
    try std.testing.expectEqualStrings("ELL", buffer.slice_range(1, 4));
    try std.testing.expectEqualStrings("LO", buffer.slice_range(3, 5));
    try std.testing.expectEqualStrings("", buffer.slice_range(2, 2));
}

test "the length is capped at the capacity" {
    var buffer = RollingBufferType(4).init();

    for (0..10) |_| {
        buffer.push('X');
    }

    try std.testing.expectEqual(@as(u32, 4), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "buffers of different capacities behave alike" {
    var buf1 = RollingBufferType(1).init();
    var buf8 = RollingBufferType(8).init();
    var buf64 = RollingBufferType(64).init();
    var buf1024 = RollingBufferType(1024).init();

    buf1.push('A');
    buf8.push('A');
    buf64.push('A');
    buf1024.push('A');

    try std.testing.expect(buf1.is_valid());
    try std.testing.expect(buf8.is_valid());
    try std.testing.expect(buf64.is_valid());
    try std.testing.expect(buf1024.is_valid());
}

test "rolling off the oldest value preserves the order" {
    var buffer = RollingBufferType(4).init();

    buffer.push('1');
    buffer.push('2');
    buffer.push('3');
    buffer.push('4');
    buffer.push('5');
    buffer.push('6');

    try std.testing.expectEqualStrings("3456", buffer.slice());
}

test "interleaved pushes and pops stay consistent" {
    var buffer = RollingBufferType(8).init();

    buffer.push('A');
    buffer.push('B');
    _ = buffer.pop();
    buffer.push('C');
    buffer.push('D');
    _ = buffer.pop();

    try std.testing.expectEqualStrings("AC", buffer.slice());
}

test "is_empty follows whether the buffer holds values" {
    var buffer = RollingBufferType(4).init();

    try std.testing.expect(buffer.is_empty());

    buffer.push('A');
    try std.testing.expect(!buffer.is_empty());

    _ = buffer.pop();
    try std.testing.expect(buffer.is_empty());
}

test "constants: valid ranges" {
    try std.testing.expectEqual(@as(u32, 1), capacity_min);
    try std.testing.expectEqual(@as(u32, 1024), capacity_max);
}
