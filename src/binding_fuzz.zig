const std = @import("std");

const binding = @import("binding.zig");
const exhaustigen = @import("testing/exhaustigen.zig");
const fuzz = @import("testing/fuzz.zig");
const keyboard_testing = @import("testing/keyboard.zig");
const keycode = @import("keycode.zig");
const modifier = @import("modifier.zig");

const Keycode = keycode.Keycode;
const Allocator = std.mem.Allocator;
const Binding = binding.Binding;
const Gen = exhaustigen.Gen;
const assert = std.debug.assert;

const KeySource = enum {
    common,
    alpha,
    function,
    numpad,
    any,
};

const ModifierSource = enum {
    none,
    single,
    pair,
    all,
    any,
};

const KeyWeights = fuzz.EnumWeightsType(KeySource);
const ModifierWeights = fuzz.EnumWeightsType(ModifierSource);

const modifier_flags = [_]u4{
    modifier.flag_ctrl,
    modifier.flag_alt,
    modifier.flag_shift,
    modifier.flag_win,
};

const id_count_max: u32 = 4096;

comptime {
    assert(modifier_flags.len == @as(usize, modifier.kind_count));
    assert(id_count_max == (@as(u32, modifier.flag_all) + 1) << 8);
}

pub fn main(gpa: Allocator, args: fuzz.FuzzArgs) !void {
    _ = gpa;

    assert(args.events_max >= 1);

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();

    const key_weights = fuzz.random_enum_weights(random, KeySource);
    const modifier_weights = fuzz.random_enum_weights(random, ModifierSource);

    var event: u32 = 0;

    while (event < args.events_max) : (event += 1) {
        const subject = generate_binding(random, &key_weights, &modifier_weights);

        check_identity(&subject);
        check_equality(random, &subject, &key_weights, &modifier_weights);
        check_match_positive(&subject);
        check_match_negative(random, &subject);
    }

    assert(event == args.events_max);
}

fn generate_binding(
    random: std.Random,
    key_weights: *const KeyWeights,
    modifier_weights: *const ModifierWeights,
) Binding {
    const key_source = fuzz.random_enum_weighted(random, KeySource, key_weights.*);
    const modifier_source = fuzz.random_enum_weighted(random, ModifierSource, modifier_weights.*);

    const result = Binding.init(
        generate_key(random, key_source),
        generate_modifiers(random, modifier_source),
    );

    assert(result.is_valid());

    return result;
}

fn check_identity(subject: *const Binding) void {
    assert(subject.is_valid());
    assert(subject.has_win() == subject.modifiers.win());
    assert(subject.match_trigger(subject.value));

    const id = subject.id();

    assert(id < id_count_max);
    assert(id & 0xFF == @intFromEnum(subject.value));
    assert(id >> 8 == subject.modifiers.to_bits());
    assert(id == subject.id());
}

fn check_equality(
    random: std.Random,
    subject: *const Binding,
    key_weights: *const KeyWeights,
    modifier_weights: *const ModifierWeights,
) void {
    assert(subject.is_valid());
    assert(subject.eql(subject));

    const other = generate_binding(random, key_weights, modifier_weights);
    const same = subject.eql(&other);

    assert(same == other.eql(subject));
    assert(same == (subject.id() == other.id()));

    if (same) {
        assert(subject.value == other.value);
        assert(subject.modifiers.flags == other.modifiers.flags);
    }

    if (subject.value != other.value) assert(!same);
    if (subject.modifiers.flags != other.modifiers.flags) assert(!same);
}

fn check_match_positive(subject: *const Binding) void {
    assert(subject.is_valid());
    assert(!Keycode.is_modifier(subject.value));

    var keyboard = subject.to_keyboard();

    assert(keyboard.is_down(subject.value));
    assert(keyboard.count() == @as(u32, subject.modifiers.count()) + 1);
    assert(subject.match(&keyboard));

    keyboard.keyup(subject.value);

    assert(!keyboard.is_down(subject.value));
    assert(!subject.match(&keyboard));

    keyboard.clear();

    assert(keyboard.count() == 0);
    assert(!subject.match(&keyboard));
}

fn check_match_negative(random: std.Random, subject: *const Binding) void {
    assert(subject.is_valid());

    if (subject.modifiers.flags == modifier.flag_all) return;

    var keyboard = subject.to_keyboard();

    assert(subject.match(&keyboard));

    const extra = missing_modifier(random, subject.modifiers);

    assert(subject.modifiers.flags & extra == 0);

    keyboard_testing.press_modifiers(&keyboard, .{ .flags = extra });

    assert(!subject.match(&keyboard));
}

