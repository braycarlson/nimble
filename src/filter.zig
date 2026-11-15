const std = @import("std");

const platform = @import("platform.zig");

pub const window = @import("filter/window.zig");

pub const WindowFilter = window.WindowFilter;

pub fn require(comptime capabilities: platform.Capabilities) void {
    if (!capabilities.window_filter) {
        @compileError("nimble: window filtering requires the window_filter capability, " ++
            "which this backend does not provide");
    }
}

const testing = std.testing;

test "a default window filter never narrows a binding" {
    const everywhere = WindowFilter{};

    try testing.expect(everywhere.is_valid());
    try testing.expect(!everywhere.is_active());
}

test "every backend keeps the same filter type in its registries" {
    try testing.expectEqual(window.WindowFilter, WindowFilter);
    try testing.expect(@sizeOf(WindowFilter) > 0);
}
