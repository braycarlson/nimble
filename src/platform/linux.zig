const contract = @import("contract.zig");

pub const capabilities = contract.Capabilities{
    .clipboard = true,
    .injected_flag_exact = false,
    .monitor_query = true,
    .remote = true,
    .window_filter = false,
    .window_targeted_input = false,
};

pub const clipboard = @import("linux/clipboard.zig");
pub const device = @import("linux/device.zig");
pub const evdev = @import("linux/evdev.zig");
pub const hook = @import("linux/hook.zig");
pub const keyboard = @import("linux/keyboard.zig");
pub const keycode = @import("linux/keycode.zig");
pub const loop = @import("linux/loop.zig");
pub const monitor = @import("linux/monitor.zig");
pub const mouse = @import("linux/mouse.zig");
pub const remote = @import("linux/remote/root.zig");
pub const rescue = @import("linux/rescue.zig");
pub const runtime = @import("linux/runtime.zig");
pub const simulate = @import("linux/simulate.zig");
pub const state = @import("linux/state.zig");
pub const time = @import("linux/time.zig");
pub const timer = @import("linux/timer.zig");
pub const uinput = @import("linux/uinput.zig");
