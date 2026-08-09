const std = @import("std");

fn rollback(result: anytype) void {
    result catch return;
}

const key_event = @import("../event/key.zig");
const modifier = @import("../modifier.zig");
const response = @import("../response.zig");
const filter_mod = @import("../filter.zig");
const pattern_mod = @import("pattern.zig");
const config_mod = @import("../registry/config.zig");
const macro_mod = @import("../registry/macro.zig");
const key_registry = @import("../registry/key.zig");
const timer_mod = @import("../registry/timer.zig");
const repeat_mod = @import("../registry/repeat.zig");
const toggle_mod = @import("../registry/toggle.zig");
const timed = @import("../registry/timed.zig");
const chord_registry = @import("../registry/chord.zig");
const sequence_registry = @import("../registry/sequence.zig");
const Keycode = @import("../keycode.zig").Keycode;

const assert = std.debug.assert;

const Key = key_event.Key;
const Response = response.Response;
const WindowFilter = filter_mod.Active;

const MacroConfig = config_mod.MacroConfig;
const Action = macro_mod.Action;

pub fn BindBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        key: Keycode,
        modifiers: modifier.Set,
        is_pause_exempt: bool = false,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, comptime pattern: []const u8) Instance {
            const parsed = comptime pattern_mod.parse(pattern);

            return Instance{
                .hook = h,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
            };
        }

        pub fn pause_exempt(instance: Instance) Instance {
            var result = instance;
            result.is_pause_exempt = true;
            return result;
        }

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            const id = try instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                wrapper.invoke,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = instance.is_pause_exempt,
                },
            );

            assert(id >= 1);

            return id;
        }

        pub fn on_simple(
            instance: Instance,
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

            const id = try instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                wrapper.invoke,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = instance.is_pause_exempt,
                },
            );

            assert(id >= 1);

            return id;
        }

        pub fn repeat(instance: Instance, interval_ms: u32) RepeatChainBuilderType(HookType) {
            return RepeatChainBuilderType(HookType){
                .hook = instance.hook,
                .key = instance.key,
                .modifiers = instance.modifiers,
                .filter = instance.filter,
                .is_pause_exempt = instance.is_pause_exempt,
                .interval_ms = interval_ms,
                .initial_delay_ms = 0,
            };
        }

        pub fn timer(instance: Instance, interval_ms: u32) TimerChainBuilderType(HookType) {
            return TimerChainBuilderType(HookType){
                .hook = instance.hook,
                .key = instance.key,
                .modifiers = instance.modifiers,
                .filter = instance.filter,
                .is_pause_exempt = instance.is_pause_exempt,
                .interval_ms = interval_ms,
                .repeating = true,
            };
        }

        pub fn toggle(
            instance: Instance,
            comptime toggle_pattern: []const u8,
        ) ToggleChainBuilderType(HookType) {
            const toggle_parsed = comptime pattern_mod.parse(toggle_pattern);

            return ToggleChainBuilderType(HookType){
                .hook = instance.hook,
                .action_key = instance.key,
                .action_modifiers = instance.modifiers,
                .toggle_key = toggle_parsed.key,
                .toggle_modifiers = toggle_parsed.modifiers,
                .filter = instance.filter,
                .is_pause_exempt = instance.is_pause_exempt,
            };
        }

        pub fn macro(instance: Instance, config: MacroConfig) MacroChainBuilderType(HookType) {
            return MacroChainBuilderType(HookType){
                .hook = instance.hook,
                .key = instance.key,
                .modifiers = instance.modifiers,
                .filter = instance.filter,
                .is_pause_exempt = instance.is_pause_exempt,
                .config = config,
            };
        }
    };
}

pub fn RepeatChainBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        key: Keycode,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,
        interval_ms: u32,
        initial_delay_ms: u32,

        pub fn initial_delay(instance: Instance, ms: u32) Instance {
            var result = instance;
            result.initial_delay_ms = ms;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            const binding_id = try instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = instance.is_pause_exempt,
                },
            );

            errdefer rollback(instance.hook.registry.unregister(binding_id));

            assert(binding_id >= 1);

            const repeat_id = try instance.hook.repeat_registry.register(
                binding_id,
                wrapper.invoke,
                context,
                repeat_mod.Options{
                    .interval_ms = instance.interval_ms,
                    .initial_delay_ms = instance.initial_delay_ms,
                },
            );

            assert(repeat_id >= 1);

            return repeat_id;
        }
    };
}

