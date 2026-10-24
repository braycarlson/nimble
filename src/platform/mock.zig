const std = @import("std");

const contract = @import("contract.zig");

pub const capabilities = contract.Capabilities{
    .clipboard = true,
    .injected_flag_exact = true,
    .monitor_query = true,
    .remote = true,
    .window_filter = true,
    .window_targeted_input = true,
};

pub const clipboard = @import("mock/clipboard.zig");
pub const keyboard = @import("mock/keyboard.zig");
pub const keycode = @import("mock/keycode.zig");
pub const loop = @import("mock/loop.zig");
pub const monitor = @import("mock/monitor.zig");
pub const mouse = @import("mock/mouse.zig");
pub const remote = @import("mock/remote.zig");
pub const record = @import("mock/record.zig");
pub const runtime = @import("mock/runtime.zig");
pub const simulate = @import("mock/simulate.zig");
pub const state = @import("mock/state.zig");
pub const time = @import("mock/time.zig");
pub const timer = @import("mock/timer.zig");
pub const window = @import("mock/window.zig");

pub const message = simulate.message;

pub fn reset() void {
    clipboard.reset();
    keyboard.reset();
    loop.reset();
    monitor.reset();
    mouse.reset();
    record.reset();
    runtime.reset();
    state.reset();
    time.reset();
    timer.reset();
    window.reset();
}

const testing = std.testing;

test reset {
    runtime.close();
    record.push(.{ .kind = .key_press, .code = .a });
    monitor.set_cursor_position(.{ .x = 40, .y = 30 });
    time.advance(500);

    try runtime.open(.{});

    reset();

    try testing.expectEqual(@as(u16, 0), record.len());
    try testing.expect(monitor.get_cursor_position().eql(.zero));
    try testing.expectEqual(@as(i64, 0), time.now_ms());
    try testing.expect(!runtime.is_open());
}
