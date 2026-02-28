pub const event = struct {
    pub const key = @import("event/key.zig");
    pub const mouse = @import("event/mouse.zig");
};

pub const simulate = struct {
    pub const key = @import("simulate/key.zig");
    pub const mouse = @import("simulate/mouse.zig");
    pub const text = @import("simulate/text.zig");
    pub const message = @import("simulate/message.zig");
};

pub const registry = struct {
    pub const base = @import("registry/base.zig");
    pub const entry = @import("registry/entry.zig");
    pub const slot = @import("registry/slot.zig");
    pub const key = @import("registry/key.zig");
    pub const mouse = @import("registry/mouse.zig");
    pub const chord = @import("registry/chord.zig");
    pub const sequence = @import("registry/sequence.zig");
    pub const timer = @import("registry/timer.zig");
    pub const command = @import("registry/command.zig");
    pub const macro = @import("registry/macro.zig");
    pub const repeat = @import("registry/repeat.zig");
    pub const toggle = @import("registry/toggle.zig");
    pub const timed = @import("registry/timed.zig");
    pub const oneshot = @import("registry/oneshot.zig");
    pub const config = @import("registry/config.zig");
};

pub const builder = struct {
    pub const pattern = @import("builder/pattern.zig");
    pub const keyboard = @import("builder/keyboard.zig");
    pub const mouse = @import("builder/mouse.zig");
};

const middleware_base = @import("middleware/base.zig");
const middleware_logging = @import("middleware/logging.zig");
const middleware_remap = @import("middleware/remap.zig");
const middleware_blocklist = @import("middleware/blocklist.zig");

pub const middleware = struct {
    pub const base = middleware_base;
    pub const logging = middleware_logging;
    pub const remap = middleware_remap;
    pub const blocklist = middleware_blocklist;

    pub const Middleware = middleware_base.Middleware;
    pub const Pipeline = middleware_base.Pipeline;
    pub const Next = middleware_base.Next;
    pub const LoggingMiddleware = middleware_logging.LoggingMiddleware;
    pub const RemapMiddleware = middleware_remap.RemapMiddleware;
    pub const BlockListMiddleware = middleware_blocklist.BlockListMiddleware;
    pub const BlockedBinding = middleware_blocklist.BlockedBinding;
    pub const Mapping = middleware_remap.Mapping;
};

pub const buffer = struct {
    pub const circular = @import("buffer/circular.zig");
    pub const rolling = @import("buffer/rolling.zig");
};

pub const keyboard = @import("keyboard.zig");
pub const mouse = @import("mouse.zig");
pub const keycode = @import("keycode.zig");
pub const modifier = @import("modifier.zig");
pub const response = @import("response.zig");
pub const filter = @import("filter.zig");
pub const state = @import("state.zig");
pub const hook = @import("hook.zig");
pub const clipboard = @import("clipboard.zig");
pub const monitor = @import("monitor.zig");
pub const binding = @import("binding.zig");
pub const character = @import("character.zig");

pub const Keyboard = keyboard.KeyboardHook;
pub const KeyboardConfig = keyboard.Config;

pub const Mouse = mouse.MouseHook;
pub const MouseConfig = mouse.Config;

pub const Response = response.Response;
pub const WindowFilter = filter.WindowFilter;
pub const Modifier = modifier.Set;

pub const Key = event.key.Key;
pub const MouseEvent = event.mouse.Mouse;
pub const MouseKind = event.mouse.Kind;

pub const CommandRegistry = registry.command.CommandRegistry;
pub const TimerRegistry = registry.timer.TimerRegistry;

pub const Position = monitor.Position;
pub const Screen = monitor.Screen;
pub const Button = simulate.mouse.Button;
pub const Monitor = monitor.Monitor;
pub const MonitorList = monitor.List;

pub const OneShotRegistry = registry.oneshot.OneShotRegistry;
pub const MacroRegistry = registry.macro.MacroRegistry;
pub const Macro = registry.macro.Macro;
pub const Action = registry.macro.Action;
pub const RepeatRegistry = registry.repeat.RepeatRegistry;
pub const TimedRegistry = registry.timed.TimedRegistry;
pub const ToggleRegistry = registry.toggle.ToggleRegistry;

pub const RepeatConfig = registry.config.RepeatConfig;
pub const TimerConfig = registry.config.TimerConfig;
pub const ToggleConfig = registry.config.ToggleConfig;
pub const MacroConfig = registry.config.MacroConfig;
