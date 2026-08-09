const std = @import("std");

const circular = @import("circular.zig");
const fuzz = @import("../testing/fuzz.zig");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Operation = enum {
    push,
    push_alphabet,
    pop,
    clear,
    match_suffix,
    match_random,
    match_empty,
    match_oversized,
};

const Match = union(enum) {
    value: bool,
    failure: circular.Error,
};

const capacities = [_]u32{ 1, 2, 3, 4, 7, 8, 16, 64 };
const alphabet = [_]u8{ 'A', 'B', 'C', 'D' };
const pattern_empty: []const u8 = &[_]u8{};

comptime {
    assert(capacities.len > 0);
    assert(alphabet.len > 1);
    assert(capacities[capacities.len - 1] <= circular.capacity_max);
}

pub fn main(gpa: Allocator, args: fuzz.FuzzArgs) !void {
    _ = gpa;

    assert(args.events_max >= 1);

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();
    const events_per_capacity: u32 = @max(1, args.events_max / @as(u32, capacities.len));

    assert(events_per_capacity >= 1);

    inline for (capacities) |capacity| {
        fuzz_capacity(random, capacity, events_per_capacity);
    }
}

fn fuzz_capacity(random: std.Random, comptime capacity: u32, events_max: u32) void {
    assert(events_max >= 1);

    const Buffer = circular.CircularBufferType(capacity);
    const Reference = ModelType(capacity);

    const weights = fuzz.random_enum_weights(random, Operation);

    var buffer = Buffer.init();
    var model = Reference.init();

    verify(capacity, &buffer, &model);

    var event: u32 = 0;

    while (event < events_max) : (event += 1) {
        const operation = fuzz.random_enum_weighted(random, Operation, weights);

        apply(capacity, random, &buffer, &model, operation);
        verify(capacity, &buffer, &model);
    }

    assert(event == events_max);
}

fn apply(
    comptime capacity: u32,
    random: std.Random,
    buffer: *circular.CircularBufferType(capacity),
    model: *ModelType(capacity),
    operation: Operation,
) void {
    assert(buffer.is_valid());

    switch (operation) {
        .push => {
            const value = random.int(u8);

            buffer.push(value);
            model.push(value);
        },
        .push_alphabet => {
            const value = fuzz.random_from_slice(random, u8, &alphabet);

            buffer.push(value);
            model.push(value);
        },
        .pop => {
            const actual = buffer.pop();
            const expected = model.pop();

            assert(std.meta.eql(actual, expected));
        },
        .clear => {
            buffer.clear();
            model.clear();

            assert(buffer.is_empty());
            assert(model.length() == 0);
        },
        .match_suffix => {
            var pattern: [capacity]u8 = undefined;
            const length = model.suffix(&pattern, random);

            if (length == 0) return;

            check_match(capacity, buffer, model, pattern[0..length]);
        },
        .match_random => {
            var pattern: [capacity]u8 = undefined;
            const length = random.intRangeAtMost(u32, 1, capacity);

            fill_random(random, pattern[0..length]);
            check_match(capacity, buffer, model, pattern[0..length]);
        },
        .match_empty => check_match(capacity, buffer, model, pattern_empty),
        .match_oversized => {
            var pattern: [capacity + 1]u8 = undefined;

            fill_random(random, &pattern);
            check_match(capacity, buffer, model, &pattern);
        },
    }
}

fn check_match(
    comptime capacity: u32,
    buffer: *const circular.CircularBufferType(capacity),
    model: *const ModelType(capacity),
    pattern: []const u8,
) void {
    assert(buffer.is_valid());

    const expected = to_match(model.match(pattern));
    const actual = to_match(buffer.match(pattern));

    assert(std.meta.activeTag(expected) == std.meta.activeTag(actual));

    switch (expected) {
        .value => |value| assert(actual.value == value),
        .failure => |failure| assert(actual.failure == failure),
    }
}