pub fn TimerChainBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        key: Keycode,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,
        interval_ms: u32,
        repeating: bool,

        pub fn once(instance: Instance) Instance {
            var result = instance;
            result.repeating = false;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            const binding_id = try instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = instance.is_pause_exempt,
                },
            );

            errdefer rollback(instance.hook.registry.unregister(binding_id));

            assert(binding_id >= 1);

            const timer_id = try instance.hook.timer_registry.register(
                instance.interval_ms,
                wrapper.invoke,
                context,
                timer_mod.Options{
                    .binding_id = binding_id,
                    .repeat = instance.repeating,
                },
            );

            assert(timer_id >= 1);

            return timer_id;
        }
    };
}

pub fn ToggleChainBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        action_key: Keycode,
        action_modifiers: modifier.Set,
        toggle_key: Keycode,
        toggle_modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,

        pub fn on(
            instance: Instance,
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

            const action_binding_id = try instance.hook.registry.register(
                instance.action_key,
                instance.action_modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = instance.is_pause_exempt,
                },
            );

            errdefer rollback(instance.hook.registry.unregister(action_binding_id));

            assert(action_binding_id >= 1);

            const toggle_binding_id = try instance.hook.registry.register(
                instance.toggle_key,
                instance.toggle_modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = instance.is_pause_exempt,
                },
            );

            errdefer rollback(instance.hook.registry.unregister(toggle_binding_id));

            assert(toggle_binding_id >= 1);

            const toggle_id = try instance.hook.toggle_registry.register(
                action_binding_id,
                toggle_binding_id,
                wrapper.invoke,
                context,
                toggle_mod.Options{
                    .filter = instance.filter,
                },
            );

            assert(toggle_id >= 1);

            return toggle_id;
        }
    };
}

pub fn MacroChainBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        key: Keycode,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,
        config: MacroConfig,

        pub fn on(
            instance: Instance,
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

            const macro_id = try instance.hook.macro_registry.create(instance.config.name);
            errdefer rollback(instance.hook.macro_registry.delete(macro_id));

            assert(macro_id >= 1);

            try instance.add_steps(macro_id);

            const binding_id = try instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                wrapper.invoke,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = instance.is_pause_exempt,
                },
            );

            assert(binding_id >= 1);

            return macro_id;
        }

        fn add_steps(instance: *const Instance, macro_id: u32) !void {
            assert(macro_id >= 1);
            assert(instance.config.step_count <= instance.config.steps.len);

            const m = instance.hook.macro_registry.get(macro_id) orelse return;

            var i: u32 = 0;

            while (i < instance.config.step_count) : (i += 1) {
                const step = instance.config.steps[i];

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

            assert(i == instance.config.step_count);
        }
    };
}

pub fn GroupBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        filter: WindowFilter = .{},
        is_pause_exempt: bool = false,

        pub fn init(h: *HookType) Instance {
            return Instance{ .hook = h };
        }

        pub fn pause_exempt(instance: Instance) Instance {
            var result = instance;
            result.is_pause_exempt = true;
            return result;
        }

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn bind(
            instance: Instance,
            comptime pattern: []const u8,
        ) GroupBindBuilderType(HookType) {
            const parsed = comptime pattern_mod.parse(pattern);

            return GroupBindBuilderType(HookType){
                .hook = instance.hook,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
                .filter = instance.filter,
                .is_pause_exempt = instance.is_pause_exempt,
            };
        }
    };
}

pub fn GroupBindBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        key: Keycode,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            const id = try instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                wrapper.invoke,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = instance.is_pause_exempt,
                },
            );

            assert(id >= 1);

            return id;
        }
    };
}

pub fn OneShotBuilderType(comptime HookType: type, comptime RegistryType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        registry: *RegistryType,
        key: Keycode,
        modifiers: modifier.Set,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, r: *RegistryType, comptime pattern: []const u8) Instance {
            const parsed = comptime pattern_mod.parse(pattern);

            return Instance{
                .hook = h,
                .registry = r,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
            };
        }

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            const binding_id = try instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{ .filter = instance.filter, .pause_exempt = false },
            );

            errdefer rollback(instance.hook.registry.unregister(binding_id));

            assert(binding_id >= 1);

            const id = try instance.registry.register(binding_id, wrapper.invoke, context);

            assert(id >= 1);

            return id;
        }
    };
}