fn missing_modifier(random: std.Random, modifiers: modifier.Set) u4 {
    assert(modifiers.flags != modifier.flag_all);

    var candidates: [modifier_flags.len]u4 = undefined;
    var count: u8 = 0;
    var index: u8 = 0;

    while (index < modifier_flags.len) : (index += 1) {
        assert(index < modifier_flags.len);

        if (modifiers.flags & modifier_flags[index] == 0) {
            candidates[count] = modifier_flags[index];
            count += 1;
        }
    }

    assert(index == modifier_flags.len);
    assert(count > 0);

    const choice = random.uintLessThan(u8, count);

    assert(choice < count);

    return candidates[choice];
}

fn random_in_range(random: std.Random, low: Keycode, high: Keycode) Keycode {
    const first = @intFromEnum(low);
    const last = @intFromEnum(high);

    assert(first < last);

    return @enumFromInt(random.intRangeAtMost(u8, first, last));
}

fn generate_key(random: std.Random, source: KeySource) Keycode {
    const result = switch (source) {
        .common => keyboard_testing.random_key_common(random),
        .alpha => random_in_range(random, .a, .z),
        .function => random_in_range(random, .f1, .f12),
        .numpad => random_in_range(random, .numpad_0, .numpad_9),
        .any => keyboard_testing.random_key_non_modifier(random),
    };

    assert(!Keycode.is_modifier(result));

    return result;
}

fn generate_modifiers(random: std.Random, source: ModifierSource) modifier.Set {
    const flags: u4 = switch (source) {
        .none => modifier.flag_none,
        .single => fuzz.random_from_slice(random, u4, &modifier_flags),
        .pair => generate_modifier_pair(random),
        .all => modifier.flag_all,
        .any => random.intRangeAtMost(u4, modifier.flag_none, modifier.flag_all),
    };

    assert(flags <= modifier.flag_all);

    return modifier.Set{ .flags = flags };
}

fn generate_modifier_pair(random: std.Random) u4 {
    const first = random.uintLessThan(u8, modifier_flags.len);
    const offset = random.intRangeAtMost(u8, 1, modifier_flags.len - 1);
    const second = (first + offset) % modifier_flags.len;

    assert(first < modifier_flags.len);
    assert(second < modifier_flags.len);
    assert(first != second);

    const result = modifier_flags[first] | modifier_flags[second];

    assert(@popCount(result) == 2);

    return result;
}

const testing = std.testing;

test "fuzz: binding identity, equality, and matching hold" {
    try main(testing.allocator, .{ .seed = 0x3a91_b4c2, .events_max = 512 });
}

test "fuzz: binding checks are deterministic per seed" {
    try main(testing.allocator, .{ .seed = 7, .events_max = 128 });
    try main(testing.allocator, .{ .seed = 7, .events_max = 128 });
}

test "binding matching holds exhaustively over a small domain" {
    const values = [_]Keycode{ .a, .f1, .space };

    comptime assert(!Keycode.is_modifier(values[0]));
    comptime assert(!Keycode.is_modifier(values[1]));
    comptime assert(!Keycode.is_modifier(values[2]));

    var gen = Gen.init();
    var cases: u32 = 0;

    while (!gen.done()) {
        const value = gen.select(Keycode, &values);
        const flags = gen.range_inclusive(u8, modifier.flag_none, modifier.flag_all);

        const subject = Binding.init(value, .{ .flags = @intCast(flags) });

        check_identity(&subject);
        check_match_positive(&subject);

        cases += 1;
    }

    const expected = values.len * (@as(u32, modifier.flag_all) + 1);

    try testing.expectEqual(expected, cases);
}

test "binding ids are unique across every key and modifier combination" {
    var lookup = [_]bool{false} ** id_count_max;
    var seen: u16 = 0;

    inline for (@typeInfo(Keycode).@"enum".fields) |field| {
        const code: Keycode = @enumFromInt(field.value);

        seen += 1;

        var flags: u8 = modifier.flag_none;

        while (flags <= modifier.flag_all) : (flags += 1) {
            const subject = Binding{
                .value = code,
                .modifiers = .{ .flags = @intCast(flags) },
            };

            const id = subject.id();

            try testing.expect(id < lookup.len);
            try testing.expect(!lookup[id]);

            lookup[id] = true;
        }

        try testing.expectEqual(@as(u8, modifier.flag_all) + 1, flags);
    }

    try testing.expectEqual(@as(u16, @typeInfo(Keycode).@"enum".fields.len), seen);
}
