const std = @import("std");
const input = @import("input");

const sequence = input.registry.sequence;

const testing = std.testing;

fn noop_callback(_: *anyopaque) void {}

const CountContext = struct {
    count: u32 = 0,

    fn callback(context: *anyopaque) void {
        const self: *CountContext = @ptrCast(@alignCast(context));
        self.count += 1;
    }
};

test "SequenceRegistry: register valid pattern" {
    var reg = sequence.SequenceRegistry(8).init();
    var context: u8 = 0;

    const id = try reg.register("abc", noop_callback, &context, .{});

    try testing.expect(id >= 1);
    try testing.expectEqual(@as(u32, 1), reg.base.count());
    try testing.expect(reg.is_valid());
}

test "SequenceRegistry: invalid char returns error and does not leak count" {
    var reg = sequence.SequenceRegistry(4).init();
    var context: u8 = 0;

    try testing.expectError(error.InvalidCharacter, reg.register("a1b", noop_callback, &context, .{}));

    try testing.expectEqual(@as(u32, 0), reg.base.count());
    try testing.expect(reg.is_valid());
}

test "SequenceRegistry: repeated invalid registers leave capacity intact" {
    var reg = sequence.SequenceRegistry(4).init();
    var context: u8 = 0;

    for (0..16) |_| {
        try testing.expectError(error.InvalidCharacter, reg.register("9", noop_callback, &context, .{}));
    }

    try testing.expectEqual(@as(u32, 0), reg.base.count());

    _ = try reg.register("aa", noop_callback, &context, .{});
    _ = try reg.register("bb", noop_callback, &context, .{});
    _ = try reg.register("cc", noop_callback, &context, .{});
    _ = try reg.register("dd", noop_callback, &context, .{});

    try testing.expectEqual(@as(u32, 4), reg.base.count());
    try testing.expectError(error.RegistryFull, reg.register("ee", noop_callback, &context, .{}));
}

test "SequenceRegistry: matches exact pattern" {
    var reg = sequence.SequenceRegistry(4).init();
    var context = CountContext{};

    _ = try reg.register("abc", CountContext.callback, &context, .{});

    try testing.expect(!reg.process('A', false));
    try testing.expect(!reg.process('B', false));
    try testing.expect(reg.process('C', false));
    try testing.expectEqual(@as(u32, 1), context.count);
}

test "SequenceRegistry: KMP repeated prefix pattern AAB matches AAAB" {
    var reg = sequence.SequenceRegistry(4).init();
    var context = CountContext{};

    _ = try reg.register("AAB", CountContext.callback, &context, .{});

    try testing.expect(!reg.process('A', false));
    try testing.expect(!reg.process('A', false));
    try testing.expect(!reg.process('A', false));
    try testing.expect(reg.process('B', false));
    try testing.expectEqual(@as(u32, 1), context.count);
}

test "SequenceRegistry: KMP repeated prefix pattern AABAA with overlapping input" {
    var reg = sequence.SequenceRegistry(4).init();
    var context = CountContext{};

    _ = try reg.register("AABAA", CountContext.callback, &context, .{});

    try testing.expect(!reg.process('A', false));
    try testing.expect(!reg.process('A', false));
    try testing.expect(!reg.process('A', false));
    try testing.expect(!reg.process('B', false));
    try testing.expect(!reg.process('A', false));
    try testing.expect(reg.process('A', false));
    try testing.expectEqual(@as(u32, 1), context.count);
}

test "SequenceRegistry: non-alpha input resets progress" {
    var reg = sequence.SequenceRegistry(4).init();
    var context = CountContext{};

    _ = try reg.register("ab", CountContext.callback, &context, .{});

    try testing.expect(!reg.process('A', false));
    try testing.expect(!reg.process('1', false));
    try testing.expect(!reg.process('B', false));
    try testing.expectEqual(@as(u32, 0), context.count);
}