pub fn TimedBuilderType(comptime HookType: type, comptime RegistryType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        registry: *RegistryType,
        key: Keycode,
        modifiers: modifier.Set,
        duration_ms: u64 = 0,
        count_limit: u32 = 0,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, r: *RegistryType, comptime pattern: []const u8) Instance {
            const parsed = comptime pattern_mod.parse(pattern);

            return Instance{
                .hook = h,
                .registry = r,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
            };
        }

        pub fn duration(instance: Instance, ms: u64) Instance {
            var result = instance;
            result.duration_ms = ms;
            return result;
        }

        pub fn count(instance: Instance, limit: u32) Instance {
            var result = instance;

            result.count_limit = limit;

            return result;
        }

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            const binding_id = try instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = false,
                },
            );

            errdefer rollback(instance.hook.registry.unregister(binding_id));

            assert(binding_id >= 1);

            var options = timed.Options{};

            if (instance.count_limit > 0) {
                options = timed.Options.count(instance.count_limit);
            } else if (instance.duration_ms > 0) {
                options = timed.Options.duration(instance.duration_ms);
            } else {
                options = timed.Options.toggle_mode();
            }

            const id = try instance.registry.register(binding_id, wrapper.invoke, context, options);

            assert(id >= 1);

            return id;
        }
    };
}

pub fn RepeatBuilderType(comptime HookType: type, comptime RegistryType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        registry: *RegistryType,
        key: Keycode,
        modifiers: modifier.Set,
        interval_ms: u32 = 100,
        initial_delay_ms: u32 = 0,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, r: *RegistryType, comptime pattern: []const u8) Instance {
            const parsed = comptime pattern_mod.parse(pattern);

            return Instance{
                .hook = h,
                .registry = r,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
            };
        }

        pub fn interval(instance: Instance, ms: u32) Instance {
            var result = instance;
            result.interval_ms = ms;
            return result;
        }

        pub fn initial_delay(instance: Instance, ms: u32) Instance {
            var result = instance;
            result.initial_delay_ms = ms;
            return result;
        }

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            const binding_id = try instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = false,
                },
            );

            errdefer rollback(instance.hook.registry.unregister(binding_id));

            assert(binding_id >= 1);

            const repeat_id = try instance.registry.register(
                binding_id,
                wrapper.invoke,
                context,
                repeat_mod.Options{
                    .interval_ms = instance.interval_ms,
                    .initial_delay_ms = instance.initial_delay_ms,
                },
            );

            assert(repeat_id >= 1);

            return repeat_id;
        }
    };
}

pub fn ChordBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        sequence: []const u8,
        timeout_ms: u32 = chord_registry.timeout_default_ms,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, sequence: []const u8) Instance {
            return Instance{
                .hook = h,
                .sequence = sequence,
            };
        }

        pub fn timeout(instance: Instance, ms: u32) Instance {
            var result = instance;
            result.timeout_ms = ms;
            return result;
        }

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            return instance.hook.chord_registry.register_text(
                instance.sequence,
                wrapper.invoke,
                context,
                chord_registry.Options{
                    .timeout_ms = instance.timeout_ms,
                    .filter = instance.filter,
                },
            );
        }
    };
}

pub fn CommandBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        name: []const u8,

        pub fn init(h: *HookType, name: []const u8) Instance {
            return Instance{
                .hook = h,
                .name = name,
            };
        }

        pub fn on(
            instance: Instance,
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

            const registry = &instance.hook.command_registry;
            const id = try registry.register(instance.name, wrapper.invoke, context);

            assert(id >= 1);

            return id;
        }

        pub fn on_simple(
            instance: Instance,
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

            const registry = &instance.hook.command_registry;
            const id = try registry.register(instance.name, wrapper.invoke, context);

            assert(id >= 1);

            return id;
        }
    };
}

const steps_max = 32;

const StepKind = enum {
    text,
    line,
    key,
    delay,
};

const Step = struct {
    kind: StepKind = .text,
    text: ?[]const u8 = null,
    keycode: Keycode = .silent,
    key_modifiers: modifier.Set = .{},
    delay_ms: u32 = 0,
};

