const std = @import("std");

const key_event = @import("../event/key.zig");
const modifier = @import("../modifier.zig");
const response_mod = @import("../response.zig");
const filter_mod = @import("../filter.zig");
const pattern_mod = @import("pattern.zig");
const config_mod = @import("../registry/config.zig");
const macro_mod = @import("../registry/macro.zig");
const key_registry = @import("../registry/key.zig");
const timer_mod = @import("../registry/timer.zig");
const repeat_mod = @import("../registry/repeat.zig");
const toggle_mod = @import("../registry/toggle.zig");
const timed_mod = @import("../registry/timed.zig");
const chord_registry = @import("../registry/chord.zig");
const sequence_registry = @import("../registry/sequence.zig");

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

pub fn GroupBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        filter: WindowFilter = .{},
        is_pause_exempt: bool = false,

        pub fn init(h: *HookType) Self {
            return Self{ .hook = h };
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

        pub fn bind(self: Self, comptime pattern: []const u8) GroupBindBuilder(HookType) {
            const parsed = comptime pattern_mod.parse(pattern);

            return GroupBindBuilder(HookType){
                .hook = self.hook,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
                .filter = self.filter,
                .is_pause_exempt = self.is_pause_exempt,
            };
        }
    };
}

pub fn GroupBindBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        key: u8,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,

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
    };
}

pub fn OneShotBuilder(comptime HookType: type, comptime RegistryType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        registry: *RegistryType,
        key: u8,
        modifiers: modifier.Set,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, r: *RegistryType, comptime pattern: []const u8) Self {
            const parsed = comptime pattern_mod.parse(pattern);

            return Self{
                .hook = h,
                .registry = r,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
            };
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
                    .pause_exempt = false,
                },
            );

            return self.registry.register(binding_id, wrapper.invoke, context, .{});
        }
    };
}

pub fn TimedBuilder(comptime HookType: type, comptime RegistryType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        registry: *RegistryType,
        key: u8,
        modifiers: modifier.Set,
        duration_ms: u64 = 0,
        max_count: u32 = 0,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, r: *RegistryType, comptime pattern: []const u8) Self {
            const parsed = comptime pattern_mod.parse(pattern);

            return Self{
                .hook = h,
                .registry = r,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
            };
        }

        pub fn duration(self: Self, ms: u64) Self {
            var result = self;
            result.duration_ms = ms;
            return result;
        }

        pub fn count(self: Self, max: u32) Self {
            var result = self;
            result.max_count = max;
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
                    .pause_exempt = false,
                },
            );

            var options = timed_mod.Options{};

            if (self.max_count > 0) {
                options = timed_mod.Options.count(self.max_count);
            } else if (self.duration_ms > 0) {
                options = timed_mod.Options.duration(self.duration_ms);
            } else {
                options = timed_mod.Options.toggle_mode();
            }

            return self.registry.register(binding_id, wrapper.invoke, context, options);
        }
    };
}

pub fn RepeatBuilder(comptime HookType: type, comptime RegistryType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        registry: *RegistryType,
        key: u8,
        modifiers: modifier.Set,
        interval_ms: u32 = 100,
        initial_delay_ms: u32 = 0,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, r: *RegistryType, comptime pattern: []const u8) Self {
            const parsed = comptime pattern_mod.parse(pattern);

            return Self{
                .hook = h,
                .registry = r,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
            };
        }

        pub fn interval(self: Self, ms: u32) Self {
            var result = self;
            result.interval_ms = ms;
            return result;
        }

        pub fn initial_delay(self: Self, ms: u32) Self {
            var result = self;
            result.initial_delay_ms = ms;
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
            comptime callback: fn (@TypeOf(context), u32) void,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, cnt: u32) void {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    callback(typed, cnt);
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
                    .pause_exempt = false,
                },
            );

            return self.registry.register(
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

pub fn ChordBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        sequence: []const u8,
        timeout_ms: u32 = chord_registry.timeout_default_ms,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, sequence: []const u8) Self {
            return Self{
                .hook = h,
                .sequence = sequence,
            };
        }

        pub fn timeout(self: Self, ms: u32) Self {
            var result = self;
            result.timeout_ms = ms;
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
            comptime callback: fn (@TypeOf(context)) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed);
                }
            };

            return self.hook.chord_registry.register(
                self.sequence,
                wrapper.invoke,
                context,
                chord_registry.Options{
                    .timeout_ms = self.timeout_ms,
                    .filter = self.filter,
                },
            );
        }
    };
}

