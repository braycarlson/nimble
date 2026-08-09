const std = @import("std");

const platform = @import("platform.zig");

pub const supported: bool = platform.capabilities.window_filter;

pub const Inert = struct {
    pub fn is_valid(_: *const Inert) bool {
        return true;
    }

    pub fn is_active(_: *const Inert) bool {
        return false;
    }

    pub fn matches(_: *const Inert) bool {
        return true;
    }
};

pub const Active = if (supported) @import("filter/window.zig").WindowFilter else Inert;

pub const WindowFilter = if (supported)
    @import("filter/window.zig").WindowFilter
else
    unavailable("WindowFilter", "window_filter");

pub fn require() void {
    if (!supported) {
        @compileError("nimble: window filtering requires the window_filter capability, " ++
            "which this backend does not provide");
    }
}

fn unavailable(comptime feature: []const u8, comptime capability: []const u8) noreturn {
    @compileError("nimble: " ++ feature ++ " requires the " ++ capability ++
        " capability, which this backend does not provide");
}

const testing = std.testing;

test "an inert filter never narrows a binding" {
    const inert = Inert{};

    try testing.expect(inert.is_valid());
    try testing.expect(!inert.is_active());
    try testing.expect(inert.matches());
    try testing.expectEqual(@as(usize, 0), @sizeOf(Inert));
}

test "the active filter follows the backend capability" {
    if (comptime supported) {
        try testing.expect(Active != Inert);
    } else {
        try testing.expectEqual(Inert, Active);
    }
}
