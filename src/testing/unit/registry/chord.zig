const std = @import("std");
const input = @import("input");

const chord_mod = input.registry.chord;
const key_event = input.event.key;
const modifier = input.modifier;
const response_mod = input.response;

const ChordKey = chord_mod.ChordKey;
const Key = key_event.Key;
const Response = response_mod.Response;

const testing = std.testing;

fn make_test_key(value: u8) Key {
    return Key{
        .value = value,
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = modifier.Set{},
    };
}

const CountContext = struct {
    count: u32 = 0,

    fn callback(context: *anyopaque) Response {
        const self: *CountContext = @ptrCast(@alignCast(context));
        self.count += 1;
        return .consume;
    }
};

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

test "ChordRegistry: completes ordered sequence" {
    var reg = chord_mod.ChordRegistry(4).init();
    var context = CountContext{};

    _ = try reg.register("ab", CountContext.callback, &context, .{});

    const key_a = make_test_key('A');
    const key_b = make_test_key('B');

    try testing.expect(reg.process(&key_a, 1000) == null);

    const response = reg.process(&key_b, 1010);

    try testing.expect(response != null);
    try testing.expectEqual(Response.consume, response.?);
    try testing.expectEqual(@as(u32, 1), context.count);
}

test "ChordRegistry: non-matching key resets progress" {
    var reg = chord_mod.ChordRegistry(4).init();
    var context = CountContext{};

    _ = try reg.register("ab", CountContext.callback, &context, .{});

    const key_a = make_test_key('A');
    const key_x = make_test_key('X');
    const key_b = make_test_key('B');

    try testing.expect(reg.process(&key_a, 1000) == null);
    try testing.expect(reg.process(&key_x, 1010) == null);
    try testing.expect(reg.process(&key_b, 1020) == null);
    try testing.expectEqual(@as(u32, 0), context.count);
}

test "ChordRegistry: sequence restarts after reset" {
    var reg = chord_mod.ChordRegistry(4).init();
    var context = CountContext{};

    _ = try reg.register("ab", CountContext.callback, &context, .{});

    const key_a = make_test_key('A');
    const key_x = make_test_key('X');
    const key_b = make_test_key('B');

    try testing.expect(reg.process(&key_a, 1000) == null);
    try testing.expect(reg.process(&key_x, 1010) == null);
    try testing.expect(reg.process(&key_a, 1020) == null);

    const response = reg.process(&key_b, 1030);

    try testing.expect(response != null);
    try testing.expectEqual(@as(u32, 1), context.count);
}

test "ChordRegistry: register rejects invalid byte" {
    var reg = chord_mod.ChordRegistry(4).init();
    var context = CountContext{};

    const sequence_low = [_]u8{ 'a', 0x00 };

    try testing.expectError(
        error.InvalidSequence,
        reg.register(&sequence_low, CountContext.callback, &context, .{}),
    );

    const sequence_high = [_]u8{ 0xFF, 'b' };

    try testing.expectError(
        error.InvalidSequence,
        reg.register(&sequence_high, CountContext.callback, &context, .{}),
    );

    try testing.expectEqual(@as(u32, 0), reg.base.count());
}