pub fn CommandBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        name: []const u8,

        pub fn init(h: *HookType, name: []const u8) Self {
            return Self{
                .hook = h,
                .name = name,
            };
        }

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), []const u8, []const u8) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, name: []const u8, args: []const u8) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed, name, args);
                }
            };

            return self.hook.command_registry.register(self.name, wrapper.invoke, context);
        }

        pub fn on_simple(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context)) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, _: []const u8, _: []const u8) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed);
                }
            };

            return self.hook.command_registry.register(self.name, wrapper.invoke, context);
        }
    };
}

const MaxSteps = 32;

const StepKind = enum {
    text,
    line,
    key,
    delay,
};

const Step = struct {
    kind: StepKind = .text,
    text: ?[]const u8 = null,
    keycode: u8 = 0,
    key_modifiers: modifier.Set = .{},
    delay_ms: u32 = 0,
};

pub fn MacroBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        name: []const u8,
        steps: [MaxSteps]Step = [_]Step{.{}} ** MaxSteps,
        step_count: u32 = 0,
        binding_key: ?u8 = null,
        binding_modifiers: modifier.Set = .{},
        filter: WindowFilter = .{},
        is_pause_exempt: bool = false,

        pub fn init(h: *HookType, name: []const u8) Self {
            return Self{
                .hook = h,
                .name = name,
            };
        }

        pub fn text(self: Self, txt: []const u8) Self {
            var result = self;
            if (result.step_count < MaxSteps) {
                result.steps[result.step_count] = .{
                    .kind = .text,
                    .text = txt,
                };
                result.step_count += 1;
            }
            return result;
        }

        pub fn line(self: Self, txt: []const u8) Self {
            var result = self;
            if (result.step_count < MaxSteps) {
                result.steps[result.step_count] = .{
                    .kind = .line,
                    .text = txt,
                };
                result.step_count += 1;
            }
            return result;
        }

        pub fn key(self: Self, comptime pattern: []const u8) Self {
            const parsed = comptime pattern_mod.parse(pattern);
            var result = self;
            if (result.step_count < MaxSteps) {
                result.steps[result.step_count] = .{
                    .kind = .key,
                    .keycode = parsed.key,
                    .key_modifiers = parsed.modifiers,
                };
                result.step_count += 1;
            }
            return result;
        }

        pub fn delay(self: Self, ms: u32) Self {
            var result = self;
            if (result.step_count < MaxSteps) {
                result.steps[result.step_count] = .{
                    .kind = .delay,
                    .delay_ms = ms,
                };
                result.step_count += 1;
            }
            return result;
        }

        pub fn bind(self: Self, comptime pattern: []const u8) Self {
            const parsed = comptime pattern_mod.parse(pattern);
            var result = self;
            result.binding_key = parsed.key;
            result.binding_modifiers = parsed.modifiers;
            return result;
        }

        pub fn with_filter(self: Self, f: WindowFilter) Self {
            var result = self;
            result.filter = f;
            return result;
        }

        pub fn pause_exempt(self: Self) Self {
            var result = self;
            result.is_pause_exempt = true;
            return result;
        }

        pub fn create(self: Self) !u32 {
            const macro_id = try self.hook.macro_registry.create(self.name);

            if (self.hook.macro_registry.get(macro_id)) |m| {
                var i: u32 = 0;
                while (i < self.step_count) : (i += 1) {
                    const step = self.steps[i];
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
                                .key = step.keycode,
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

            if (self.binding_key) |bkey| {
                const Dummy = struct {
                    fn pass_through(_: *anyopaque, _: *const Key) Response {
                        return .pass;
                    }
                };

                _ = try self.hook.registry.register(
                    bkey,
                    self.binding_modifiers,
                    Dummy.pass_through,
                    self.hook,
                    key_registry.Options{
                        .filter = self.filter,
                        .pause_exempt = self.is_pause_exempt,
                    },
                );
            }

            return macro_id;
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

            const macro_id = try self.hook.macro_registry.create(self.name);

            if (self.hook.macro_registry.get(macro_id)) |m| {
                var i: u32 = 0;
                while (i < self.step_count) : (i += 1) {
                    const step = self.steps[i];
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
                                .key = step.keycode,
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

            if (self.binding_key) |bkey| {
                _ = try self.hook.registry.register(
                    bkey,
                    self.binding_modifiers,
                    wrapper.invoke,
                    context,
                    key_registry.Options{
                        .filter = self.filter,
                        .pause_exempt = self.is_pause_exempt,
                    },
                );
            }

            return macro_id;
        }
    };
}

pub fn ModifierBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        modifiers: modifier.Set.Args = .{},

        pub fn init(h: *HookType) Self {
            return Self{ .hook = h };
        }

        pub fn ctrl(self: Self) Self {
            var result = self;
            result.modifiers.ctrl = true;
            return result;
        }

        pub fn alt(self: Self) Self {
            var result = self;
            result.modifiers.alt = true;
            return result;
        }

        pub fn shift(self: Self) Self {
            var result = self;
            result.modifiers.shift = true;
            return result;
        }

        pub fn win(self: Self) Self {
            var result = self;
            result.modifiers.win = true;
            return result;
        }

        pub fn key(self: Self, value: u8) KeyBindBuilder(HookType) {
            return KeyBindBuilder(HookType){
                .hook = self.hook,
                .modifiers = modifier.Set.from(self.modifiers),
                .key = value,
            };
        }
    };
}

