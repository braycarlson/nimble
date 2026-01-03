const std = @import("std");

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

        pub fn is_valid(self: *const Entry) bool {
            std.debug.assert(@intFromPtr(self) != 0);

            const valid_range = self.value <= self.bound or self.bound == 0;
            const result = valid_range;

            return result;
        }

        pub fn reset(self: *Entry) void {
            std.debug.assert(@intFromPtr(self) != 0);

            self.value = 0;
            self.bound = 0;

            std.debug.assert(self.value == 0);
            std.debug.assert(self.bound == 0);
            std.debug.assert(self.is_valid());
        }
    };

    pub fn init() Gen {
        const result = Gen{};

        std.debug.assert(!result.started);
        std.debug.assert(result.p == 0);
        std.debug.assert(result.p_max == 0);
        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn is_valid(self: *const Gen) bool {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(capacity == 32);

        const valid_p = self.p <= capacity;
        const valid_p_max = self.p_max <= capacity;
        const valid_range = self.p <= self.p_max or !self.started;
        const result = valid_p and valid_p_max and valid_range;

        return result;
    }

    pub fn done(self: *Gen) bool {
        std.debug.assert(self.is_valid());

        if (!self.started) {
            self.started = true;

            std.debug.assert(self.started);

            return false;
        }

        std.debug.assert(self.started);

        const found = self.find_next_state();

        return !found;
    }

    fn find_next_state(self: *Gen) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.started);

        var i: u8 = self.p_max;
        var iteration: u8 = 0;

        while (iteration < capacity) : (iteration += 1) {
            std.debug.assert(iteration < capacity);

            if (i == 0) {
                std.debug.assert(iteration <= capacity);

                return false;
            }

            std.debug.assert(i > 0);

            i -= 1;

            std.debug.assert(i < capacity);
            std.debug.assert(self.v[i].is_valid());

            if (self.v[i].value < self.v[i].bound) {
                self.v[i].value += 1;

                std.debug.assert(self.v[i].value <= self.v[i].bound);

                self.reset_entries_after(i);
                self.p = 0;

                std.debug.assert(self.p == 0);
                std.debug.assert(self.is_valid());

                return true;
            }
        }

        std.debug.assert(iteration == capacity);

        return false;
    }

    fn reset_entries_after(self: *Gen, idx: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(idx < capacity);

        var j: u8 = idx + 1;
        var iteration: u8 = 0;

        while (j < self.p_max and iteration < capacity) : ({
            j += 1;
            iteration += 1;
        }) {
            std.debug.assert(j < self.p_max);
            std.debug.assert(iteration < capacity);

            self.v[j].reset();
        }

        std.debug.assert(iteration <= capacity);
    }

    fn get_or_create_entry(self: *Gen, bound: u32) u32 {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.p < capacity);

        if (self.p < self.p_max) {
            const result = self.v[self.p].value;

            std.debug.assert(result <= self.v[self.p].bound);

            self.p += 1;

            std.debug.assert(self.is_valid());

            return result;
        }

        std.debug.assert(self.p == self.p_max);

        self.v[self.p].bound = bound;
        self.v[self.p].value = 0;

        std.debug.assert(self.v[self.p].is_valid());

        const result = self.v[self.p].value;

        self.p += 1;
        self.p_max = self.p;

        std.debug.assert(self.p == self.p_max);
        std.debug.assert(self.p <= capacity);
        std.debug.assert(self.is_valid());

        return result;
    }

    pub fn range_inclusive(self: *Gen, comptime T: type, min: T, max: T) T {
        std.debug.assert(self.is_valid());
        std.debug.assert(max >= min);

        const range_size: u32 = @intCast(max - min);
        const offset = self.get_or_create_entry(range_size);

        std.debug.assert(offset <= range_size);

        const result: T = min + @as(T, @intCast(offset));

        std.debug.assert(result >= min);
        std.debug.assert(result <= max);
        std.debug.assert(self.is_valid());

        return result;
    }

    pub fn range_exclusive(self: *Gen, comptime T: type, min: T, max: T) T {
        std.debug.assert(self.is_valid());
        std.debug.assert(max > min);

        const result = self.range_inclusive(T, min, max - 1);

        std.debug.assert(result >= min);
        std.debug.assert(result < max);
        std.debug.assert(self.is_valid());

        return result;
    }

    pub fn boolean(self: *Gen) bool {
        std.debug.assert(self.is_valid());

        const value = self.range_inclusive(u8, 0, 1);

        std.debug.assert(value == 0 or value == 1);

        const result = value == 1;

        std.debug.assert(self.is_valid());

        return result;
    }

    pub fn select(self: *Gen, comptime T: type, items: []const T) T {
        std.debug.assert(self.is_valid());
        std.debug.assert(items.len > 0);
        std.debug.assert(items.len <= bound_max);

        const idx = self.range_exclusive(usize, 0, items.len);

        std.debug.assert(idx < items.len);

        const result = items[idx];

        std.debug.assert(self.is_valid());

        return result;
    }

    pub fn subset(self: *Gen, comptime T: type, items: []const T, buffer: []T) []T {
        std.debug.assert(self.is_valid());
        std.debug.assert(buffer.len >= items.len);
        std.debug.assert(items.len <= capacity);

        var count: usize = 0;
        var i: u8 = 0;

        while (i < items.len and i < capacity) : (i += 1) {
            std.debug.assert(i < items.len);
            std.debug.assert(count <= i);

            if (self.boolean()) {
                std.debug.assert(count < buffer.len);

                buffer[count] = items[i];
                count += 1;
            }
        }

        std.debug.assert(i == items.len or i == capacity);
        std.debug.assert(count <= items.len);
        std.debug.assert(self.is_valid());

        const result = buffer[0..count];

        return result;
    }

    pub fn enumerate(self: *Gen, comptime E: type) E {
        std.debug.assert(self.is_valid());

        const fields = @typeInfo(E).@"enum".fields;

        comptime std.debug.assert(fields.len > 0);
        comptime std.debug.assert(fields.len <= bound_max);

        const idx = self.range_exclusive(usize, 0, fields.len);

        std.debug.assert(idx < fields.len);

        const result: E = @enumFromInt(fields[idx].value);

        std.debug.assert(self.is_valid());

        return result;
    }
};

