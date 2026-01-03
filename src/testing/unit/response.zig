const std = @import("std");
const input = @import("input");

const response_mod = input.response;
const Response = response_mod.Response;

const testing = std.testing;

test "Response.is_valid" {
    try testing.expect(Response.pass.is_valid());
    try testing.expect(Response.consume.is_valid());
    try testing.expect(Response.replace.is_valid());
}

test "Response.should_block" {
    try testing.expect(!Response.pass.should_block());
    try testing.expect(Response.consume.should_block());
    try testing.expect(Response.replace.should_block());
}

test "Response.from_bool" {
    try testing.expectEqual(Response.pass, Response.from_bool(false));
    try testing.expectEqual(Response.consume, Response.from_bool(true));
}

test "Response enum values" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(Response.pass));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(Response.consume));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(Response.replace));
}

test "Response.should_block inverse of pass" {
    try testing.expect(Response.pass.should_block() == false);
    try testing.expect(Response.consume.should_block() == true);
    try testing.expect(Response.replace.should_block() == true);
}

test "Response comparison" {
    try testing.expect(Response.pass == Response.pass);
    try testing.expect(Response.consume == Response.consume);
    try testing.expect(Response.replace == Response.replace);
    try testing.expect(Response.pass != Response.consume);
    try testing.expect(Response.consume != Response.replace);
    try testing.expect(Response.pass != Response.replace);
}

test "Response.from_bool consistency" {
    const pass_result = Response.from_bool(false);
    const consume_result = Response.from_bool(true);

    try testing.expect(!pass_result.should_block());
    try testing.expect(consume_result.should_block());
}

test "Response all variants valid" {
    const variants = [_]Response{ Response.pass, Response.consume, Response.replace };

    for (variants) |variant| {
        try testing.expect(variant.is_valid());
    }
}

test "Response blocking variants" {
    const blocking = [_]Response{ Response.consume, Response.replace };
    const non_blocking = [_]Response{Response.pass};

    for (blocking) |variant| {
        try testing.expect(variant.should_block());
    }

    for (non_blocking) |variant| {
        try testing.expect(!variant.should_block());
    }
}
