const std = @import("std");

const input = @import("input");
const keycode = input.keycode;
const modifier = input.modifier;

pub const iteration_max: u32 = 1024;
pub const shuffle_max: u8 = 16;
pub const weight_max: u32 = 1024;
pub const seed_buffer_size: u8 = 8;
pub const modifier_limit_max: u8 = 4;
pub const modifier_flag_max: u4 = 0x0F;
pub const env_seed_name = "FUZZ_SEED";

pub fn get_random_seed() u64 {
    var buffer: [seed_buffer_size]u8 = undefined;

    std.debug.assert(buffer.len == seed_buffer_size);

    std.posix.getrandom(&buffer) catch {
        const timestamp: u64 = @intCast(std.time.milliTimestamp());

        std.debug.assert(timestamp > 0 or timestamp == 0);

        return timestamp;
    };

    const result = std.mem.readInt(u64, &buffer, .little);

    std.debug.assert(result > 0 or result == 0);

    return result;
}

pub fn get_seed_from_env(allocator: std.mem.Allocator) u64 {
    std.debug.assert(@intFromPtr(&allocator) != 0);

    const env_seed = std.process.getEnvVarOwned(allocator, env_seed_name) catch {
        return get_random_seed();
    };

    defer allocator.free(env_seed);

    std.debug.assert(env_seed.len >= 0);

    const result = parse_seed(env_seed);

    return result;
}

pub fn parse_seed(text: []const u8) u64 {
    std.debug.assert(text.len > 0 or text.len == 0);

    const result = std.fmt.parseUnsigned(u64, text, 10) catch {
        return get_random_seed();
    };

    std.debug.assert(result > 0 or result == 0);

    return result;
}

pub fn random_enum(comptime E: type, random: *std.Random) E {
    std.debug.assert(@intFromPtr(random) != 0);

    const fields = @typeInfo(E).@"enum".fields;

    comptime std.debug.assert(fields.len > 0);
    comptime std.debug.assert(fields.len <= iteration_max);

    const idx = random.intRangeLessThan(usize, 0, fields.len);

    std.debug.assert(idx < fields.len);

    const result: E = @enumFromInt(fields[idx].value);

    return result;
}

pub fn random_enum_excluding(comptime E: type, random: *std.Random, exclude: E) E {
    std.debug.assert(@intFromPtr(random) != 0);

    const fields = @typeInfo(E).@"enum".fields;

    comptime std.debug.assert(fields.len > 1);
    comptime std.debug.assert(fields.len <= iteration_max);

    var attempts: u8 = 0;
    var result = random_enum(E, random);

    while (result == exclude and attempts < shuffle_max) : (attempts += 1) {
        std.debug.assert(attempts < shuffle_max);

        result = random_enum(E, random);
    }

    std.debug.assert(attempts <= shuffle_max);

    if (result == exclude) {
        var i: usize = 0;

        while (i < fields.len) : (i += 1) {
            std.debug.assert(i < fields.len);

            const candidate: E = @enumFromInt(fields[i].value);

            if (candidate != exclude) {
                return candidate;
            }
        }

        std.debug.assert(i == fields.len);
    }

    std.debug.assert(result != exclude);

    return result;
}

pub fn random_bool(random: *std.Random) bool {
    std.debug.assert(@intFromPtr(random) != 0);

    const value = random.intRangeLessThan(u8, 0, 2);

    std.debug.assert(value == 0 or value == 1);

    const result = value == 1;

    return result;
}

pub fn random_bool_weighted(random: *std.Random, true_probability: u8) bool {
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(true_probability <= 100);

    const roll = random.intRangeLessThan(u8, 0, 100);

    std.debug.assert(roll < 100);

    const result = roll < true_probability;

    return result;
}

pub fn random_from_slice(comptime T: type, random: *std.Random, items: []const T) T {
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(items.len > 0);
    std.debug.assert(items.len <= iteration_max);

    const idx = random.intRangeLessThan(usize, 0, items.len);

    std.debug.assert(idx < items.len);

    const result = items[idx];

    return result;
}

pub fn random_modifier_set(random: *std.Random) modifier.Set {
    std.debug.assert(@intFromPtr(random) != 0);

    const flags = random.intRangeAtMost(u4, 0, modifier_flag_max);

    std.debug.assert(flags <= modifier_flag_max);

    const result = modifier.Set{ .flags = flags };

    std.debug.assert(result.flags == flags);

    return result;
}

pub fn random_modifier_set_limited(random: *std.Random, max_modifiers: u8) modifier.Set {
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(max_modifiers <= modifier_limit_max);

    var flags: u4 = 0;
    var count: u8 = 0;
    var i: u8 = 0;

    while (i < modifier_limit_max and count < max_modifiers) : (i += 1) {
        std.debug.assert(i < modifier_limit_max);
        std.debug.assert(count <= max_modifiers);

        if (random_bool(random)) {
            const flag = get_modifier_flag_by_index(i);

            flags |= flag;
            count += 1;
        }
    }

    std.debug.assert(i <= modifier_limit_max);
    std.debug.assert(count <= max_modifiers);
    std.debug.assert(flags <= modifier_flag_max);

    const result = modifier.Set{ .flags = flags };

    std.debug.assert(result.count() <= max_modifiers);

    return result;
}

fn get_modifier_flag_by_index(idx: u8) u4 {
    std.debug.assert(idx < modifier_limit_max);

    const flags = [modifier_limit_max]u4{
        modifier.flag_ctrl,
        modifier.flag_alt,
        modifier.flag_shift,
        modifier.flag_win,
    };

    const result = flags[idx];

    std.debug.assert(result > 0);

    return result;
}

