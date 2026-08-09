const std = @import("std");

const platform = @import("platform.zig");

const middleware_base = @import("middleware/base.zig");
const middleware_blocklist = @import("middleware/blocklist.zig");
const middleware_logging = @import("middleware/logging.zig");
const middleware_remap = @import("middleware/remap.zig");

const testing = std.testing;

pub const binding = @import("binding.zig");
pub const character = @import("character.zig");
pub const filter = @import("filter.zig");
pub const keyboard = @import("keyboard.zig");
pub const keycode = @import("keycode.zig");
pub const modifier = @import("modifier.zig");
pub const mouse = @import("mouse.zig");
pub const response = @import("response.zig");
pub const runtime = @import("runtime.zig");
pub const state = @import("state.zig");
pub const sync = @import("sync.zig");

pub const hook = platform.backend.hook;
pub const loop = platform.backend.loop;
pub const time = platform.backend.time;

pub const buffer = struct {
    pub const circular = @import("buffer/circular.zig");
    pub const rolling = @import("buffer/rolling.zig");
};

pub const builder = struct {
    pub const keyboard = @import("builder/keyboard.zig");
    pub const mouse = @import("builder/mouse.zig");
    pub const pattern = @import("builder/pattern.zig");
};

pub const event = struct {
    pub const key = @import("event/key.zig");
    pub const mouse = @import("event/mouse.zig");
};

pub const middleware = struct {
    pub const base = middleware_base;
    pub const blocklist = middleware_blocklist;
    pub const logging = middleware_logging;
    pub const remap = middleware_remap;

    pub const BlockedBinding = middleware_blocklist.BlockedBinding;
    pub const BlockListMiddlewareType = middleware_blocklist.BlockListMiddlewareType;
    pub const LoggingMiddleware = middleware_logging.LoggingMiddleware;
    pub const Mapping = middleware_remap.Mapping;
    pub const Middleware = middleware_base.Middleware;
    pub const Next = middleware_base.Next;
    pub const PipelineType = middleware_base.PipelineType;
    pub const RemapMiddlewareType = middleware_remap.RemapMiddlewareType;
};

pub const registry = struct {
    pub const base = @import("registry/base.zig");
    pub const chord = @import("registry/chord.zig");
    pub const command = @import("registry/command.zig");
    pub const config = @import("registry/config.zig");
    pub const entry = @import("registry/entry.zig");
    pub const key = @import("registry/key.zig");
    pub const macro = @import("registry/macro.zig");
    pub const mouse = @import("registry/mouse.zig");
    pub const oneshot = @import("registry/oneshot.zig");
    pub const repeat = @import("registry/repeat.zig");
    pub const sequence = @import("registry/sequence.zig");
    pub const slot = @import("registry/slot.zig");
    pub const timed = @import("registry/timed.zig");
    pub const timer = @import("registry/timer.zig");
    pub const toggle = @import("registry/toggle.zig");
};

pub const simulate = struct {
    pub const key = platform.backend.simulate.key;
    pub const mouse = platform.backend.simulate.mouse;
    pub const text = platform.backend.simulate.text;

    pub const message = if (platform.capabilities.window_targeted_input)
        platform.backend.message
    else
        unavailable("simulate.message", "window_targeted_input");
};

pub const clipboard = if (platform.capabilities.clipboard)
    platform.backend.clipboard
else
    unavailable("clipboard", "clipboard");

pub const monitor = if (platform.capabilities.monitor_query)
    platform.backend.monitor
else
    unavailable("monitor", "monitor_query");

pub const remote = if (platform.capabilities.remote)
    platform.backend.remote
else
    unavailable("remote", "remote");

pub const window = if (platform.capabilities.window_filter)
    platform.backend.window
else
    unavailable("window", "window_filter");

pub const mock = platform.mock;

pub const capabilities = platform.capabilities;

pub const Action = registry.macro.Action;
pub const Button = simulate.mouse.Button;
pub const Capabilities = platform.Capabilities;
pub const CommandRegistryType = registry.command.CommandRegistryType;
pub const Key = event.key.Key;
pub const KeyboardType = keyboard.KeyboardHookType;
pub const KeyboardConfig = keyboard.Config;
pub const Keycode = keycode.Keycode;
pub const Macro = registry.macro.Macro;
pub const MacroConfig = registry.config.MacroConfig;
pub const MacroRegistryType = registry.macro.MacroRegistryType;
pub const Mode = runtime.Mode;
pub const Modifier = modifier.Set;
pub const Monitor = monitor.Monitor;
pub const MonitorList = monitor.List;
pub const MouseType = mouse.MouseHookType;
pub const MouseButton = event.mouse.Button;
pub const MouseConfig = mouse.Config;
pub const MouseEvent = event.mouse.Mouse;
pub const MouseKind = event.mouse.Kind;
pub const MousePayload = event.mouse.Payload;
pub const MousePosition = event.mouse.Position;
pub const MouseStamp = event.mouse.Stamp;
pub const Mutex = sync.Mutex;
pub const OneShotRegistryType = registry.oneshot.OneShotRegistryType;
pub const Position = monitor.Position;
pub const RepeatConfig = registry.config.RepeatConfig;
pub const RepeatRegistryType = registry.repeat.RepeatRegistryType;
pub const Response = response.Response;
pub const RuntimeOptions = runtime.Options;
pub const Screen = monitor.Screen;
pub const TimedRegistryType = registry.timed.TimedRegistryType;
pub const TimerConfig = registry.config.TimerConfig;
pub const TimerRegistryType = registry.timer.TimerRegistryType;
pub const ToggleConfig = registry.config.ToggleConfig;
pub const ToggleRegistryType = registry.toggle.ToggleRegistryType;
pub const WindowFilter = filter.WindowFilter;

fn unavailable(comptime feature: []const u8, comptime capability: []const u8) noreturn {
    @compileError("nimble: " ++ feature ++ " requires the " ++ capability ++
        " capability, which this backend does not provide");
}

test "the full keyboard hook surface compiles" {
    const Hook = keyboard.KeyboardHookType(.{});

    if (comptime platform.capabilities.clipboard) {
        testing.refAllDecls(Hook);
    }

    try testing.expect(@sizeOf(Hook) > 0);
}

test "a custom config keyboard hook surface compiles" {
    const Hook = keyboard.KeyboardHookType(.{
        .capacity = 16,
        .capacity_chord = 4,
        .pass_injected = true,
    });

    if (comptime platform.capabilities.clipboard) {
        testing.refAllDecls(Hook);
    }

    try testing.expect(@sizeOf(Hook) > 0);
}

test "the full mouse hook surface compiles" {
    const Hook = mouse.MouseHookType(.{});

    if (comptime platform.capabilities.monitor_query) {
        testing.refAllDecls(Hook);
    }

    try testing.expect(@sizeOf(Hook) > 0);
}

test "a custom config mouse hook surface compiles" {
    const Hook = mouse.MouseHookType(.{
        .capacity = 16,
        .pass_injected = false,
    });

    if (comptime platform.capabilities.monitor_query) {
        testing.refAllDecls(Hook);
    }

    try testing.expect(@sizeOf(Hook) > 0);
}