pub fn MacroBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        name: []const u8,
        play_callback: key_registry.Callback,
        steps: [steps_max]Step = [_]Step{.{}} ** steps_max,
        step_count: u32 = 0,
        binding_key: ?Keycode = null,
        binding_modifiers: modifier.Set = .{},
        filter: WindowFilter = .{},
        is_pause_exempt: bool = false,

        pub fn init(h: *HookType, comptime name: []const u8) Instance {
            comptime assert(name.len > 0);

            const player = struct {
                fn invoke(ctx: *anyopaque, k: *const Key) Response {
                    assert(k.is_valid());

                    const typed: *HookType = @ptrCast(@alignCast(ctx));

                    _ = typed.macro_registry.play_by_name(name);

                    return .consume;
                }
            };

            const result = Instance{
                .hook = h,
                .name = name,
                .play_callback = player.invoke,
            };

            assert(result.step_count == 0);

            return result;
        }

        pub fn text(instance: Instance, txt: []const u8) Instance {
            assert(txt.len > 0);
            assert(instance.step_count < steps_max);

            var result = instance;

            result.steps[result.step_count] = .{
                .kind = .text,
                .text = txt,
            };

            result.step_count += 1;

            assert(result.step_count <= steps_max);

            return result;
        }

        pub fn line(instance: Instance, txt: []const u8) Instance {
            assert(instance.step_count < steps_max);

            var result = instance;

            result.steps[result.step_count] = .{
                .kind = .line,
                .text = txt,
            };

            result.step_count += 1;

            assert(result.step_count <= steps_max);

            return result;
        }

        pub fn key(instance: Instance, comptime pattern: []const u8) Instance {
            const parsed = comptime pattern_mod.parse(pattern);
            assert(instance.step_count < steps_max);

            var result = instance;

            result.steps[result.step_count] = .{
                .kind = .key,
                .keycode = parsed.key,
                .key_modifiers = parsed.modifiers,
            };

            result.step_count += 1;

            assert(result.step_count <= steps_max);

            return result;
        }

        pub fn delay(instance: Instance, ms: u32) Instance {
            assert(instance.step_count < steps_max);

            var result = instance;

            result.steps[result.step_count] = .{
                .kind = .delay,
                .delay_ms = ms,
            };

            result.step_count += 1;

            assert(result.step_count <= steps_max);

            return result;
        }

        pub fn bind(instance: Instance, comptime pattern: []const u8) Instance {
            const parsed = comptime pattern_mod.parse(pattern);

            var result = instance;
            result.binding_key = parsed.key;
            result.binding_modifiers = parsed.modifiers;
            return result;
        }

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn pause_exempt(instance: Instance) Instance {
            var result = instance;
            result.is_pause_exempt = true;
            return result;
        }

        pub fn create(instance: Instance) !u32 {
            const macro_id = try instance.hook.macro_registry.create(instance.name);
            errdefer rollback(instance.hook.macro_registry.delete(macro_id));

            assert(macro_id >= 1);

            try instance.add_steps(macro_id);

            if (instance.binding_key) |bkey| {
                const binding_id = try instance.hook.registry.register(
                    bkey,
                    instance.binding_modifiers,
                    instance.play_callback,
                    instance.hook,
                    key_registry.Options{
                        .filter = instance.filter,
                        .pause_exempt = instance.is_pause_exempt,
                    },
                );

                assert(binding_id >= 1);
            }

            return macro_id;
        }

        fn add_steps(instance: *const Instance, macro_id: u32) !void {
            assert(macro_id >= 1);
            assert(instance.step_count <= instance.steps.len);

            const m = instance.hook.macro_registry.get(macro_id) orelse return;

            var i: u32 = 0;

            while (i < instance.step_count) : (i += 1) {
                const step = instance.steps[i];

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

            assert(i == instance.step_count);
        }

        pub fn on(
            instance: Instance,
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

            const macro_id = try instance.hook.macro_registry.create(instance.name);
            errdefer rollback(instance.hook.macro_registry.delete(macro_id));

            assert(macro_id >= 1);

            try instance.add_steps(macro_id);

            if (instance.binding_key) |bkey| {
                const binding_id = try instance.hook.registry.register(
                    bkey,
                    instance.binding_modifiers,
                    wrapper.invoke,
                    context,
                    key_registry.Options{
                        .filter = instance.filter,
                        .pause_exempt = instance.is_pause_exempt,
                    },
                );

                assert(binding_id >= 1);
            }

            return macro_id;
        }
    };
}

pub fn ModifierBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        modifiers: modifier.Set.Args = .{},

        pub fn init(h: *HookType) Instance {
            return Instance{ .hook = h };
        }

        pub fn ctrl(instance: Instance) Instance {
            var result = instance;
            result.modifiers.ctrl = true;
            return result;
        }

        pub fn alt(instance: Instance) Instance {
            var result = instance;
            result.modifiers.alt = true;
            return result;
        }

        pub fn shift(instance: Instance) Instance {
            var result = instance;
            result.modifiers.shift = true;
            return result;
        }

        pub fn win(instance: Instance) Instance {
            var result = instance;
            result.modifiers.win = true;
            return result;
        }

        pub fn key(instance: Instance, value: Keycode) KeyBindBuilderType(HookType) {
            return KeyBindBuilderType(HookType){
                .hook = instance.hook,
                .modifiers = modifier.Set.from(instance.modifiers),
                .key = value,
            };
        }
    };
}

