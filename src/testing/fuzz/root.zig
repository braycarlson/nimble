const std = @import("std");

pub const common = @import("common.zig");
pub const input = @import("input.zig");
pub const registry = @import("registry.zig");
pub const model = @import("model.zig");
pub const simulator = @import("simulator.zig");

pub const random_enum = common.random_enum;
pub const random_enum_excluding = common.random_enum_excluding;
pub const random_bool = common.random_bool;
pub const random_bool_weighted = common.random_bool_weighted;
pub const random_from_slice = common.random_from_slice;
pub const random_modifier_set = common.random_modifier_set;
pub const random_modifier_set_limited = common.random_modifier_set_limited;
pub const weighted_select = common.weighted_select;

pub const random_key_code = input.random_key_code;
pub const random_non_modifier_key_code = input.random_non_modifier_key_code;
pub const random_common_key = input.random_common_key;
pub const random_modifier_code = input.random_modifier_code;
pub const random_alpha_key = input.random_alpha_key;
pub const random_digit_key = input.random_digit_key;
pub const random_function_key = input.random_function_key;
pub const random_numpad_key = input.random_numpad_key;
pub const is_modifier_code = input.is_modifier_code;
pub const KeySequence = input.KeySequence;

pub const fuzz_key_registry = registry.fuzz_key_registry;
pub const fuzz_binding_matching = registry.fuzz_binding_matching;

pub const Model = model.Model;
pub const Operation = model.Operation;
pub const Simulator = simulator.Simulator;
pub const Failure = simulator.Failure;
pub const Trace = simulator.Trace;

pub const key_permutation_capacity: u8 = 8;
pub const modifier_permutation_capacity: u8 = 16;
pub const event_sequence_capacity: u16 = 256;
pub const iteration_max: u32 = 0xFFFFFFFF;
pub const delay_min: u16 = 10;
pub const delay_max: u16 = 200;
pub const release_delay_min: u16 = 10;
pub const release_delay_max: u16 = 50;
pub const release_probability: u8 = 40;

pub const FuzzArgs = struct {
    seed: u64,
    iterations: u32 = 10000,
    verbose: bool = false,

    pub fn is_valid(self: *const FuzzArgs) bool {
        std.debug.assert(iteration_max == 0xFFFFFFFF);

        const valid_iterations = self.iterations > 0;

        return valid_iterations;
    }
};

pub const KeyPermutation = struct {
    keys: [key_permutation_capacity]u8 = [_]u8{0} ** key_permutation_capacity,
    len: u8 = 0,
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) KeyPermutation {
        const result = KeyPermutation{
            .prng = std.Random.DefaultPrng.init(seed),
        };

        std.debug.assert(result.len == 0);

        return result;
    }

    pub fn is_valid(self: *const KeyPermutation) bool {
        std.debug.assert(key_permutation_capacity == 8);

        const result = self.len <= key_permutation_capacity;

        return result;
    }

    pub fn generate(self: *KeyPermutation, count: u8) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(count <= key_permutation_capacity);

        var random = self.prng.random();

        self.len = @min(count, key_permutation_capacity);

        var i: u8 = 0;

        while (i < self.len) : (i += 1) {
            std.debug.assert(i < self.len);
            std.debug.assert(i < key_permutation_capacity);

            self.keys[i] = input.random_non_modifier_key_code(&random);
        }

        std.debug.assert(i == self.len);
        std.debug.assert(self.is_valid());
    }

    pub fn slice(self: *const KeyPermutation) []const u8 {
        std.debug.assert(self.is_valid());

        const result = self.keys[0..self.len];

        std.debug.assert(result.len == self.len);

        return result;
    }
};

pub const ModifierPermutation = struct {
    combinations: [modifier_permutation_capacity]u4 = [_]u4{0} ** modifier_permutation_capacity,
    len: u8 = 0,
    prng: std.Random.DefaultPrng,

    pub fn init(seed: u64) ModifierPermutation {
        const result = ModifierPermutation{
            .prng = std.Random.DefaultPrng.init(seed),
        };

        std.debug.assert(result.len == 0);

        return result;
    }

    pub fn is_valid(self: *const ModifierPermutation) bool {
        std.debug.assert(modifier_permutation_capacity == 16);

        const result = self.len <= modifier_permutation_capacity;

        return result;
    }

    pub fn generate_all(self: *ModifierPermutation) void {
        std.debug.assert(@intFromPtr(self) != 0);

        self.len = modifier_permutation_capacity;

        var i: u8 = 0;

        while (i < modifier_permutation_capacity) : (i += 1) {
            std.debug.assert(i < modifier_permutation_capacity);

            self.combinations[i] = @intCast(i);
        }

        std.debug.assert(i == modifier_permutation_capacity);
        std.debug.assert(self.is_valid());
    }

    pub fn generate_random(self: *ModifierPermutation, count: u8) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(count <= modifier_permutation_capacity);

        var random = self.prng.random();

        self.len = @min(count, modifier_permutation_capacity);

        var i: u8 = 0;

        while (i < self.len) : (i += 1) {
            std.debug.assert(i < self.len);
            std.debug.assert(i < modifier_permutation_capacity);

            self.combinations[i] = random.int(u4);
        }

        std.debug.assert(i == self.len);
        std.debug.assert(self.is_valid());
    }

    pub fn slice(self: *const ModifierPermutation) []const u4 {
        std.debug.assert(self.is_valid());

        const result = self.combinations[0..self.len];

        std.debug.assert(result.len == self.len);

        return result;
    }
};

