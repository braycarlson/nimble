const builtin = @import("builtin");

const interface = @import("platform/interface.zig");

pub const Capabilities = interface.Capabilities;
pub const HookError = interface.HookError;
pub const Mode = interface.Mode;
pub const Options = interface.Options;
pub const ReleaseCallback = interface.ReleaseCallback;
pub const Tick = interface.Tick;
pub const TimerId = interface.TimerId;

pub const Fake = @import("platform/fake.zig");

pub const Native = switch (builtin.target.os.tag) {
    .linux => @import("platform/linux.zig"),
    .windows => @import("platform/windows.zig"),
    else => @compileError("nimble: unsupported target OS"),
};

pub const assert_backend = interface.assert_backend;
pub const sleep_ms_max = interface.sleep_ms_max;
pub const timer_interval_ms_max = interface.timer_interval_ms_max;
pub const timer_interval_ms_min = interface.timer_interval_ms_min;