pub fn KeyBindBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        modifiers: modifier.Set,
        key: Keycode,
        is_pause_exempt: bool = false,
        filter: WindowFilter = .{},

        pub fn pause_exempt(instance: Instance) Instance {
            var result = instance;
            result.is_pause_exempt = true;
            return result;
        }

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            return instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                wrapper.invoke,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = instance.is_pause_exempt,
                },
            );
        }

        pub fn repeat(instance: Instance, interval_ms: u32) KeyRepeatChainBuilderType(HookType) {
            return KeyRepeatChainBuilderType(HookType){
                .hook = instance.hook,
                .key = instance.key,
                .modifiers = instance.modifiers,
                .filter = instance.filter,
                .is_pause_exempt = instance.is_pause_exempt,
                .interval_ms = interval_ms,
                .initial_delay_ms = 0,
            };
        }

        pub fn timer(instance: Instance, interval_ms: u32) KeyTimerChainBuilderType(HookType) {
            return KeyTimerChainBuilderType(HookType){
                .hook = instance.hook,
                .key = instance.key,
                .modifiers = instance.modifiers,
                .filter = instance.filter,
                .is_pause_exempt = instance.is_pause_exempt,
                .interval_ms = interval_ms,
                .repeating = true,
            };
        }
    };
}

pub fn KeyRepeatChainBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        key: Keycode,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,
        interval_ms: u32,
        initial_delay_ms: u32,

        pub fn initial_delay(instance: Instance, ms: u32) Instance {
            var result = instance;
            result.initial_delay_ms = ms;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            const binding_id = try instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = instance.is_pause_exempt,
                },
            );

            errdefer rollback(instance.hook.registry.unregister(binding_id));

            assert(binding_id >= 1);

            const repeat_id = try instance.hook.repeat_registry.register(
                binding_id,
                wrapper.invoke,
                context,
                repeat_mod.Options{
                    .interval_ms = instance.interval_ms,
                    .initial_delay_ms = instance.initial_delay_ms,
                },
            );

            assert(repeat_id >= 1);

            return repeat_id;
        }
    };
}

pub fn KeyTimerChainBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        key: Keycode,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,
        interval_ms: u32,
        repeating: bool,

        pub fn once(instance: Instance) Instance {
            var result = instance;
            result.repeating = false;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            const binding_id = try instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = instance.filter,
                    .pause_exempt = instance.is_pause_exempt,
                },
            );

            errdefer rollback(instance.hook.registry.unregister(binding_id));

            assert(binding_id >= 1);

            const timer_id = try instance.hook.timer_registry.register(
                instance.interval_ms,
                wrapper.invoke,
                context,
                timer_mod.Options{
                    .binding_id = binding_id,
                    .repeat = instance.repeating,
                },
            );

            assert(timer_id >= 1);

            return timer_id;
        }
    };
}

pub fn SequenceBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        pattern: []const u8,
        filter: WindowFilter = .{},
        is_block_exempt: bool = false,

        pub fn init(h: *HookType, pattern: []const u8) Instance {
            return Instance{
                .hook = h,
                .pattern = pattern,
            };
        }

        pub fn block_exempt(instance: Instance) Instance {
            var result = instance;
            result.is_block_exempt = true;
            return result;
        }

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            return instance.hook.sequence_registry.register(
                instance.pattern,
                wrapper.invoke,
                context,
                sequence_registry.Options{
                    .filter = instance.filter,
                    .block_exempt = instance.is_block_exempt,
                },
            );
        }
    };
}

pub fn TimerBuilderType(comptime RegistryType: type) type {
    return struct {
        const Instance = @This();

        registry: *RegistryType,
        interval_ms: u32,
        repeating: bool = true,

        pub fn every(r: *RegistryType, ms: u32) Instance {
            return Instance{
                .registry = r,
                .interval_ms = ms,
                .repeating = true,
            };
        }

        pub fn after(r: *RegistryType, ms: u32) Instance {
            return Instance{
                .registry = r,
                .interval_ms = ms,
                .repeating = false,
            };
        }

        pub fn on(
            instance: Instance,
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

            return instance.registry.register(
                instance.interval_ms,
                wrapper.invoke,
                context,
                timer_mod.Options{
                    .binding_id = 0,
                    .repeat = instance.repeating,
                },
            );
        }
    };
}