const testing = std.testing;

test "Gen init" {
    const g = Gen.init();

    std.debug.assert(!g.started);
    std.debug.assert(g.p == 0);
    std.debug.assert(g.p_max == 0);

    try testing.expect(!g.started);
    try testing.expectEqual(@as(u8, 0), g.p);
    try testing.expectEqual(@as(u8, 0), g.p_max);
    try testing.expect(g.is_valid());
}

test "Gen is_valid" {
    var g = Gen.init();

    std.debug.assert(g.is_valid());

    try testing.expect(g.is_valid());

    g.p = capacity + 1;

    std.debug.assert(!g.is_valid());

    try testing.expect(!g.is_valid());
}

test "Gen Entry is_valid" {
    var entry = Gen.Entry{};

    std.debug.assert(entry.is_valid());

    try testing.expect(entry.is_valid());

    entry.value = 5;
    entry.bound = 10;

    std.debug.assert(entry.is_valid());

    try testing.expect(entry.is_valid());

    entry.value = 15;

    std.debug.assert(!entry.is_valid());

    try testing.expect(!entry.is_valid());
}

test "Gen done sequence" {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(!g.started);

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        _ = g.range_inclusive(u8, 0, 2);
        iteration += 1;
    }

    std.debug.assert(iteration > 0);
    std.debug.assert(g.started);

    try testing.expectEqual(@as(u32, 3), iteration);
}

test "Gen range_inclusive bounds" {
    var g = Gen.init();
    var values: [8]u8 = undefined;
    var count: u8 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(count < 8);
        std.debug.assert(g.is_valid());

        const value = g.range_inclusive(u8, 5, 10);

        std.debug.assert(value >= 5);
        std.debug.assert(value <= 10);

        values[count] = value;
        count += 1;
    }

    std.debug.assert(count > 0);
    std.debug.assert(count <= 8);

    var i: u8 = 0;

    while (i < count) : (i += 1) {
        std.debug.assert(i < count);

        try testing.expect(values[i] >= 5);
        try testing.expect(values[i] <= 10);
    }

    std.debug.assert(i == count);
}

test "Gen boolean exhaustive" {
    var g = Gen.init();
    var seen_true: bool = false;
    var seen_false: bool = false;
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const value = g.boolean();

        if (value) {
            seen_true = true;
        } else {
            seen_false = true;
        }

        iteration += 1;
    }

    std.debug.assert(iteration == 2);
    std.debug.assert(seen_true);
    std.debug.assert(seen_false);

    try testing.expect(seen_true);
    try testing.expect(seen_false);
    try testing.expectEqual(@as(u32, 2), iteration);
}

test "Gen select" {
    var g = Gen.init();
    const items = [_]u8{ 10, 20, 30 };
    var seen = [_]bool{ false, false, false };
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const value = g.select(u8, &items);

        var i: u8 = 0;

        while (i < items.len) : (i += 1) {
            std.debug.assert(i < items.len);

            if (items[i] == value) {
                seen[i] = true;
            }
        }

        std.debug.assert(i == items.len);

        iteration += 1;
    }

    std.debug.assert(iteration == 3);
    std.debug.assert(seen[0] and seen[1] and seen[2]);

    try testing.expectEqual(@as(u32, 3), iteration);
    try testing.expect(seen[0]);
    try testing.expect(seen[1]);
    try testing.expect(seen[2]);
}

test "Gen subset" {
    var g = Gen.init();
    const items = [_]u8{ 1, 2, 3 };
    var buffer: [3]u8 = undefined;
    var subset_count: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(subset_count < iteration_max);
        std.debug.assert(g.is_valid());

        const subset = g.subset(u8, &items, &buffer);

        std.debug.assert(subset.len <= items.len);

        subset_count += 1;
    }

    std.debug.assert(subset_count == 8);

    try testing.expectEqual(@as(u32, 8), subset_count);
}

test "Gen enumerate" {
    const TestEnum = enum(u8) {
        first = 0,
        second = 1,
        third = 2,
    };

    var g = Gen.init();
    var seen = [_]bool{ false, false, false };
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const value = g.enumerate(TestEnum);

        seen[@intFromEnum(value)] = true;
        iteration += 1;
    }

    std.debug.assert(iteration == 3);
    std.debug.assert(seen[0] and seen[1] and seen[2]);

    try testing.expectEqual(@as(u32, 3), iteration);
    try testing.expect(seen[0]);
    try testing.expect(seen[1]);
    try testing.expect(seen[2]);
}

test "Gen multiple choices" {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const a = g.range_inclusive(u8, 0, 1);
        const b = g.range_inclusive(u8, 0, 1);

        std.debug.assert(a <= 1);
        std.debug.assert(b <= 1);

        iteration += 1;
    }

    std.debug.assert(iteration == 4);

    try testing.expectEqual(@as(u32, 4), iteration);
}