pub const InputSequence = struct {
    events: [event_sequence_capacity]Event = undefined,
    len: u16 = 0,
    prng: std.Random.DefaultPrng,

    pub const Event = struct {
        key: u8,
        down: bool,
        delay: u16,

        pub fn is_valid(self: *const Event) bool {
            const input_mod = @import("input");

            const result = input_mod.code.is_valid(self.key);

            return result;
        }
    };

    pub fn init(seed: u64) InputSequence {
        const result = InputSequence{
            .prng = std.Random.DefaultPrng.init(seed),
        };

        std.debug.assert(result.len == 0);

        return result;
    }

    pub fn is_valid(self: *const InputSequence) bool {
        std.debug.assert(event_sequence_capacity == 256);

        const result = self.len <= event_sequence_capacity;

        return result;
    }

    pub fn generate_realistic(self: *InputSequence, length: u16) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(length <= event_sequence_capacity);

        var random = self.prng.random();
        var held_keys = input.KeySequence.init();

        self.len = 0;

        generate_key_events(self, &random, &held_keys, length);
        release_remaining_keys(self, &random, &held_keys);

        std.debug.assert(self.is_valid());
    }

    pub fn slice(self: *const InputSequence) []const Event {
        std.debug.assert(self.is_valid());

        const result = self.events[0..self.len];

        std.debug.assert(result.len == self.len);

        return result;
    }
};

fn generate_key_events(seq: *InputSequence, random: *std.Random, held_keys: *input.KeySequence, length: u16) void {
    std.debug.assert(@intFromPtr(seq) != 0);
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(@intFromPtr(held_keys) != 0);

    var i: u16 = 0;

    while (i < length and seq.len < event_sequence_capacity) : (i += 1) {
        std.debug.assert(i < length or seq.len >= event_sequence_capacity);

        const should_release = held_keys.len > 0 and random.intRangeLessThan(u8, 0, 100) < release_probability;

        if (should_release) {
            release_key(seq, random, held_keys);
        } else {
            press_key(seq, random, held_keys);
        }
    }

    std.debug.assert(i == length or seq.len == event_sequence_capacity);
}

fn release_key(seq: *InputSequence, random: *std.Random, held_keys: *input.KeySequence) void {
    std.debug.assert(@intFromPtr(seq) != 0);
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(@intFromPtr(held_keys) != 0);
    std.debug.assert(held_keys.len > 0);

    const key = held_keys.pop();

    if (key) |k| {
        std.debug.assert(seq.len < event_sequence_capacity);

        seq.events[seq.len] = .{
            .key = k,
            .down = false,
            .delay = random.intRangeAtMost(u16, delay_min, 100),
        };

        seq.len += 1;
    }
}

fn press_key(seq: *InputSequence, random: *std.Random, held_keys: *input.KeySequence) void {
    std.debug.assert(@intFromPtr(seq) != 0);
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(@intFromPtr(held_keys) != 0);

    const key = input.random_common_key(random);

    if (!held_keys.contains(key)) {
        held_keys.push(key);

        std.debug.assert(seq.len < event_sequence_capacity);

        seq.events[seq.len] = .{
            .key = key,
            .down = true,
            .delay = random.intRangeAtMost(u16, delay_min + 40, delay_max),
        };

        seq.len += 1;
    }
}

fn release_remaining_keys(seq: *InputSequence, random: *std.Random, held_keys: *input.KeySequence) void {
    std.debug.assert(@intFromPtr(seq) != 0);
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(@intFromPtr(held_keys) != 0);

    var j: u16 = 0;

    while (held_keys.len > 0 and seq.len < event_sequence_capacity and j < event_sequence_capacity) : (j += 1) {
        std.debug.assert(j < event_sequence_capacity);

        const key = held_keys.pop();

        if (key) |k| {
            seq.events[seq.len] = .{
                .key = k,
                .down = false,
                .delay = random.intRangeAtMost(u16, release_delay_min, release_delay_max),
            };

            seq.len += 1;
        }
    }

    std.debug.assert(j <= event_sequence_capacity);
}

test {
    _ = common;
    _ = input;
    _ = registry;
    _ = model;
    _ = simulator;
}