const keyboard = @import("../keyboard.zig");

const testing = std.testing;

const Hook = keyboard.KeyboardHookType(.{
    .capacity_repeat = 1,
    .capacity_macro = 4,
});

const Ctx = struct {
    hits: u32 = 0,

    fn on_key(ctx: *Ctx, _: *const Key) Response {
        ctx.hits += 1;

        return .pass;
    }

    fn on_repeat(ctx: *Ctx, _: u32) void {
        ctx.hits += 1;
    }

    fn on_timer(ctx: *Ctx) void {
        ctx.hits += 1;
    }
};

fn make_key(value: Keycode, mods: modifier.Set) Key {
    return Key{
        .value = value,
        .down = true,
        .injected = false,
        .modifiers = mods,
    };
}

test "a repeat chain registers both the binding and the repeat" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};
    const repeat_id = try hook.bind("Ctrl+A").repeat(100).on(&ctx, Ctx.on_repeat);

    try testing.expect(repeat_id >= 1);

    const key = make_key(.a, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) != null);
}

test "a failed repeat rolls the binding back" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};

    _ = try hook.bind("Ctrl+A").repeat(100).on(&ctx, Ctx.on_repeat);

    const result = hook.bind("Ctrl+B").repeat(100).on(&ctx, Ctx.on_repeat);

    try testing.expectError(error.RegistryFull, result);

    const key = make_key(.b, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) == null);
}

test "a timer chain registers both the binding and the timer" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};
    const timer_id = try hook.bind("Ctrl+C").timer(1000).on(&ctx, Ctx.on_timer);

    try testing.expect(timer_id >= 1);

    const key = make_key(.c, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) != null);
}

test "a toggle chain registers both of its bindings" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};
    const toggle_id = try hook.bind("Ctrl+D").toggle("Ctrl+T").on(&ctx, Ctx.on_key);

    try testing.expect(toggle_id >= 1);

    const action_key = make_key(.d, modifier.Set.from(.{ .ctrl = true }));
    const toggle_key = make_key(.t, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&action_key) != null);
    try testing.expect(hook.registry.find(&toggle_key) != null);
}

test "a macro chain registers both the macro and the binding" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};

    const config = MacroConfig.init("chain_macro").text("hello");
    const macro_id = try hook.bind("Ctrl+E").macro(config).on(&ctx, Ctx.on_key);

    try testing.expect(macro_id >= 1);
    try testing.expect(hook.macro_registry.find_by_name("chain_macro") != null);

    const key = make_key(.e, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) != null);
}

test "a failed binding rolls the macro back" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};

    _ = try hook.bind("Ctrl+F").on(&ctx, Ctx.on_key);

    const config = MacroConfig.init("orphan_macro").text("hello");
    const result = hook.bind("Ctrl+F").macro(config).on(&ctx, Ctx.on_key);

    try testing.expectError(error.AlreadyRegistered, result);
    try testing.expect(hook.macro_registry.find_by_name("orphan_macro") == null);
}

test "creating a macro wires its play binding" {
    var hook = Hook.init();
    defer hook.deinit();

    const macro_id = try hook.macro_builder("play_macro")
        .text("hello")
        .bind("Ctrl+G")
        .create();

    try testing.expect(macro_id >= 1);
    try testing.expect(hook.macro_registry.find_by_name("play_macro") != null);

    const key = make_key(.g, modifier.Set.from(.{ .ctrl = true }));
    const entry = hook.registry.find(&key);

    try testing.expect(entry != null);
}

test "a failed play binding rolls the macro back" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};

    _ = try hook.bind("Ctrl+H").on(&ctx, Ctx.on_key);

    const result = hook.macro_builder("rollback_macro")
        .text("hello")
        .bind("Ctrl+H")
        .create();

    try testing.expectError(error.AlreadyRegistered, result);
    try testing.expect(hook.macro_registry.find_by_name("rollback_macro") == null);
}

test "a macro registers both itself and its callback binding" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};

    const macro_id = try hook.macro_builder("callback_macro")
        .text("hello")
        .bind("Ctrl+I")
        .on(&ctx, Ctx.on_key);

    try testing.expect(macro_id >= 1);

    const key = make_key(.i, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) != null);
}
