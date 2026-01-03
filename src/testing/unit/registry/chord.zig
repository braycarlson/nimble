const std = @import("std");
const input = @import("input");

const chord_mod = input.registry.chord;
const key_event = input.event.key;
const modifier = input.modifier;

const ChordKey = chord_mod.ChordKey;
const Key = key_event.Key;

const testing = std.testing;

test "ChordKey default" {
    const ck = ChordKey{};

    try testing.expectEqual(@as(u8, 0), ck.value);
    try testing.expect(ck.modifiers.none());
}

test "ChordKey.is_valid" {
    const valid = ChordKey{ .value = 'A', .modifiers = modifier.Set{} };
    const invalid_low = ChordKey{ .value = 0x00, .modifiers = modifier.Set{} };
    const invalid_high = ChordKey{ .value = 0xFF, .modifiers = modifier.Set{} };

    try testing.expect(valid.is_valid());
    try testing.expect(!invalid_low.is_valid());
    try testing.expect(!invalid_high.is_valid());
}

test "ChordKey.is_valid with modifiers" {
    const ck = ChordKey{
        .value = 'B',
        .modifiers = modifier.Set.from(.{ .ctrl = true, .alt = true }),
    };

    try testing.expect(ck.is_valid());
}

test "ChordKey.matches same value no modifiers" {
    const ck = ChordKey{ .value = 'A', .modifiers = modifier.Set{} };
    const key = Key{
        .value = 'A',
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = modifier.Set{},
    };

    try testing.expect(ck.matches(&key));
}

test "ChordKey.matches same value with modifiers" {
    const ck = ChordKey{
        .value = 'A',
        .modifiers = modifier.Set.from(.{ .ctrl = true }),
    };
    const key = Key{
        .value = 'A',
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = modifier.Set.from(.{ .ctrl = true }),
    };

    try testing.expect(ck.matches(&key));
}

test "ChordKey.matches different value" {
    const ck = ChordKey{ .value = 'A', .modifiers = modifier.Set{} };
    const key = Key{
        .value = 'B',
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = modifier.Set{},
    };

    try testing.expect(!ck.matches(&key));
}

test "ChordKey.matches different modifiers" {
    const ck = ChordKey{
        .value = 'A',
        .modifiers = modifier.Set.from(.{ .ctrl = true }),
    };
    const key = Key{
        .value = 'A',
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = modifier.Set.from(.{ .alt = true }),
    };

    try testing.expect(!ck.matches(&key));
}

test "ChordKey.matches_value same" {
    const ck = ChordKey{ .value = 'X', .modifiers = modifier.Set{} };
    const key = Key{
        .value = 'X',
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = modifier.Set.from(.{ .ctrl = true }),
    };

    try testing.expect(ck.matches_value(&key));
}

test "ChordKey.matches_value different" {
    const ck = ChordKey{ .value = 'X', .modifiers = modifier.Set{} };
    const key = Key{
        .value = 'Y',
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = modifier.Set{},
    };

    try testing.expect(!ck.matches_value(&key));
}

test "ChordKey.matches_value ignores modifiers" {
    const ck = ChordKey{
        .value = 'Z',
        .modifiers = modifier.Set.from(.{ .shift = true }),
    };
    const key = Key{
        .value = 'Z',
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = modifier.Set{},
    };

    try testing.expect(ck.matches_value(&key));
}

test "chord constants" {
    try testing.expect(chord_mod.sequence_max >= 2);
    try testing.expect(chord_mod.sequence_max <= 16);
    try testing.expect(chord_mod.timeout_min_ms <= chord_mod.timeout_default_ms);
    try testing.expect(chord_mod.timeout_default_ms <= chord_mod.timeout_max_ms);
    try testing.expect(chord_mod.capacity_default <= chord_mod.capacity_max);
}
