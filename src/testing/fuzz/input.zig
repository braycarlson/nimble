const std = @import("std");

const input = @import("input");
const keycode = input.keycode;
const modifier = input.modifier;

const common = @import("common.zig");

pub const sequence_capacity: u8 = 32;
pub const modifier_keycode_count: u8 = 8;
pub const iteration_max: u32 = 0xFFFFFFFF;
pub const key_value_min: u8 = 0x08;
pub const key_value_max: u8 = 0xFE;
pub const alpha_key_min: u8 = 'A';
pub const alpha_key_max: u8 = 'Z';
pub const digit_key_min: u8 = '0';
pub const digit_key_max: u8 = '9';
pub const common_key_count: u8 = 16;
pub const operation_threshold_keydown: u8 = 40;
pub const operation_threshold_keyup: u8 = 80;

const modifier_keycodes = [modifier_keycode_count]u8{
    keycode.lshift,
    keycode.rshift,
    keycode.lctrl,
    keycode.rctrl,
    keycode.lmenu,
    keycode.rmenu,
    keycode.lwin,
    keycode.rwin,
};

const common_keys = [common_key_count]u8{
    'A', 'S', 'D', 'W', 'E', 'R', 'F', 'G',
    'Q', 'Z', 'X', 'C', 'V', 'B', 'N', 'M',
};

pub fn random_key_keycode(random: *std.Random) u8 {
    std.debug.assert(@intFromPtr(random) != 0);

    const result = random.intRangeAtMost(u8, key_value_min, key_value_max);

    std.debug.assert(result >= key_value_min);
    std.debug.assert(result <= key_value_max);
    std.debug.assert(keycode.is_valid(result));

    return result;
}

pub fn random_non_modifier_key_keycode(random: *std.Random) u8 {
    std.debug.assert(@intFromPtr(random) != 0);

    var attempts: u8 = 0;
    var result: u8 = random.intRangeAtMost(u8, key_value_min, key_value_max);

    while (keycode.is_modifier(result) and attempts < sequence_capacity) : (attempts += 1) {
        std.debug.assert(attempts < sequence_capacity);

        result = random.intRangeAtMost(u8, key_value_min, key_value_max);
    }

    std.debug.assert(attempts <= sequence_capacity);
    std.debug.assert(!keycode.is_modifier(result));
    std.debug.assert(keycode.is_valid(result));

    return result;
}

pub fn random_common_key(random: *std.Random) u8 {
    std.debug.assert(@intFromPtr(random) != 0);

    const idx = random.intRangeLessThan(u8, 0, common_key_count);

    std.debug.assert(idx < common_key_count);

    const result = common_keys[idx];

    std.debug.assert(result >= alpha_key_min);
    std.debug.assert(result <= alpha_key_max);

    return result;
}

pub fn random_modifier_keycode(random: *std.Random) u8 {
    std.debug.assert(@intFromPtr(random) != 0);

    const idx = random.intRangeLessThan(u8, 0, modifier_keycode_count);

    std.debug.assert(idx < modifier_keycode_count);

    const result = modifier_keycodes[idx];

    std.debug.assert(keycode.is_modifier(result));
    std.debug.assert(keycode.is_valid(result));

    return result;
}

pub fn random_alpha_key(random: *std.Random) u8 {
    std.debug.assert(@intFromPtr(random) != 0);

    const result = random.intRangeAtMost(u8, alpha_key_min, alpha_key_max);

    std.debug.assert(result >= alpha_key_min);
    std.debug.assert(result <= alpha_key_max);

    return result;
}

pub fn random_digit_key(random: *std.Random) u8 {
    std.debug.assert(@intFromPtr(random) != 0);

    const result = random.intRangeAtMost(u8, digit_key_min, digit_key_max);

    std.debug.assert(result >= digit_key_min);
    std.debug.assert(result <= digit_key_max);

    return result;
}

pub fn random_function_key(random: *std.Random) u8 {
    std.debug.assert(@intFromPtr(random) != 0);

    const result = random.intRangeAtMost(u8, keycode.f1, keycode.f12);

    std.debug.assert(result >= keycode.f1);
    std.debug.assert(result <= keycode.f12);
    std.debug.assert(keycode.is_valid(result));

    return result;
}

pub fn random_numpad_key(random: *std.Random) u8 {
    std.debug.assert(@intFromPtr(random) != 0);

    const result = random.intRangeAtMost(u8, keycode.numpad0, keycode.numpad9);

    std.debug.assert(result >= keycode.numpad0);
    std.debug.assert(result <= keycode.numpad9);
    std.debug.assert(keycode.is_valid(result));

    return result;
}

pub fn is_modifier_keycode(value: u8) bool {
    std.debug.assert(keycode.is_valid(value));

    var i: u8 = 0;

    while (i < modifier_keycode_count) : (i += 1) {
        std.debug.assert(i < modifier_keycode_count);

        if (value == modifier_keycodes[i]) {
            std.debug.assert(keycode.is_modifier(value));

            return true;
        }
    }

    std.debug.assert(i == modifier_keycode_count);

    return false;
}

