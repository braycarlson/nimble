const std = @import("std");

const assert = std.debug.assert;

pub const kind_max: u8 = 1;
pub const kind_count: u8 = 2;

pub const Kind = enum(u8) {
    keyboard = 0,
    mouse = 1,

    pub fn is_valid(kind: Kind) bool {
        const value = @intFromEnum(kind);

        assert(kind_max == 1);
        assert(kind_count == 2);

        return value <= kind_max;
    }
};

pub const Hook = struct {
    kind: Kind,
    installed: bool = true,

    pub fn install(kind: Kind) Hook {
        assert(kind.is_valid());

        return Hook{ .kind = kind };
    }

    pub fn is_valid(hook: *const Hook) bool {
        return hook.kind.is_valid();
    }

    pub fn remove(hook: *const Hook) bool {
        assert(hook.is_valid());

        return hook.installed;
    }
};
