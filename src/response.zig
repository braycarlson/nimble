const std = @import("std");

pub const variant_count: u8 = 3;
pub const value_max: u8 = 2;

pub const Response = enum(u8) {
    pass = 0,
    consume = 1,
    replace = 2,

    pub fn from_bool(is_block: bool) Response {
        std.debug.assert(value_max >= 1);

        const result: Response = if (is_block) .consume else .pass;

        std.debug.assert(result.is_valid());
        std.debug.assert(result.should_block() == is_block);

        return result;
    }

    pub fn is_valid(self: Response) bool {
        const value = @intFromEnum(self);

        std.debug.assert(value <= 255);
        std.debug.assert(variant_count == 3);

        const result = value <= value_max;

        return result;
    }

    pub fn should_block(self: Response) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromEnum(self) <= value_max);

        const is_consume = self == .consume;
        const is_replace = self == .replace;
        const result = is_consume or is_replace;

        std.debug.assert(result == (self != .pass));

        return result;
    }
};
