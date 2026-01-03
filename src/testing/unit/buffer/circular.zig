const std = @import("std");
const input = @import("input");

const circular = input.buffer.circular;

const CircularBuffer = circular.CircularBuffer;

test "CircularBuffer: init creates empty buffer" {
    const buffer = CircularBuffer(16).init();

    try std.testing.expect(buffer.is_empty());
    try std.testing.expectEqual(@as(u32, 0), buffer.length());
    try std.testing.expectEqual(@as(u32, 0), buffer.head);
    try std.testing.expectEqual(@as(u32, 0), buffer.tail);
}

test "CircularBuffer: is_valid for new buffer" {
    const buffer = CircularBuffer(16).init();

    try std.testing.expect(buffer.is_valid());
}

test "CircularBuffer: push single value" {
    var buffer = CircularBuffer(16).init();

    buffer.push('A');

    try std.testing.expect(!buffer.is_empty());
    try std.testing.expectEqual(@as(u32, 1), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "CircularBuffer: push multiple values" {
    var buffer = CircularBuffer(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    try std.testing.expectEqual(@as(u32, 3), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "CircularBuffer: clear resets buffer" {
    var buffer = CircularBuffer(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    buffer.clear();

    try std.testing.expect(buffer.is_empty());
    try std.testing.expectEqual(@as(u32, 0), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "CircularBuffer: push wraps around at capacity" {
    var buffer = CircularBuffer(4).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');
    buffer.push('D');
    buffer.push('E');

    try std.testing.expectEqual(@as(u32, 3), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "CircularBuffer: get returns correct value" {
    var buffer = CircularBuffer(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    try std.testing.expectEqual(@as(?u8, 'A'), buffer.get(0));
    try std.testing.expectEqual(@as(?u8, 'B'), buffer.get(1));
    try std.testing.expectEqual(@as(?u8, 'C'), buffer.get(2));
}

test "CircularBuffer: get returns null for out of bounds" {
    var buffer = CircularBuffer(16).init();

    buffer.push('A');
    buffer.push('B');

    try std.testing.expect(buffer.get(2) == null);
    try std.testing.expect(buffer.get(100) == null);
}

test "CircularBuffer: match single char pattern" {
    var buffer = CircularBuffer(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    try std.testing.expect(try buffer.match("C"));
    try std.testing.expect(!try buffer.match("A"));
    try std.testing.expect(!try buffer.match("D"));
}

test "CircularBuffer: match multi-char pattern" {
    var buffer = CircularBuffer(16).init();

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

test "CircularBuffer: match empty pattern returns error" {
    var buffer = CircularBuffer(16).init();

    buffer.push('A');
    buffer.push('B');

    const result = buffer.match("");

    try std.testing.expectError(circular.Error.EmptyPattern, result);
}

test "CircularBuffer: match pattern larger than capacity returns error" {
    var buffer = CircularBuffer(4).init();

    buffer.push('A');
    buffer.push('B');

    const result = buffer.match("ABCDE");

    try std.testing.expectError(circular.Error.PatternTooLarge, result);
}

test "CircularBuffer: match on empty buffer returns false" {
    const buffer = CircularBuffer(16).init();

    try std.testing.expect(!try buffer.match("A"));
}

test "CircularBuffer: match after wrap around" {
    var buffer = CircularBuffer(4).init();

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

test "CircularBuffer: length is capped at capacity" {
    var buffer = CircularBuffer(4).init();

    for (0..10) |_| {
        buffer.push('X');
    }

    try std.testing.expectEqual(@as(u32, 3), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "CircularBuffer: different capacities" {
    var buf1 = CircularBuffer(1).init();
    var buf8 = CircularBuffer(8).init();
    var buf64 = CircularBuffer(64).init();
    var buf1024 = CircularBuffer(1024).init();

    buf1.push('A');
    buf8.push('A');
    buf64.push('A');
    buf1024.push('A');

    try std.testing.expect(buf1.is_valid());
    try std.testing.expect(buf8.is_valid());
    try std.testing.expect(buf64.is_valid());
    try std.testing.expect(buf1024.is_valid());
}

test "CircularBuffer: is_empty after clear" {
    var buffer = CircularBuffer(16).init();

    buffer.push('A');
    buffer.push('B');

    try std.testing.expect(!buffer.is_empty());

    buffer.clear();

    try std.testing.expect(buffer.is_empty());
}

test "CircularBuffer: pattern matching is case sensitive" {
    var buffer = CircularBuffer(16).init();

    buffer.push('H');
    buffer.push('i');

    try std.testing.expect(try buffer.match("Hi"));
    try std.testing.expect(!try buffer.match("HI"));
    try std.testing.expect(!try buffer.match("hi"));
}

test "CircularBuffer: sequential pattern building" {
    var buffer = CircularBuffer(32).init();

    const text = "hello world";
    for (text) |c| {
        buffer.push(c);
    }

    try std.testing.expect(try buffer.match("world"));
    try std.testing.expect(try buffer.match("o world"));
    try std.testing.expect(try buffer.match("hello world"));
}

test "constants: valid ranges" {
    try std.testing.expectEqual(@as(u32, 1), circular.capacity_min);
    try std.testing.expectEqual(@as(u32, 1024), circular.capacity_max);
}
