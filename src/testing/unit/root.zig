const std = @import("std");

pub const automation = struct {
    pub const config = @import("automation/config.zig");
    pub const macro = @import("automation/macro.zig");
    pub const oneshot = @import("automation/oneshot.zig");
    pub const repeat = @import("automation/repeat.zig");
    pub const timed = @import("automation/timed.zig");
    pub const toggle = @import("automation/toggle.zig");
};

pub const buffer = struct {
    pub const circular = @import("buffer/circular.zig");
    pub const rolling = @import("buffer/rolling.zig");
};

pub const builder = struct {
    pub const pattern = @import("builder/pattern.zig");
};

pub const event = struct {
    pub const key = @import("event/key.zig");
    pub const mouse = @import("event/mouse.zig");
};

pub const middleware = struct {
    pub const base = @import("middleware/base.zig");
    pub const blocklist = @import("middleware/blocklist.zig");
    pub const logging = @import("middleware/logging.zig");
    pub const remap = @import("middleware/remap.zig");
};

pub const registry = struct {
    pub const base = @import("registry/base.zig");
    pub const chord = @import("registry/chord.zig");
    pub const command = @import("registry/command.zig");
    pub const entry = @import("registry/entry.zig");
    pub const key = @import("registry/key.zig");
    pub const mouse = @import("registry/mouse.zig");
    pub const slot = @import("registry/slot.zig");
    pub const timer = @import("registry/timer.zig");
};

pub const binding = @import("binding.zig");
pub const character = @import("character.zig");
pub const event_root = @import("event.zig");
pub const filter = @import("filter.zig");
pub const hook = @import("hook.zig");
pub const keycode = @import("keycode.zig");
pub const modifier = @import("modifier.zig");
pub const response = @import("response.zig");
pub const root = @import("root.zig");
pub const state = @import("state.zig");
pub const timer = @import("timer.zig");

test {
    _ = automation.config;
    _ = automation.macro;
    _ = automation.oneshot;
    _ = automation.repeat;
    _ = automation.timed;
    _ = automation.toggle;

    _ = buffer.circular;
    _ = buffer.rolling;

    _ = builder.pattern;

    _ = event.key;
    _ = event.mouse;

    _ = registry.base;
    _ = registry.chord;
    _ = registry.command;
    _ = registry.entry;
    _ = registry.key;
    _ = registry.mouse;
    _ = registry.slot;
    _ = registry.timer;

    _ = binding;
    _ = character;
    _ = event_root;
    _ = filter;
    _ = hook;
    _ = keycode;
    _ = modifier;
    _ = response;
    _ = root;
    _ = state;
    _ = timer;
}
