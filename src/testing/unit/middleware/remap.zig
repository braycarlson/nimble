const std = @import("std");
const input = @import("input");

const key_event = input.event.key;
const middleware = input.middleware;
const modifier = input.modifier;
const response = input.response;

const Key = key_event.Key;
const Next = middleware.Next;
const RemapMiddleware = middleware.RemapMiddleware;
const Response = response.Response;

const testing = std.testing;

fn make_key(value: u8, mods: modifier.Set) Key {
    return Key{
        .value = value,
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = mods,
    };
}

const Capture = struct {
    value: u8 = 0,
    flags: u4 = 0,

    fn call(context: *anyopaque, key: *const Key) Response {
        const typed: *Capture = @ptrCast(@alignCast(context));

        typed.value = key.value;
        typed.flags = key.modifiers.to_bits();

        return .pass;
    }
};

test "RemapMiddleware.add rejects invalid from_key" {
    var remap = RemapMiddleware(4).init();

    const result = remap.add(.{
        .from_key = 0x00,
        .from_modifiers = .{},
        .to_key = 'B',
        .to_modifiers = .{},
    });

    try testing.expectError(error.InvalidKey, result);
    try testing.expectEqual(@as(u32, 0), remap.count);
}

test "RemapMiddleware.add rejects invalid to_key" {
    var remap = RemapMiddleware(4).init();

    const result = remap.add(.{
        .from_key = 'A',
        .from_modifiers = .{},
        .to_key = 0xFF,
        .to_modifiers = .{},
    });

    try testing.expectError(error.InvalidKey, result);
    try testing.expectEqual(@as(u32, 0), remap.count);
}

test "RemapMiddleware.add valid mapping" {
    var remap = RemapMiddleware(4).init();

    const slot = try remap.add(.{
        .from_key = 'A',
        .from_modifiers = .{},
        .to_key = 'B',
        .to_modifiers = .{},
    });

    try testing.expectEqual(@as(u32, 0), slot);
    try testing.expectEqual(@as(u32, 1), remap.count);
}

test "RemapMiddleware.process remaps matching key" {
    var remap = RemapMiddleware(4).init();

    _ = try remap.add(.{
        .from_key = 'A',
        .from_modifiers = .{},
        .to_key = 'B',
        .to_modifiers = modifier.Set.from(.{ .ctrl = true }),
    });

    var capture = Capture{};

    const next = Next{
        .context = &capture,
        .call = Capture.call,
    };

    const key = make_key('A', .{});
    const result = remap.process(&key, &next);

    try testing.expectEqual(Response.pass, result);
    try testing.expectEqual(@as(u8, 'B'), capture.value);
    try testing.expectEqual(input.modifier.flag_ctrl, capture.flags);
}

test "RemapMiddleware.process passes unmatched key" {
    var remap = RemapMiddleware(4).init();

    _ = try remap.add(.{
        .from_key = 'A',
        .from_modifiers = .{},
        .to_key = 'B',
        .to_modifiers = .{},
    });

    var capture = Capture{};

    const next = Next{
        .context = &capture,
        .call = Capture.call,
    };

    const key = make_key('C', .{});
    const result = remap.process(&key, &next);

    try testing.expectEqual(Response.pass, result);
    try testing.expectEqual(@as(u8, 'C'), capture.value);
}

test "RemapMiddleware.remove keeps other slots stable" {
    var remap = RemapMiddleware(4).init();

    const first_slot = try remap.add(.{
        .from_key = 'A',
        .from_modifiers = .{},
        .to_key = 'B',
        .to_modifiers = .{},
    });

    const second_slot = try remap.add(.{
        .from_key = 'C',
        .from_modifiers = .{},
        .to_key = 'D',
        .to_modifiers = .{},
    });

    try remap.remove(first_slot);
    try remap.remove(second_slot);

    try testing.expectEqual(@as(u32, 0), remap.count);
    try testing.expectError(error.NotFound, remap.remove(second_slot));
}
