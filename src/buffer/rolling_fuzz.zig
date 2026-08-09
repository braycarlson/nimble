const std = @import("std");

const fuzz = @import("../testing/fuzz.zig");
const rolling = @import("rolling.zig");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Operation = enum {
    push,
    push_alphabet,
    push_burst,
    pop,
    clear,
    slice_from,
    slice_range,
};

const capacities = [_]u32{ 1, 2, 3, 4, 7, 8, 16, 64 };
const alphabet = [_]u8{ 'A', 'B', 'C', 'D' };
const burst_mean: u32 = 4;
const burst_count_max: u32 = 256;

comptime {
    assert(capacities.len > 0);
    assert(alphabet.len > 1);
    assert(burst_mean >= 1);
    assert(burst_count_max > burst_mean);
    assert(capacities[capacities.len - 1] <= rolling.capacity_max);
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

    const Buffer = rolling.RollingBufferType(capacity);
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
    buffer: *rolling.RollingBufferType(capacity),
    model: *ModelType(capacity),
    operation: Operation,
) void {
    assert(buffer.is_valid());

    switch (operation) {
        .push => push(capacity, buffer, model, random.int(u8)),
        .push_alphabet => push(
            capacity,
            buffer,
            model,
            fuzz.random_from_slice(random, u8, &alphabet),
        ),
        .push_burst => {
            const count = fuzz.random_int_exponential(random, u32, burst_mean);
            var index: u32 = 0;

            while (index < count and index < burst_count_max) : (index += 1) {
                const value = fuzz.random_from_slice(random, u8, &alphabet);

                push(capacity, buffer, model, value);
            }

            assert(index == count or index == burst_count_max);
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
        .slice_from => {
            const start = random.uintAtMost(u32, model.length());

            assert(start <= model.length());
            assert(std.mem.eql(u8, buffer.slice_from(start), model.slice_from(start)));
        },
        .slice_range => {
            const end = random.uintAtMost(u32, model.length());
            const start = random.uintAtMost(u32, end);

            assert(start <= end);
            assert(end <= model.length());
            assert(std.mem.eql(u8, buffer.slice_range(start, end), model.slice_range(start, end)));
        },
    }
}

fn push(
    comptime capacity: u32,
    buffer: *rolling.RollingBufferType(capacity),
    model: *ModelType(capacity),
    value: u8,
) void {
    assert(buffer.is_valid());

    buffer.push(value);
    model.push(value);

    assert(buffer.length() == model.length());
    assert(buffer.length() >= 1);
}

fn verify(
    comptime capacity: u32,
    buffer: *const rolling.RollingBufferType(capacity),
    model: *const ModelType(capacity),
) void {
    assert(buffer.is_valid());
    assert(buffer.length() == model.length());
    assert(buffer.is_empty() == (model.length() == 0));
    assert(std.mem.eql(u8, buffer.slice(), model.slice()));

    var index: u32 = 0;

    while (index <= capacity) : (index += 1) {
        assert(index <= capacity);
        assert(std.meta.eql(buffer.get(index), model.get(index)));
    }

    assert(index == capacity + 1);
}

fn ModelType(comptime capacity: u32) type {
    assert(capacity >= rolling.capacity_min);
    assert(capacity <= rolling.capacity_max);

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

        pub fn slice(instance: *const Instance) []const u8 {
            assert(instance.len <= capacity);

            return instance.items[0..instance.len];
        }

        pub fn slice_from(instance: *const Instance, start: u32) []const u8 {
            assert(instance.len <= capacity);
            assert(start <= instance.len);

            return instance.items[start..instance.len];
        }

        pub fn slice_range(instance: *const Instance, start: u32, end: u32) []const u8 {
            assert(instance.len <= capacity);
            assert(start <= end);
            assert(end <= instance.len);

            return instance.items[start..end];
        }
    };
}

const testing = std.testing;

test "fuzz: rolling buffer tracks the reference model" {
    try main(testing.allocator, .{ .seed = 0x1d0e_ff31, .events_max = 2048 });
}

test "fuzz: rolling buffer is deterministic per seed" {
    try main(testing.allocator, .{ .seed = 4242, .events_max = 256 });
    try main(testing.allocator, .{ .seed = 4242, .events_max = 256 });
}