pub fn fuzz_binding(random: *std.Random, iterations: u32) !void {
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(iterations > 0);
    std.debug.assert(iterations <= iteration_max);

    const Binding = input.binding.Binding;
    const Keyboard = input.state.Keyboard;

    var iteration: u32 = 0;

    while (iteration < iterations) : (iteration += 1) {
        std.debug.assert(iteration < iterations);

        const key_keycode = random_non_modifier_key_keycode(random);
        const mods = common.random_modifier_set_limited(random, 3);
        const binding = Binding.init(key_keycode, mods);

        std.debug.assert(binding.is_valid());
        std.debug.assert(!keycode.is_modifier(key_keycode));

        var keyboard = Keyboard.init();

        std.debug.assert(keyboard.count() == 0);

        apply_binding_to_keyboard(&keyboard, key_keycode, &mods);

        std.debug.assert(keyboard.is_down(key_keycode));
        std.debug.assert(binding.match(&keyboard));

        keyboard.clear();

        std.debug.assert(keyboard.count() == 0);
        std.debug.assert(!binding.match(&keyboard));
    }

    std.debug.assert(iteration == iterations);
}

fn apply_binding_to_keyboard(
    keyboard: *input.state.Keyboard,
    key_keycode: u8,
    mods: *const modifier.Set,
) void {
    std.debug.assert(@intFromPtr(keyboard) != 0);
    std.debug.assert(keycode.is_valid(key_keycode));
    std.debug.assert(mods.flags <= modifier.flag_all);

    const initial_count = keyboard.count();

    keyboard.keydown(key_keycode);

    if (mods.ctrl()) {
        keyboard.keydown(keycode.lctrl);
    }

    if (mods.alt()) {
        keyboard.keydown(keycode.lmenu);
    }

    if (mods.shift()) {
        keyboard.keydown(keycode.lshift);
    }

    if (mods.win()) {
        keyboard.keydown(keycode.lwin);
    }

    std.debug.assert(keyboard.is_down(key_keycode));
    std.debug.assert(keyboard.count() >= initial_count + 1);
}

pub fn fuzz_keyboard(random: *std.Random, iterations: u32) !void {
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(iterations > 0);
    std.debug.assert(iterations <= iteration_max);

    const Keyboard = input.state.Keyboard;

    var keyboard = Keyboard.init();
    var iteration: u32 = 0;

    std.debug.assert(keyboard.count() == 0);

    while (iteration < iterations) : (iteration += 1) {
        std.debug.assert(iteration < iterations);

        const operation = random.intRangeLessThan(u8, 0, 100);

        std.debug.assert(operation < 100);

        execute_keyboard_operation(&keyboard, random, operation);
    }

    std.debug.assert(iteration == iterations);
}

fn execute_keyboard_operation(
    keyboard: *input.state.Keyboard,
    random: *std.Random,
    operation: u8,
) void {
    std.debug.assert(@intFromPtr(keyboard) != 0);
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(operation < 100);

    if (operation < operation_threshold_keydown) {
        execute_keydown_operation(keyboard, random);
    } else if (operation < operation_threshold_keyup) {
        execute_keyup_operation(keyboard, random);
    } else {
        execute_clear_operation(keyboard);
    }
}

fn execute_keydown_operation(keyboard: *input.state.Keyboard, random: *std.Random) void {
    std.debug.assert(@intFromPtr(keyboard) != 0);
    std.debug.assert(@intFromPtr(random) != 0);

    const key = random_key_keycode(random);

    std.debug.assert(keycode.is_valid(key));

    keyboard.keydown(key);

    std.debug.assert(keyboard.is_down(key));
}

fn execute_keyup_operation(keyboard: *input.state.Keyboard, random: *std.Random) void {
    std.debug.assert(@intFromPtr(keyboard) != 0);
    std.debug.assert(@intFromPtr(random) != 0);

    const key = random_key_keycode(random);

    std.debug.assert(keycode.is_valid(key));

    keyboard.keyup(key);

    std.debug.assert(!keyboard.is_down(key));
}

fn execute_clear_operation(keyboard: *input.state.Keyboard) void {
    std.debug.assert(@intFromPtr(keyboard) != 0);

    keyboard.clear();

    std.debug.assert(keyboard.count() == 0);
}

