const std = @import("std");

const assert = std.debug.assert;

pub const variant_count: u8 = 3;
pub const value_max: u8 = 2;

pub const Response = enum(u8) {
    pass = 0,
    consume = 1,
    replace = 2,

    pub fn from_bool(is_block: bool) Response {
        assert(value_max >= 1);

        const result: Response = if (is_block) .consume else .pass;

        assert(result.is_valid());
        assert(result.should_block() == is_block);

        return result;
    }

    pub fn is_valid(response: Response) bool {
        const value = @intFromEnum(response);

        comptime assert(@typeInfo(Response).@"enum".fields.len == variant_count);

        return value <= value_max;
    }

    pub fn should_block(response: Response) bool {
        assert(response.is_valid());

        const is_consume = response == .consume;
        const is_replace = response == .replace;
        const result = is_consume or is_replace;

        assert(result == (response != .pass));

        return result;
    }
};

const testing = std.testing;

test "a response reports whether it is valid" {
    try testing.expect(Response.pass.is_valid());
    try testing.expect(Response.consume.is_valid());
    try testing.expect(Response.replace.is_valid());
}

test "a response reports whether it blocks the event" {
    try testing.expect(!Response.pass.should_block());
    try testing.expect(Response.consume.should_block());
    try testing.expect(Response.replace.should_block());
}

test "a response is built from a boolean" {
    try testing.expectEqual(Response.pass, Response.from_bool(false));
    try testing.expectEqual(Response.consume, Response.from_bool(true));
}

test "the response values are stable" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(Response.pass));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(Response.consume));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(Response.replace));
}

test "blocking is the inverse of passing" {
    try testing.expect(Response.pass.should_block() == false);
    try testing.expect(Response.consume.should_block() == true);
    try testing.expect(Response.replace.should_block() == true);
}

test "responses compare by value" {
    try testing.expect(Response.pass == Response.pass);
    try testing.expect(Response.consume == Response.consume);
    try testing.expect(Response.replace == Response.replace);
    try testing.expect(Response.pass != Response.consume);
    try testing.expect(Response.consume != Response.replace);
    try testing.expect(Response.pass != Response.replace);
}

test "building from a boolean agrees with blocking" {
    const pass_result = Response.from_bool(false);
    const consume_result = Response.from_bool(true);

    try testing.expect(!pass_result.should_block());
    try testing.expect(consume_result.should_block());
}

test "every response variant is valid" {
    const variants = [_]Response{ Response.pass, Response.consume, Response.replace };

    for (variants) |variant| {
        try testing.expect(variant.is_valid());
    }
}

test "only the blocking responses block" {
    const blocking = [_]Response{ Response.consume, Response.replace };
    const non_blocking = [_]Response{Response.pass};

    for (blocking) |variant| {
        try testing.expect(variant.should_block());
    }

    for (non_blocking) |variant| {
        try testing.expect(!variant.should_block());
    }
}
