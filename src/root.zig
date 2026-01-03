const std = @import("std");

pub const automation = @import("automation/root.zig");
pub const buffer = @import("buffer/root.zig");
pub const builder = @import("builder/root.zig");
pub const event = @import("event/root.zig");
pub const keyboard = @import("keyboard/root.zig");
pub const middleware = @import("middleware/root.zig");
pub const monitor = @import("monitor.zig");
pub const mouse = @import("mouse/root.zig");
pub const registry = @import("registry/root.zig");
pub const sender = @import("sender/root.zig");

pub const binding = @import("binding.zig");
pub const character = @import("character.zig");
pub const clipboard = @import("clipboard.zig");
pub const keycode = @import("keycode.zig");
pub const command = @import("registry/command.zig");
pub const filter = @import("filter.zig");
pub const hook = @import("hook.zig");
pub const modifier = @import("modifier.zig");
pub const response = @import("response.zig");
pub const circular = @import("buffer/circular.zig");
pub const rolling = @import("buffer/rolling.zig");
pub const state = @import("state.zig");
pub const timer = @import("timer.zig");
pub const typer = @import("sender/typer.zig");

pub const Keyboard = keyboard.KeyboardHook;
pub const KeyboardConfig = keyboard.Config;

pub const Mouse = mouse.MouseHook;
pub const MouseConfig = mouse.Config;

pub const Response = response.Response;
pub const WindowFilter = filter.WindowFilter;
pub const Modifier = modifier.Set;

pub const Key = event.Key;
pub const MouseEvent = event.Mouse;
pub const MouseKind = event.MouseKind;

pub const CommandRegistry = command.CommandRegistry;
pub const TimerRegistry = timer.TimerRegistry;

pub const Position = monitor.Position;
pub const Screen = monitor.Screen;
pub const Button = sender.Button;
pub const Monitor = monitor.Monitor;
pub const MonitorList = monitor.List;

pub const OneShotRegistry = automation.OneShotRegistry;
pub const MacroRegistry = automation.MacroRegistry;
pub const Macro = automation.Macro;
pub const Action = automation.Action;
pub const RepeatRegistry = automation.RepeatRegistry;
pub const TimedRegistry = automation.TimedRegistry;
pub const ToggleRegistry = automation.ToggleRegistry;

pub const RepeatConfig = builder.RepeatConfig;
pub const TimerConfig = builder.TimerConfig;
pub const ToggleConfig = builder.ToggleConfig;
pub const MacroConfig = builder.MacroConfig;
