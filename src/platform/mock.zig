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
pub const hook = @import("mock/hook.zig");
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
