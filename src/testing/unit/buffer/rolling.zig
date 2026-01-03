const std = @import("std");
const input = @import("input");

const rolling = input.buffer.rolling;

const RollingBuffer = rolling.RollingBuffer;

test "RollingBuffer: init creates empty buffer" {
    const buffer = RollingBuffer(16).init();

    try std.testing.expect(buffer.is_empty());
    try std.testing.expectEqual(@as(u32, 0), buffer.length());
    try std.testing.expectEqual(@as(u32, 0), buffer.len);
}

test "RollingBuffer: is_valid for new buffer" {
    const buffer = RollingBuffer(16).init();

    try std.testing.expect(buffer.is_valid());
}

test "RollingBuffer: push single value" {
    var buffer = RollingBuffer(16).init();

    buffer.push('A');

    try std.testing.expect(!buffer.is_empty());
    try std.testing.expectEqual(@as(u32, 1), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "RollingBuffer: push multiple values" {
    var buffer = RollingBuffer(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    try std.testing.expectEqual(@as(u32, 3), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "RollingBuffer: clear resets buffer" {
    var buffer = RollingBuffer(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    buffer.clear();

    try std.testing.expect(buffer.is_empty());
    try std.testing.expectEqual(@as(u32, 0), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "RollingBuffer: push rolls off oldest at capacity" {
    var buffer = RollingBuffer(4).init();

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

test "RollingBuffer: get returns correct values" {
    var buffer = RollingBuffer(16).init();

    buffer.push('A');
    buffer.push('B');
    buffer.push('C');

    try std.testing.expectEqual(@as(?u8, 'A'), buffer.get(0));
    try std.testing.expectEqual(@as(?u8, 'B'), buffer.get(1));
    try std.testing.expectEqual(@as(?u8, 'C'), buffer.get(2));
}

test "RollingBuffer: get returns null for out of bounds" {
    var buffer = RollingBuffer(16).init();

    buffer.push('A');
    buffer.push('B');

    try std.testing.expect(buffer.get(2) == null);
    try std.testing.expect(buffer.get(100) == null);
}

test "RollingBuffer: get returns null on empty buffer" {
    const buffer = RollingBuffer(16).init();

    try std.testing.expect(buffer.get(0) == null);
}

test "RollingBuffer: pop removes and returns last value" {
    var buffer = RollingBuffer(16).init();

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

test "RollingBuffer: pop returns null on empty buffer" {
    var buffer = RollingBuffer(16).init();

    try std.testing.expect(buffer.pop() == null);
}

test "RollingBuffer: slice returns full buffer content" {
    var buffer = RollingBuffer(16).init();

    buffer.push('H');
    buffer.push('E');
    buffer.push('L');
    buffer.push('L');
    buffer.push('O');

    const s = buffer.slice();

    try std.testing.expectEqualStrings("HELLO", s);
}

test "RollingBuffer: slice returns empty for empty buffer" {
    const buffer = RollingBuffer(16).init();

    const s = buffer.slice();

    try std.testing.expectEqual(@as(usize, 0), s.len);
}

test "RollingBuffer: slice_from returns partial buffer" {
    var buffer = RollingBuffer(16).init();

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

test "RollingBuffer: slice_range returns specified range" {
    var buffer = RollingBuffer(16).init();

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

test "RollingBuffer: length is capped at capacity" {
    var buffer = RollingBuffer(4).init();

    for (0..10) |_| {
        buffer.push('X');
    }

    try std.testing.expectEqual(@as(u32, 4), buffer.length());
    try std.testing.expect(buffer.is_valid());
}

test "RollingBuffer: different capacities" {
    var buf1 = RollingBuffer(1).init();
    var buf8 = RollingBuffer(8).init();
    var buf64 = RollingBuffer(64).init();
    var buf1024 = RollingBuffer(1024).init();

    buf1.push('A');
    buf8.push('A');
    buf64.push('A');
    buf1024.push('A');

    try std.testing.expect(buf1.is_valid());
    try std.testing.expect(buf8.is_valid());
    try std.testing.expect(buf64.is_valid());
    try std.testing.expect(buf1024.is_valid());
}

test "RollingBuffer: rolling behavior preserves order" {
    var buffer = RollingBuffer(4).init();

    buffer.push('1');
    buffer.push('2');
    buffer.push('3');
    buffer.push('4');
    buffer.push('5');
    buffer.push('6');

    try std.testing.expectEqualStrings("3456", buffer.slice());
}

test "RollingBuffer: push and pop interleaved" {
    var buffer = RollingBuffer(8).init();

    buffer.push('A');
    buffer.push('B');
    _ = buffer.pop();
    buffer.push('C');
    buffer.push('D');
    _ = buffer.pop();

    try std.testing.expectEqualStrings("AC", buffer.slice());
}

test "RollingBuffer: is_empty reflects correct state" {
    var buffer = RollingBuffer(4).init();

    try std.testing.expect(buffer.is_empty());

    buffer.push('A');
    try std.testing.expect(!buffer.is_empty());

    _ = buffer.pop();
    try std.testing.expect(buffer.is_empty());
}

test "constants: valid ranges" {
    try std.testing.expectEqual(@as(u32, 1), rolling.capacity_min);
    try std.testing.expectEqual(@as(u32, 1024), rolling.capacity_max);
}
