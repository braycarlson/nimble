const contract = @import("contract.zig");

pub const capabilities = contract.Capabilities{
    .clipboard = true,
    .injected_flag_exact = true,
    .monitor_query = true,
    .remote = true,
    .window_filter = true,
    .window_targeted_input = true,
};

pub const clipboard = @import("windows/clipboard.zig");
pub const event = @import("windows/event.zig");
pub const hook = @import("windows/hook.zig");
pub const keyboard = @import("windows/keyboard.zig");
pub const keycode = @import("windows/keycode.zig");
pub const loop = @import("windows/loop.zig");
pub const monitor = @import("windows/monitor.zig");
pub const mouse = @import("windows/mouse.zig");
pub const remote = @import("windows/remote.zig");
pub const runtime = @import("windows/runtime.zig");
pub const simulate = @import("windows/simulate.zig");
pub const state = @import("windows/state.zig");
pub const time = @import("windows/time.zig");
pub const timer = @import("windows/timer.zig");
pub const window = @import("windows/window.zig");

pub const message = simulate.message;
