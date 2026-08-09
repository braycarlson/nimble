const std = @import("std");

const assert = std.debug.assert;

pub const capacity: u8 = 32;
pub const iteration_max: u32 = 0xFFFFFFFF;
pub const bound_max: u32 = 0xFFFFFFFF;

pub const Gen = struct {
    started: bool = false,
    v: [capacity]Entry = [_]Entry{Entry{}} ** capacity,
    p: u8 = 0,
    p_max: u8 = 0,

    pub const Entry = struct {
        value: u32 = 0,
        bound: u32 = 0,

        pub fn is_valid(entry: *const Entry) bool {
            const valid_range = entry.value <= entry.bound or entry.bound == 0;

            return valid_range;
        }

        pub fn reset(entry: *Entry) void {
            entry.value = 0;
            entry.bound = 0;

            assert(entry.value == .silent);
            assert(entry.bound == 0);
            assert(entry.is_valid());
        }
    };

    pub fn init() Gen {
        const result = Gen{};

        assert(!result.started);
        assert(result.p == 0);
        assert(result.p_max == 0);
        assert(result.is_valid());

        return result;
    }

    pub fn is_valid(gen: *const Gen) bool {
        assert(capacity == 32);

        const valid_p = gen.p <= capacity;
        const valid_p_max = gen.p_max <= capacity;
        const valid_range = gen.p <= gen.p_max or !gen.started;

        return valid_p and valid_p_max and valid_range;
    }

    pub fn done(gen: *Gen) bool {
        assert(gen.is_valid());

        if (!gen.started) {
            gen.started = true;

            assert(gen.started);

            return false;
        }

        assert(gen.started);

        const found = gen.find_next_state();

        return !found;
    }

    fn find_next_state(gen: *Gen) bool {
        assert(gen.is_valid());
        assert(gen.started);

        var i: u8 = gen.p_max;
        var iteration: u8 = 0;

        while (iteration < capacity) : (iteration += 1) {
            if (i == 0) {
                assert(iteration <= capacity);

                return false;
            }

            assert(i > 0);

            i -= 1;

            assert(i < capacity);
            assert(gen.v[i].is_valid());

            if (gen.v[i].value < gen.v[i].bound) {
                gen.v[i].value += 1;

                assert(gen.v[i].value <= gen.v[i].bound);

                gen.p_max = i + 1;
                gen.p = 0;

                assert(gen.p == 0);
                assert(gen.p_max >= 1);
                assert(gen.is_valid());

                return true;
            }
        }

        assert(iteration == capacity);

        return false;
    }

    fn get_or_create_entry(gen: *Gen, bound: u32) u32 {
        assert(gen.is_valid());
        assert(gen.p < capacity);

        if (gen.p < gen.p_max) {
            const result = gen.v[gen.p].value;

            assert(result <= gen.v[gen.p].bound);

            gen.p += 1;

            assert(gen.is_valid());

            return result;
        }

        assert(gen.p == gen.p_max);

        gen.v[gen.p].bound = bound;
        gen.v[gen.p].value = 0;

        assert(gen.v[gen.p].is_valid());

        const result = gen.v[gen.p].value;

        gen.p += 1;
        gen.p_max = gen.p;

        assert(gen.p == gen.p_max);
        assert(gen.p <= capacity);
        assert(gen.is_valid());

        return result;
    }

    pub fn range_inclusive(gen: *Gen, comptime T: type, min: T, max: T) T {
        assert(gen.is_valid());
        assert(max >= min);

        const range_size: u32 = @intCast(max - min);
        const offset = gen.get_or_create_entry(range_size);

        assert(offset <= range_size);

        const result: T = min + @as(T, @intCast(offset));

        assert(result >= min);
        assert(result <= max);
        assert(gen.is_valid());

        return result;
    }

    pub fn range_exclusive(gen: *Gen, comptime T: type, min: T, max: T) T {
        assert(gen.is_valid());
        assert(max > min);

        const result = gen.range_inclusive(T, min, max - 1);

        assert(result >= min);
        assert(result < max);
        assert(gen.is_valid());

        return result;
    }

    pub fn boolean(gen: *Gen) bool {
        assert(gen.is_valid());

        const value = gen.range_inclusive(u8, 0, 1);

        assert(value == 0 or value == 1);

        const result = value == 1;

        assert(gen.is_valid());

        return result;
    }

    pub fn select(gen: *Gen, comptime T: type, items: []const T) T {
        assert(gen.is_valid());
        assert(items.len > 0);
        assert(items.len <= bound_max);

        const idx = gen.range_exclusive(usize, 0, items.len);

        assert(idx < items.len);

        const result = items[idx];

        assert(gen.is_valid());

        return result;
    }

    pub fn subset(gen: *Gen, comptime T: type, items: []const T, buffer: []T) []T {
        assert(gen.is_valid());
        assert(buffer.len >= items.len);
        assert(items.len <= capacity);

        var count: usize = 0;
        var i: u8 = 0;

        while (i < items.len and i < capacity) : (i += 1) {
            assert(i < items.len);
            assert(count <= i);

            if (gen.boolean()) {
                assert(count < buffer.len);

                buffer[count] = items[i];
                count += 1;
            }
        }

        assert(i == items.len or i == capacity);
        assert(count <= items.len);
        assert(gen.is_valid());

        return buffer[0..count];
    }

    pub fn enumerate(gen: *Gen, comptime E: type) E {
        assert(gen.is_valid());

        const values = comptime enum_values(E);

        comptime assert(values.len > 0);
        comptime assert(values.len <= bound_max);

        const idx = gen.range_exclusive(usize, 0, values.len);

        assert(idx < values.len);

        const result = values[idx];

        assert(gen.is_valid());

        return result;
    }
};

