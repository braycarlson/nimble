const std = @import("std");

const key_event = @import("../../event/key.zig");
const modifier = @import("../../modifier.zig");
const response_mod = @import("../../response.zig");
const filter_mod = @import("../../filter.zig");
const pattern_mod = @import("../pattern.zig");
const config_mod = @import("../../automation/config.zig");
const macro_mod = @import("../../automation/macro.zig");
const key_registry = @import("../../registry/key.zig");
const timer_mod = @import("../../registry/timer.zig");
const repeat_mod = @import("../../automation/repeat.zig");
const toggle_mod = @import("../../automation/toggle.zig");

const Key = key_event.Key;
const Response = response_mod.Response;
const WindowFilter = filter_mod.WindowFilter;

const RepeatConfig = config_mod.RepeatConfig;
const TimerConfig = config_mod.TimerConfig;
const ToggleConfig = config_mod.ToggleConfig;
const MacroConfig = config_mod.MacroConfig;
const Action = macro_mod.Action;

pub fn BindBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        key: u8,
        modifiers: modifier.Set,
        is_pause_exempt: bool = false,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, comptime pattern: []const u8) Self {
            const parsed = comptime pattern_mod.parse(pattern);

            return Self{
                .hook = h,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
            };
        }

        pub fn pause_exempt(self: Self) Self {
            var result = self;
            result.is_pause_exempt = true;
            return result;
        }

        pub fn with_filter(self: Self, f: WindowFilter) Self {
            var result = self;
            result.filter = f;
            return result;
        }

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), *const Key) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, k: *const Key) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed, k);
                }
            };

            return self.hook.registry.register(
                self.key,
                self.modifiers,
                wrapper.invoke,
                context,
                key_registry.Options{
                    .filter = self.filter,
                    .pause_exempt = self.is_pause_exempt,
                },
            );
        }

        pub fn on_simple(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context)) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, _: *const Key) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed);
                }
            };

            return self.hook.registry.register(
                self.key,
                self.modifiers,
                wrapper.invoke,
                context,
                key_registry.Options{
                    .filter = self.filter,
                    .pause_exempt = self.is_pause_exempt,
                },
            );
        }

        pub fn repeat(self: Self, interval_ms: u32) RepeatChainBuilder(HookType) {
            return RepeatChainBuilder(HookType){
                .hook = self.hook,
                .key = self.key,
                .modifiers = self.modifiers,
                .filter = self.filter,
                .is_pause_exempt = self.is_pause_exempt,
                .interval_ms = interval_ms,
                .initial_delay_ms = 0,
            };
        }

        pub fn timer(self: Self, interval_ms: u32) TimerChainBuilder(HookType) {
            return TimerChainBuilder(HookType){
                .hook = self.hook,
                .key = self.key,
                .modifiers = self.modifiers,
                .filter = self.filter,
                .is_pause_exempt = self.is_pause_exempt,
                .interval_ms = interval_ms,
                .repeating = true,
            };
        }

        pub fn toggle(self: Self, comptime toggle_pattern: []const u8) ToggleChainBuilder(HookType) {
            const toggle_parsed = comptime pattern_mod.parse(toggle_pattern);

            return ToggleChainBuilder(HookType){
                .hook = self.hook,
                .action_key = self.key,
                .action_modifiers = self.modifiers,
                .toggle_key = toggle_parsed.key,
                .toggle_modifiers = toggle_parsed.modifiers,
                .filter = self.filter,
                .is_pause_exempt = self.is_pause_exempt,
            };
        }

        pub fn macro(self: Self, cfg: MacroConfig) MacroChainBuilder(HookType) {
            return MacroChainBuilder(HookType){
                .hook = self.hook,
                .key = self.key,
                .modifiers = self.modifiers,
                .filter = self.filter,
                .is_pause_exempt = self.is_pause_exempt,
                .config = cfg,
            };
        }
    };
}

pub fn RepeatChainBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        key: u8,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,
        interval_ms: u32,
        initial_delay_ms: u32,

        pub fn initial_delay(self: Self, ms: u32) Self {
            var result = self;
            result.initial_delay_ms = ms;
            return result;
        }

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), u32) void,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, count: u32) void {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    callback(typed, count);
                }

                fn pass_through(_: *anyopaque, _: *const Key) Response {
                    return .pass;
                }
            };

            const binding_id = try self.hook.registry.register(
                self.key,
                self.modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = self.filter,
                    .pause_exempt = self.is_pause_exempt,
                },
            );

            return self.hook.repeat_registry.register(
                binding_id,
                wrapper.invoke,
                context,
                repeat_mod.Options{
                    .interval_ms = self.interval_ms,
                    .initial_delay_ms = self.initial_delay_ms,
                },
            );
        }
    };
}

pub fn TimerChainBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        key: u8,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,
        interval_ms: u32,
        repeating: bool,

        pub fn once(self: Self) Self {
            var result = self;
            result.repeating = false;
            return result;
        }

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context)) void,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque) void {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    callback(typed);
                }

                fn pass_through(_: *anyopaque, _: *const Key) Response {
                    return .pass;
                }
            };

            const binding_id = try self.hook.registry.register(
                self.key,
                self.modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = self.filter,
                    .pause_exempt = self.is_pause_exempt,
                },
            );

            return self.hook.timer_registry.register(
                self.interval_ms,
                wrapper.invoke,
                context,
                timer_mod.Options{
                    .binding_id = binding_id,
                    .repeat = self.repeating,
                },
            );
        }
    };
}

pub fn ToggleChainBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        action_key: u8,
        action_modifiers: modifier.Set,
        toggle_key: u8,
        toggle_modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), *const Key) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, k: *const Key) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed, k);
                }

                fn pass_through(_: *anyopaque, _: *const Key) Response {
                    return .pass;
                }
            };

            const action_binding_id = try self.hook.registry.register(
                self.action_key,
                self.action_modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = self.filter,
                    .pause_exempt = self.is_pause_exempt,
                },
            );

            const toggle_binding_id = try self.hook.registry.register(
                self.toggle_key,
                self.toggle_modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = self.filter,
                    .pause_exempt = self.is_pause_exempt,
                },
            );

            return self.hook.toggle_registry.register(
                action_binding_id,
                toggle_binding_id,
                wrapper.invoke,
                context,
                toggle_mod.Options{
                    .filter = self.filter,
                },
            );
        }
    };
}

pub fn MacroChainBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        key: u8,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,
        config: MacroConfig,

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), *const Key) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, k: *const Key) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed, k);
                }
            };

            const macro_id = try self.hook.macro_registry.create(self.config.name);

            if (self.hook.macro_registry.get(macro_id)) |m| {
                var i: u32 = 0;

                while (i < self.config.step_count) : (i += 1) {
                    const step = self.config.steps[i];

                    switch (step.kind) {
                        .text => {
                            if (step.text) |txt| {
                                try m.add_text(txt);
                            }
                        },
                        .line => {
                            if (step.text) |txt| {
                                try m.add_line(txt);
                            }
                        },
                        .key => {
                            try m.add_action(Action{
                                .kind = .key_press,
                                .key = step.key_code,
                                .modifiers = step.key_modifiers,
                            });
                        },
                        .delay => {
                            try m.add_action(Action{
                                .kind = .delay,
                                .delay_ms = step.delay_ms,
                            });
                        },
                    }
                }
            }

            _ = try self.hook.registry.register(
                self.key,
                self.modifiers,
                wrapper.invoke,
                context,
                key_registry.Options{
                    .filter = self.filter,
                    .pause_exempt = self.is_pause_exempt,
                },
            );

            return macro_id;
        }
    };
}
