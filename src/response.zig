const std = @import("std");

const assert = std.debug.assert;

const variant_count: u8 = 2;
const value_max: u8 = 1;

pub const Response = enum(u8) {
    pass = 0,
    consume = 1,

    pub fn is_valid(response: Response) bool {
        const value = @backingInt(response);

        comptime assert(@typeInfo(Response).@"enum".field_names.len == variant_count);

        return value <= value_max;
    }

    pub fn should_block(response: Response) bool {
        assert(response.is_valid());

        return response == .consume;
    }
};

const testing = std.testing;

test Response {
    const verdict: Response = .consume;

    try testing.expect(verdict.should_block());
    try testing.expect(!Response.pass.should_block());
}

test "a response reports whether it is valid" {
    try testing.expect(Response.pass.is_valid());
    try testing.expect(Response.consume.is_valid());
}

test "the response values are stable" {
    try testing.expectEqual(@as(u8, 0), @backingInt(Response.pass));
    try testing.expectEqual(@as(u8, 1), @backingInt(Response.consume));
}

test "every response variant is valid" {
    for (std.enums.values(Response)) |variant| {
        try testing.expect(variant.is_valid());
    }
}