pub fn weighted_select(comptime T: type, random: *std.Random, items: []const T, weights: []const u32) T {
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(items.len > 0);
    std.debug.assert(items.len == weights.len);
    std.debug.assert(items.len <= iteration_max);

    const total = compute_weight_total(weights);

    std.debug.assert(total > 0);
    std.debug.assert(total <= weight_max * items.len);

    var choice = random.intRangeLessThan(u32, 0, total);
    var i: u32 = 0;

    while (i < weights.len and i < iteration_max) : (i += 1) {
        std.debug.assert(i < weights.len);

        if (choice < weights[i]) {
            std.debug.assert(i < items.len);

            return items[i];
        }

        choice -= weights[i];
    }

    std.debug.assert(i == weights.len or i == iteration_max);
    std.debug.assert(items.len > 0);

    const result = items[items.len - 1];

    return result;
}

fn compute_weight_total(weights: []const u32) u32 {
    std.debug.assert(weights.len > 0);
    std.debug.assert(weights.len <= iteration_max);

    var total: u32 = 0;
    var i: u32 = 0;

    while (i < weights.len and i < iteration_max) : (i += 1) {
        std.debug.assert(i < weights.len);
        std.debug.assert(total <= weight_max * iteration_max);

        total += weights[i];
    }

    std.debug.assert(i == weights.len or i == iteration_max);
    std.debug.assert(total > 0);

    return total;
}

pub fn shuffle(comptime T: type, random: *std.Random, items: []T) void {
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(items.len <= iteration_max);

    if (items.len <= 1) {
        return;
    }

    std.debug.assert(items.len > 1);

    var i: u32 = @intCast(items.len);
    var iteration: u32 = 0;

    while (i > 1 and iteration < iteration_max) : (iteration += 1) {
        std.debug.assert(i > 1);
        std.debug.assert(iteration < iteration_max);

        i -= 1;

        const j = random.intRangeLessThan(u32, 0, i + 1);

        std.debug.assert(j <= i);
        std.debug.assert(i < items.len);
        std.debug.assert(j < items.len);

        const tmp = items[i];

        items[i] = items[j];
        items[j] = tmp;
    }

    std.debug.assert(iteration <= iteration_max);
}

const testing = std.testing;

test "get_random_seed produces value" {
    const seed = get_random_seed();

    std.debug.assert(seed >= 0);

    try testing.expect(seed >= 0);
}

test "parse_seed valid" {
    const result = parse_seed("12345");

    std.debug.assert(result == 12345);

    try testing.expectEqual(@as(u64, 12345), result);
}

test "parse_seed invalid falls back" {
    const result = parse_seed("not_a_number");

    std.debug.assert(result >= 0);

    try testing.expect(result >= 0);
}

test "random_bool distribution" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var true_count: u32 = 0;
    var i: u32 = 0;

    while (i < 1000) : (i += 1) {
        std.debug.assert(i < 1000);

        if (random_bool(&random)) {
            true_count += 1;
        }
    }

    std.debug.assert(i == 1000);
    std.debug.assert(true_count > 0);
    std.debug.assert(true_count < 1000);

    try testing.expect(true_count > 400);
    try testing.expect(true_count < 600);
}

test "random_bool_weighted probability" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var true_count: u32 = 0;
    var i: u32 = 0;

    while (i < 1000) : (i += 1) {
        std.debug.assert(i < 1000);

        if (random_bool_weighted(&random, 80)) {
            true_count += 1;
        }
    }

    std.debug.assert(i == 1000);

    try testing.expect(true_count > 700);
}

test "random_modifier_set_limited respects limit" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var i: u32 = 0;

    while (i < 100) : (i += 1) {
        std.debug.assert(i < 100);

        const mods = random_modifier_set_limited(&random, 2);

        std.debug.assert(mods.count() <= 2);

        try testing.expect(mods.count() <= 2);
    }

    std.debug.assert(i == 100);
}

test "weighted_select distribution" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    const items = [_]u8{ 'A', 'B', 'C' };
    const weights = [_]u32{ 100, 50, 50 };
    var a_count: u32 = 0;
    var i: u32 = 0;

    while (i < 1000) : (i += 1) {
        std.debug.assert(i < 1000);

        const result = weighted_select(u8, &random, &items, &weights);

        if (result == 'A') {
            a_count += 1;
        }
    }

    std.debug.assert(i == 1000);

    try testing.expect(a_count > 400);
}

test "shuffle changes order" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var items = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const original = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };

    shuffle(u8, &random, &items);

    var same_count: u8 = 0;
    var i: u8 = 0;

    while (i < items.len) : (i += 1) {
        std.debug.assert(i < items.len);

        if (items[i] == original[i]) {
            same_count += 1;
        }
    }

    std.debug.assert(i == items.len);

    try testing.expect(same_count < 8);
}

test "random_enum produces valid values" {
    const TestEnum = enum(u8) {
        first = 0,
        second = 1,
        third = 2,
    };

    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var seen = [_]bool{ false, false, false };
    var i: u32 = 0;

    while (i < 100) : (i += 1) {
        std.debug.assert(i < 100);

        const value = random_enum(TestEnum, &random);

        seen[@intFromEnum(value)] = true;
    }

    std.debug.assert(i == 100);
    std.debug.assert(seen[0] and seen[1] and seen[2]);

    try testing.expect(seen[0]);
    try testing.expect(seen[1]);
    try testing.expect(seen[2]);
}

test "random_enum_excluding respects exclusion" {
    const TestEnum = enum(u8) {
        first = 0,
        second = 1,
        third = 2,
    };

    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var i: u32 = 0;

    while (i < 100) : (i += 1) {
        std.debug.assert(i < 100);

        const value = random_enum_excluding(TestEnum, &random, .first);

        std.debug.assert(value != .first);

        try testing.expect(value != .first);
    }

    std.debug.assert(i == 100);
}