pub fn KeyBindBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        modifiers: modifier.Set,
        key: u8,
        is_pause_exempt: bool = false,
        filter: WindowFilter = .{},

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

        pub fn repeat(self: Self, interval_ms: u32) KeyRepeatChainBuilder(HookType) {
            return KeyRepeatChainBuilder(HookType){
                .hook = self.hook,
                .key = self.key,
                .modifiers = self.modifiers,
                .filter = self.filter,
                .is_pause_exempt = self.is_pause_exempt,
                .interval_ms = interval_ms,
                .initial_delay_ms = 0,
            };
        }

        pub fn timer(self: Self, interval_ms: u32) KeyTimerChainBuilder(HookType) {
            return KeyTimerChainBuilder(HookType){
                .hook = self.hook,
                .key = self.key,
                .modifiers = self.modifiers,
                .filter = self.filter,
                .is_pause_exempt = self.is_pause_exempt,
                .interval_ms = interval_ms,
                .repeating = true,
            };
        }
    };
}

pub fn KeyRepeatChainBuilder(comptime HookType: type) type {
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

pub fn KeyTimerChainBuilder(comptime HookType: type) type {
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

pub fn SequenceBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        pattern: []const u8,
        filter: WindowFilter = .{},
        is_block_exempt: bool = false,

        pub fn init(h: *HookType, pattern: []const u8) Self {
            return Self{
                .hook = h,
                .pattern = pattern,
            };
        }

        pub fn block_exempt(self: Self) Self {
            var result = self;
            result.is_block_exempt = true;
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
            comptime callback: fn (@TypeOf(context)) void,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque) void {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    callback(typed);
                }
            };

            return self.hook.sequence_registry.register(
                self.pattern,
                wrapper.invoke,
                context,
                sequence_registry.Options{
                    .filter = self.filter,
                    .block_exempt = self.is_block_exempt,
                },
            );
        }
    };
}

pub fn TimerBuilder(comptime RegistryType: type) type {
    return struct {
        const Self = @This();

        registry: *RegistryType,
        interval_ms: u32,
        repeating: bool = true,

        pub fn every(r: *RegistryType, ms: u32) Self {
            return Self{
                .registry = r,
                .interval_ms = ms,
                .repeating = true,
            };
        }

        pub fn after(r: *RegistryType, ms: u32) Self {
            return Self{
                .registry = r,
                .interval_ms = ms,
                .repeating = false,
            };
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
            };

            return self.registry.register(
                self.interval_ms,
                wrapper.invoke,
                context,
                timer_mod.Options{
                    .binding_id = 0,
                    .repeat = self.repeating,
                },
            );
        }
    };
}