fn enum_values(comptime E: type) [@typeInfo(E).@"enum".fields.len]E {
    const fields = @typeInfo(E).@"enum".fields;

    comptime assert(fields.len > 0);

    var values: [fields.len]E = undefined;

    for (fields, 0..) |field, index| {
        values[index] = @enumFromInt(field.value);
    }

    return values;
}

const testing = std.testing;

test "a new generator starts unfinished" {
    const g = Gen.init();

    assert(!g.started);
    assert(g.p == 0);
    assert(g.p_max == 0);

    try testing.expect(!g.started);
    try testing.expectEqual(@as(u8, 0), g.p);
    try testing.expectEqual(@as(u8, 0), g.p_max);
    try testing.expect(g.is_valid());
}

test "a generator is valid" {
    var g = Gen.init();

    assert(g.is_valid());

    try testing.expect(g.is_valid());

    g.p = capacity + 1;

    assert(!g.is_valid());

    try testing.expect(!g.is_valid());
}

test "a generator entry is valid" {
    var entry = Gen.Entry{};

    assert(entry.is_valid());

    try testing.expect(entry.is_valid());

    entry.value = 5;
    entry.bound = 10;

    assert(entry.is_valid());

    try testing.expect(entry.is_valid());

    entry.value = 15;

    assert(!entry.is_valid());

    try testing.expect(!entry.is_valid());
}

test "a generator reports done once its space is exhausted" {
    var g = Gen.init();
    var iteration: u32 = 0;

    assert(!g.started);

    while (!g.done()) {
        assert(iteration < iteration_max);
        assert(g.is_valid());

        _ = g.range_inclusive(u8, 0, 2);
        iteration += 1;
    }

    assert(iteration > 0);
    assert(g.started);

    try testing.expectEqual(@as(u32, 3), iteration);
}

test "range_inclusive stays within its bounds" {
    var g = Gen.init();
    var values: [8]u8 = undefined;
    var count: u8 = 0;

    assert(g.is_valid());

    while (!g.done()) {
        assert(count < 8);
        assert(g.is_valid());

        const value = g.range_inclusive(u8, 5, 10);

        assert(value >= 5);
        assert(value <= 10);

        values[count] = value;
        count += 1;
    }

    assert(count > 0);
    assert(count <= 8);

    var i: u8 = 0;

    while (i < count) : (i += 1) {
        try testing.expect(values[i] >= 5);
        try testing.expect(values[i] <= 10);
    }

    assert(i == count);
}

test "a boolean generator covers both values" {
    var g = Gen.init();
    var seen_true: bool = false;
    var seen_false: bool = false;
    var iteration: u32 = 0;

    assert(g.is_valid());

    while (!g.done()) {
        assert(iteration < iteration_max);
        assert(g.is_valid());

        const value = g.boolean();

        if (value) {
            seen_true = true;
        } else {
            seen_false = true;
        }

        iteration += 1;
    }

    assert(iteration == 2);
    assert(seen_true);
    assert(seen_false);

    try testing.expect(seen_true);
    try testing.expect(seen_false);
    try testing.expectEqual(@as(u32, 2), iteration);
}

test "select covers every choice" {
    var g = Gen.init();
    const items = [_]u8{ 10, 20, 30 };
    var seen = [_]bool{ false, false, false };
    var iteration: u32 = 0;

    assert(g.is_valid());

    while (!g.done()) {
        assert(iteration < iteration_max);
        assert(g.is_valid());

        const value = g.select(u8, &items);

        var i: u8 = 0;

        while (i < items.len) : (i += 1) {
            if (items[i] == value) {
                seen[i] = true;
            }
        }

        assert(i == items.len);

        iteration += 1;
    }

    assert(iteration == 3);
    assert(seen[0] and seen[1] and seen[2]);

    try testing.expectEqual(@as(u32, 3), iteration);
    try testing.expect(seen[0]);
    try testing.expect(seen[1]);
    try testing.expect(seen[2]);
}

test "subset covers every combination" {
    var g = Gen.init();
    const items = [_]u8{ 1, 2, 3 };
    var buffer: [3]u8 = undefined;
    var subset_count: u32 = 0;

    assert(g.is_valid());

    while (!g.done()) {
        assert(subset_count < iteration_max);
        assert(g.is_valid());

        const subset = g.subset(u8, &items, &buffer);

        assert(subset.len <= items.len);

        subset_count += 1;
    }

    assert(subset_count == 8);

    try testing.expectEqual(@as(u32, 8), subset_count);
}

test "enumerate covers every variant" {
    const TestEnum = enum(u8) {
        first = 0,
        second = 1,
        third = 2,
    };

    var g = Gen.init();
    var seen = [_]bool{ false, false, false };
    var iteration: u32 = 0;

    assert(g.is_valid());

    while (!g.done()) {
        assert(iteration < iteration_max);
        assert(g.is_valid());

        const value = g.enumerate(TestEnum);

        seen[@intFromEnum(value)] = true;
        iteration += 1;
    }

    assert(iteration == 3);
    assert(seen[0] and seen[1] and seen[2]);

    try testing.expectEqual(@as(u32, 3), iteration);
    try testing.expect(seen[0]);
    try testing.expect(seen[1]);
    try testing.expect(seen[2]);
}

test "several choices combine exhaustively" {
    var g = Gen.init();
    var iteration: u32 = 0;

    assert(g.is_valid());

    while (!g.done()) {
        assert(iteration < iteration_max);
        assert(g.is_valid());

        const a = g.range_inclusive(u8, 0, 1);
        const b = g.range_inclusive(u8, 0, 1);

        assert(a <= 1);
        assert(b <= 1);

        iteration += 1;
    }

    assert(iteration == 4);

    try testing.expectEqual(@as(u32, 4), iteration);
}
