const std = @import("std");
const input = @import("input");

const key_event = input.event.key;
const middleware = input.middleware;
const modifier = input.modifier;
const response = input.response;

const Key = key_event.Key;
const Next = middleware.Next;
const BlockListMiddleware = middleware.BlockListMiddleware;
const Response = response.Response;

const testing = std.testing;

fn make_key(value: u8, down: bool) Key {
    return Key{
        .value = value,
        .scan = 0,
        .down = down,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = .{},
    };
}

fn pass_call(_: *anyopaque, key: *const Key) Response {
    std.debug.assert(key.is_valid());

    return .pass;
}

var next_context: u8 = 0;

fn make_next() Next {
    return Next{
        .context = &next_context,
        .call = pass_call,
    };
}

test "BlockListMiddleware.process consumes blocked key" {
    var blocklist = BlockListMiddleware(4).init();

    _ = try blocklist.add(.{ .key = 'A', .modifiers = .{} });

    const next = make_next();
    const key = make_key('A', true);

    try testing.expectEqual(Response.consume, blocklist.process(&key, &next));
}

test "BlockListMiddleware.process passes unblocked key" {
    var blocklist = BlockListMiddleware(4).init();

    _ = try blocklist.add(.{ .key = 'A', .modifiers = .{} });

    const next = make_next();
    const key = make_key('B', true);

    try testing.expectEqual(Response.pass, blocklist.process(&key, &next));
}

test "BlockListMiddleware.process passes key up" {
    var blocklist = BlockListMiddleware(4).init();

    _ = try blocklist.add(.{ .key = 'A', .modifiers = .{} });

    const next = make_next();
    const key = make_key('A', false);

    try testing.expectEqual(Response.pass, blocklist.process(&key, &next));
}

test "BlockListMiddleware.process passes when disabled" {
    var blocklist = BlockListMiddleware(4).init();

    _ = try blocklist.add(.{ .key = 'A', .modifiers = .{} });

    blocklist.set_enabled(false);

    const next = make_next();
    const key = make_key('A', true);

    try testing.expectEqual(Response.pass, blocklist.process(&key, &next));
    try testing.expect(!blocklist.is_enabled());
}

test "BlockListMiddleware.remove unblocks key" {
    var blocklist = BlockListMiddleware(4).init();

    const slot = try blocklist.add(.{ .key = 'A', .modifiers = .{} });

    try blocklist.remove(slot);

    const next = make_next();
    const key = make_key('A', true);

    try testing.expectEqual(Response.pass, blocklist.process(&key, &next));
    try testing.expectError(error.NotFound, blocklist.remove(slot));
}