fn verify(
    comptime capacity: u32,
    buffer: *const circular.CircularBufferType(capacity),
    model: *const ModelType(capacity),
) void {
    assert(buffer.is_valid());
    assert(buffer.length() == model.length());
    assert(buffer.is_empty() == (model.length() == 0));

    var index: u32 = 0;

    while (index <= capacity) : (index += 1) {
        assert(index <= capacity);
        assert(std.meta.eql(buffer.get(index), model.get(index)));
    }

    assert(index == capacity + 1);
}

fn fill_random(random: std.Random, target: []u8) void {
    assert(target.len > 0);

    var index: u32 = 0;

    while (index < target.len) : (index += 1) {
        assert(index < target.len);

        target[index] = fuzz.random_from_slice(random, u8, &alphabet);
    }

    assert(index == target.len);
}

fn to_match(result: circular.Error!bool) Match {
    const value = result catch |err| return Match{ .failure = err };

    return Match{ .value = value };
}

fn ModelType(comptime capacity: u32) type {
    assert(capacity >= circular.capacity_min);
    assert(capacity <= circular.capacity_max);

    return struct {
        const Instance = @This();

        items: [capacity]u8 = [_]u8{0} ** capacity,
        len: u32 = 0,

        pub fn init() Instance {
            const result = Instance{};

            assert(result.len == 0);

            return result;
        }

        pub fn push(instance: *Instance, value: u8) void {
            assert(instance.len <= capacity);

            if (instance.len == capacity) {
                var index: u32 = 0;

                while (index + 1 < capacity) : (index += 1) {
                    assert(index + 1 < capacity);

                    instance.items[index] = instance.items[index + 1];
                }

                assert(index + 1 == capacity);

                instance.len = capacity - 1;
            }

            assert(instance.len < capacity);

            instance.items[instance.len] = value;
            instance.len += 1;

            assert(instance.len <= capacity);
            assert(instance.items[instance.len - 1] == value);
        }

        pub fn pop(instance: *Instance) ?u8 {
            assert(instance.len <= capacity);

            if (instance.len == 0) return null;

            instance.len -= 1;

            const result = instance.items[instance.len];

            assert(instance.len < capacity);

            return result;
        }

        pub fn clear(instance: *Instance) void {
            assert(instance.len <= capacity);

            instance.len = 0;

            assert(instance.len == 0);
        }

        pub fn get(instance: *const Instance, index: u32) ?u8 {
            assert(instance.len <= capacity);

            if (index >= instance.len) return null;

            assert(index < capacity);

            return instance.items[index];
        }

        pub fn length(instance: *const Instance) u32 {
            assert(instance.len <= capacity);

            return instance.len;
        }

        pub fn match(instance: *const Instance, pattern: []const u8) circular.Error!bool {
            assert(instance.len <= capacity);

            if (pattern.len == 0) return circular.Error.EmptyPattern;
            if (pattern.len > capacity) return circular.Error.PatternTooLarge;
            if (instance.len < pattern.len) return false;

            const size: u32 = @intCast(pattern.len);
            const start = instance.len - size;

            assert(start + size == instance.len);

            return std.mem.eql(u8, instance.items[start..instance.len], pattern);
        }

        pub fn suffix(instance: *const Instance, target: []u8, random: std.Random) u32 {
            assert(target.len == capacity);
            assert(instance.len <= capacity);

            if (instance.len == 0) return 0;

            const size = random.intRangeAtMost(u32, 1, instance.len);

            assert(size >= 1);
            assert(size <= instance.len);

            const start = instance.len - size;

            @memcpy(target[0..size], instance.items[start..instance.len]);

            return size;
        }
    };
}

const testing = std.testing;

test "fuzz: circular buffer tracks the reference model" {
    try main(testing.allocator, .{ .seed = 0x71c4_9a2e, .events_max = 2048 });
}

test "fuzz: circular buffer is deterministic per seed" {
    try main(testing.allocator, .{ .seed = 99, .events_max = 256 });
    try main(testing.allocator, .{ .seed = 99, .events_max = 256 });
}