pub const KeySequence = struct {
    keys: [sequence_capacity]u8 = [_]u8{0} ** sequence_capacity,
    len: u8 = 0,

    pub fn init() KeySequence {
        const result = KeySequence{};

        std.debug.assert(result.len == 0);
        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn is_valid(self: *const KeySequence) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_len = self.len <= sequence_capacity;
        const result = valid_len;

        return result;
    }

    pub fn push(self: *KeySequence, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        if (self.len >= sequence_capacity) {
            std.debug.assert(self.len == sequence_capacity);

            return;
        }

        std.debug.assert(self.len < sequence_capacity);

        self.keys[self.len] = key;
        self.len += 1;

        std.debug.assert(self.len <= sequence_capacity);
        std.debug.assert(self.is_valid());
    }

    pub fn pop(self: *KeySequence) ?u8 {
        std.debug.assert(self.is_valid());

        if (self.len == 0) {
            return null;
        }

        std.debug.assert(self.len > 0);

        self.len -= 1;

        const result = self.keys[self.len];

        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(result));

        return result;
    }

    pub fn slice(self: *const KeySequence) []const u8 {
        std.debug.assert(self.is_valid());

        const result = self.keys[0..self.len];

        std.debug.assert(result.len == self.len);

        return result;
    }

    pub fn clear(self: *KeySequence) void {
        std.debug.assert(self.is_valid());

        self.len = 0;

        std.debug.assert(self.len == 0);
        std.debug.assert(self.is_valid());
    }

    pub fn contains(self: *const KeySequence, key: u8) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        var i: u8 = 0;

        while (i < self.len and i < sequence_capacity) : (i += 1) {
            std.debug.assert(i < self.len);

            if (self.keys[i] == key) {
                return true;
            }
        }

        std.debug.assert(i == self.len or i == sequence_capacity);

        return false;
    }
};

const testing = std.testing;

test "random_key_keycode produces valid keycodes" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var i: u32 = 0;

    while (i < 100) : (i += 1) {
        std.debug.assert(i < 100);

        const key = random_key_keycode(&random);

        std.debug.assert(keycode.is_valid(key));

        try testing.expect(key >= key_value_min);
        try testing.expect(key <= key_value_max);
    }

    std.debug.assert(i == 100);
}

test "random_non_modifier_key_keycode excludes modifiers" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var i: u32 = 0;

    while (i < 100) : (i += 1) {
        std.debug.assert(i < 100);

        const key = random_non_modifier_key_keycode(&random);

        std.debug.assert(!keycode.is_modifier(key));

        try testing.expect(!keycode.is_modifier(key));
        try testing.expect(keycode.is_valid(key));
    }

    std.debug.assert(i == 100);
}

test "random_modifier_keycode produces only modifiers" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var i: u32 = 0;

    while (i < 100) : (i += 1) {
        std.debug.assert(i < 100);

        const key = random_modifier_keycode(&random);

        std.debug.assert(keycode.is_modifier(key));

        try testing.expect(keycode.is_modifier(key));
        try testing.expect(keycode.is_valid(key));
    }

    std.debug.assert(i == 100);
}

test "KeySequence init" {
    const seq = KeySequence.init();

    std.debug.assert(seq.len == 0);
    std.debug.assert(seq.is_valid());

    try testing.expectEqual(@as(u8, 0), seq.len);
    try testing.expect(seq.is_valid());
}

test "KeySequence push and pop" {
    var seq = KeySequence.init();

    std.debug.assert(seq.len == 0);

    seq.push('A');

    std.debug.assert(seq.len == 1);

    seq.push('B');

    std.debug.assert(seq.len == 2);

    try testing.expectEqual(@as(u8, 2), seq.len);
    try testing.expect(seq.is_valid());

    const b = seq.pop();

    std.debug.assert(seq.len == 1);

    try testing.expectEqual(@as(u8, 'B'), b.?);

    const a = seq.pop();

    std.debug.assert(seq.len == 0);

    try testing.expectEqual(@as(u8, 'A'), a.?);
    try testing.expectEqual(@as(?u8, null), seq.pop());
}

test "KeySequence contains" {
    var seq = KeySequence.init();

    std.debug.assert(!seq.contains('A'));

    seq.push('A');
    seq.push('B');

    std.debug.assert(seq.contains('A'));
    std.debug.assert(seq.contains('B'));
    std.debug.assert(!seq.contains('C'));

    try testing.expect(seq.contains('A'));
    try testing.expect(seq.contains('B'));
    try testing.expect(!seq.contains('C'));
}

test "KeySequence capacity limit" {
    var seq = KeySequence.init();
    var i: u8 = 0;

    while (i < sequence_capacity) : (i += 1) {
        std.debug.assert(i < sequence_capacity);

        seq.push(i + key_value_min);
    }

    std.debug.assert(i == sequence_capacity);
    std.debug.assert(seq.len == sequence_capacity);

    seq.push(0xFF);

    std.debug.assert(seq.len == sequence_capacity);

    try testing.expectEqual(sequence_capacity, seq.len);
    try testing.expect(seq.is_valid());
}

test "fuzz_binding basic" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();

    try fuzz_binding(&random, 100);
}

test "fuzz_keyboard basic" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();

    try fuzz_keyboard(&random, 100);
}
