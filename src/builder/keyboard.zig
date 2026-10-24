const std = @import("std");

const chord_registry = @import("../registry/chord.zig");
const filter_mod = @import("../filter.zig");
const key_event = @import("../event/key.zig");
const key_registry = @import("../registry/key.zig");
const keyboard_module = @import("../keyboard.zig");
const keycode = @import("../keycode.zig");
const macro_registry = @import("../registry/macro.zig");
const modifier = @import("../modifier.zig");
const pattern_mod = @import("pattern.zig");
const repeat_registry = @import("../registry/repeat.zig");
const response = @import("../response.zig");
const sequence_registry = @import("../registry/sequence.zig");
const timer_registry = @import("../registry/timer.zig");
const toggle_registry = @import("../registry/toggle.zig");

const assert = std.debug.assert;

const CapacityError = keyboard_module.CapacityError;
const Key = key_event.Key;
const Keycode = keycode.Keycode;
const RequestError = keyboard_module.RequestError;
const Response = response.Response;
const WindowFilter = filter_mod.Active;

pub const macro_step_count_max: u32 = 64;

const MacroStep = union(enum) {
    delay_ms: u32,
    line: []const u8,
    stroke: Stroke,
    text: []const u8,

    const Stroke = struct {
        value: Keycode,
        modifiers: modifier.Set,
    };
};

pub fn BindBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        key: Keycode,
        modifiers: modifier.Set,
        filter: WindowFilter = .{},
        is_block_exempt: bool = false,

        pub fn block_exempt(instance: Instance) Instance {
            var result = instance;

            result.is_block_exempt = true;

            return result;
        }

        pub fn with_filter(instance: Instance, filter: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;

            result.filter = filter;

            return result;
        }

        pub fn on(
            instance: Instance,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner, *const Key) Response,
        ) (CapacityError || RequestError)!HookType.Binding {
            const wrapper = struct {
                fn invoke(pointer: *anyopaque, key: *const Key) Response {
                    const typed: *Owner = @ptrCast(@alignCast(pointer));
                    return callback(typed, key);
                }
            };

            const id = try instance.register(wrapper.invoke, owner);

            assert(id >= 1);

            return @fromBackingInt(id);
        }

        pub fn once(instance: Instance) OneshotChainType(HookType) {
            comptime keyboard_module.require(HookType, "oneshot_registry", "oneshot_count_max");

            return .{ .bind = instance };
        }

        pub fn repeat(instance: Instance, interval_ms: u32) RepeatChainType(HookType) {
            comptime keyboard_module.require(HookType, "repeat_registry", "repeat_count_max");

            return .{ .bind = instance, .interval_ms = interval_ms };
        }

        pub fn toggle(
            instance: Instance,
            comptime pattern: []const u8,
        ) ToggleChainType(HookType) {
            comptime keyboard_module.require(HookType, "toggle_registry", "toggle_count_max");

            const parsed = comptime pattern_mod.parse(pattern);

            return .{
                .bind = instance,
                .toggle_key = parsed.key,
                .toggle_modifiers = parsed.modifiers,
            };
        }

        fn register(
            instance: *const Instance,
            callback: key_registry.Callback,
            context: ?*anyopaque,
        ) (key_registry.CapacityError || key_registry.RequestError)!u32 {
            return instance.hook.registry.register(
                instance.key,
                instance.modifiers,
                callback,
                context,
                .{
                    .filter = instance.filter,
                    .block_exempt = instance.is_block_exempt,
                },
            );
        }
    };
}

pub fn OneshotChainType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        bind: BindBuilderType(HookType),

        pub fn on(
            instance: Instance,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner, *const Key) Response,
        ) (CapacityError || RequestError)!HookType.Oneshot {
            const wrapper = struct {
                fn invoke(pointer: *anyopaque, key: *const Key) Response {
                    const typed: *Owner = @ptrCast(@alignCast(pointer));
                    return callback(typed, key);
                }
            };

            const hook = instance.bind.hook;
            const binding_id = try instance.bind.register(pass_through, owner);
            errdefer rollback(hook.registry.unregister(binding_id));

            const id = try hook.oneshot_registry.register(binding_id, wrapper.invoke, owner);

            assert(id >= 1);

            return @fromBackingInt(id);
        }
    };
}

pub fn RepeatChainType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        bind: BindBuilderType(HookType),
        interval_ms: u32,
        delay_ms_initial: u32 = 0,

        pub fn delay_initial(instance: Instance, delay_ms: u32) Instance {
            var result = instance;

            result.delay_ms_initial = delay_ms;

            return result;
        }

        pub fn on(
            instance: Instance,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner, u32) void,
        ) (CapacityError || RequestError)!HookType.Repeat {
            const wrapper = struct {
                fn invoke(pointer: *anyopaque, count: u32) void {
                    const typed: *Owner = @ptrCast(@alignCast(pointer));

                    callback(typed, count);
                }
            };

            const hook = instance.bind.hook;
            const binding_id = try instance.bind.register(pass_through, owner);
            errdefer rollback(hook.registry.unregister(binding_id));

            const id = try hook.repeat_registry.register(binding_id, wrapper.invoke, owner, .{
                .key = instance.bind.key,
                .interval_ms = instance.interval_ms,
                .delay_ms_initial = instance.delay_ms_initial,
            });

            assert(id >= 1);

            return @fromBackingInt(id);
        }
    };
}

pub fn ToggleChainType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        bind: BindBuilderType(HookType),
        toggle_key: Keycode,
        toggle_modifiers: modifier.Set,

        pub fn on(
            instance: Instance,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner, *const Key) Response,
        ) (CapacityError || RequestError)!HookType.Toggle {
            const wrapper = struct {
                fn invoke(pointer: *anyopaque, key: *const Key) Response {
                    const typed: *Owner = @ptrCast(@alignCast(pointer));
                    return callback(typed, key);
                }
            };

            const hook = instance.bind.hook;
            const action_id = try instance.bind.register(pass_through, owner);
            errdefer rollback(hook.registry.unregister(action_id));

            var switch_bind = instance.bind;

            switch_bind.key = instance.toggle_key;
            switch_bind.modifiers = instance.toggle_modifiers;

            const toggle_id = try switch_bind.register(pass_through, owner);
            errdefer rollback(hook.registry.unregister(toggle_id));

            const id = try hook.toggle_registry.register(
                action_id,
                toggle_id,
                wrapper.invoke,
                owner,
                .{ .filter = instance.bind.filter },
            );

            assert(id >= 1);

            return @fromBackingInt(id);
        }
    };
}

pub fn GroupBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        filter: WindowFilter = .{},
        is_block_exempt: bool = false,

        pub fn block_exempt(instance: Instance) Instance {
            var result = instance;

            result.is_block_exempt = true;

            return result;
        }

        pub fn with_filter(instance: Instance, filter: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;

            result.filter = filter;

            return result;
        }

        pub fn bind(instance: Instance, comptime pattern: []const u8) BindBuilderType(HookType) {
            const parsed = comptime pattern_mod.parse(pattern);

            return .{
                .hook = instance.hook,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
                .filter = instance.filter,
                .is_block_exempt = instance.is_block_exempt,
            };
        }
    };
}

pub fn ChordBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        keys: []const Keycode,
        timeout_ms: u32 = chord_registry.timeout_default_ms,
        filter: WindowFilter = .{},

        pub fn timeout(instance: Instance, timeout_ms: u32) Instance {
            var result = instance;

            result.timeout_ms = timeout_ms;

            return result;
        }

        pub fn with_filter(instance: Instance, filter: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;

            result.filter = filter;

            return result;
        }

        pub fn on(
            instance: Instance,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner) Response,
        ) (CapacityError || RequestError)!HookType.Chord {
            const wrapper = struct {
                fn invoke(pointer: *anyopaque) Response {
                    const typed: *Owner = @ptrCast(@alignCast(pointer));
                    return callback(typed);
                }
            };

            const id = try instance.hook.chord_registry.register(
                instance.keys,
                wrapper.invoke,
                owner,
                .{
                    .timeout_ms = instance.timeout_ms,
                    .filter = instance.filter,
                },
            );

            assert(id >= 1);

            return @fromBackingInt(id);
        }
    };
}

pub fn CommandBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        name: []const u8,

        pub fn on(
            instance: Instance,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner, []const u8, []const u8) Response,
        ) (CapacityError || RequestError)!HookType.Command {
            const wrapper = struct {
                fn invoke(pointer: *anyopaque, name: []const u8, args: []const u8) Response {
                    const typed: *Owner = @ptrCast(@alignCast(pointer));
                    return callback(typed, name, args);
                }
            };

            const id = try instance.hook.command_registry.register(
                instance.name,
                wrapper.invoke,
                owner,
            );

            assert(id >= 1);

            return @fromBackingInt(id);
        }
    };
}

pub fn MacroBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        name: []const u8,
        play_callback: key_registry.Callback,
        steps: [macro_step_count_max]MacroStep = undefined,
        step_count: u32 = 0,
        binding_key: ?Keycode = null,
        binding_modifiers: modifier.Set = .{},
        filter: WindowFilter = .{},

        pub fn text(instance: Instance, value: []const u8) Instance {
            assert(value.len > 0);

            return instance.push(.{ .text = value });
        }

        pub fn line(instance: Instance, value: []const u8) Instance {
            return instance.push(.{ .line = value });
        }

        pub fn key(instance: Instance, comptime pattern: []const u8) Instance {
            const parsed = comptime pattern_mod.parse(pattern);

            return instance.push(.{
                .stroke = .{ .value = parsed.key, .modifiers = parsed.modifiers },
            });
        }

        pub fn delay(instance: Instance, delay_ms: u32) Instance {
            return instance.push(.{ .delay_ms = delay_ms });
        }

        pub fn bind(instance: Instance, comptime pattern: []const u8) Instance {
            comptime keyboard_module.require(HookType, "registry", "binding_count_max");

            const parsed = comptime pattern_mod.parse(pattern);

            var result = instance;

            result.binding_key = parsed.key;
            result.binding_modifiers = parsed.modifiers;

            return result;
        }

        pub fn with_filter(instance: Instance, filter: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;

            result.filter = filter;

            return result;
        }

        pub fn create(instance: *const Instance) (CapacityError || RequestError)!HookType.Macro {
            const macro_id = try instance.hook.macro_registry.create(instance.name);
            errdefer rollback_macro(instance.hook.macro_registry.delete(macro_id));

            assert(macro_id >= 1);

            try instance.add_steps(macro_id);

            if (instance.binding_key) |binding_key| {
                const binding_id = try instance.hook.registry.register(
                    binding_key,
                    instance.binding_modifiers,
                    instance.play_callback,
                    instance.hook,
                    .{ .filter = instance.filter },
                );

                assert(binding_id >= 1);
            }

            return @fromBackingInt(macro_id);
        }

        fn push(instance: Instance, step: MacroStep) Instance {
            assert(instance.step_count < macro_step_count_max);

            var result = instance;

            result.steps[result.step_count] = step;
            result.step_count += 1;

            assert(result.step_count <= macro_step_count_max);

            return result;
        }

        fn add_steps(instance: *const Instance, macro_id: u32) macro_registry.CapacityError!void {
            assert(macro_id >= 1);
            assert(instance.step_count <= macro_step_count_max);

            const macro = instance.hook.macro_registry.get(macro_id) orelse unreachable;

            for (instance.steps[0..instance.step_count]) |step| {
                switch (step) {
                    .delay_ms => |delay_ms| try macro.add_action(.{
                        .kind = .delay,
                        .delay_ms = delay_ms,
                    }),
                    .line => |value| try macro.add_line(value),
                    .stroke => |stroke| try macro.add_action(.{
                        .kind = .key_press,
                        .key = stroke.value,
                        .modifiers = stroke.modifiers,
                    }),
                    .text => |value| try macro.add_text(value),
                }
            }
        }
    };
}

pub fn SequenceBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        text: []const u8,
        filter: WindowFilter = .{},
        is_block_exempt: bool = false,

        pub fn block_exempt(instance: Instance) Instance {
            var result = instance;

            result.is_block_exempt = true;

            return result;
        }

        pub fn with_filter(instance: Instance, filter: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;

            result.filter = filter;

            return result;
        }

        pub fn on(
            instance: Instance,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner) void,
        ) (CapacityError || RequestError)!HookType.Sequence {
            const wrapper = struct {
                fn invoke(pointer: *anyopaque) void {
                    const typed: *Owner = @ptrCast(@alignCast(pointer));

                    callback(typed);
                }
            };

            const id = try instance.hook.sequence_registry.register(
                instance.text,
                wrapper.invoke,
                owner,
                .{
                    .filter = instance.filter,
                    .block_exempt = instance.is_block_exempt,
                },
            );

            assert(id >= 1);

            return @fromBackingInt(id);
        }
    };
}

pub fn TimerBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        interval_ms: u32,
        repeating: bool = true,

        pub fn once(instance: Instance) Instance {
            var result = instance;

            result.repeating = false;

            return result;
        }

        pub fn on(
            instance: Instance,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner) void,
        ) (CapacityError || RequestError)!HookType.Timer {
            const wrapper = struct {
                fn invoke(pointer: *anyopaque) void {
                    const typed: *Owner = @ptrCast(@alignCast(pointer));

                    callback(typed);
                }
            };

            const id = try instance.hook.timer_registry.register(
                instance.interval_ms,
                wrapper.invoke,
                owner,
                .{ .repeat = instance.repeating },
            );

            assert(id >= 1);

            return @fromBackingInt(id);
        }
    };
}

fn pass_through(_: *anyopaque, key: *const Key) Response {
    assert(key.is_valid());

    return .pass;
}

fn rollback(result: key_registry.RequestError!void) void {
    result catch |err| switch (err) {
        error.BindingDuplicate, error.HandleUnknown => unreachable,
    };
}

fn rollback_macro(result: macro_registry.RequestError!void) void {
    result catch |err| switch (err) {
        error.HandleUnknown, error.MacroPlaying, error.NameInvalid => unreachable,
    };
}

const testing = std.testing;

const Hook = keyboard_module.KeyboardType(.{
    .binding_count_max = 16,
    .macro_count_max = 4,
    .oneshot_count_max = 2,
    .repeat_count_max = 1,
    .toggle_count_max = 2,
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
    const hook = try testing.allocator.create(Hook);
    defer testing.allocator.destroy(hook);

    try hook.init(.{});
    defer hook.deinit();

    var ctx = Ctx{};

    _ = try hook.bind("Ctrl+A").repeat(100).on(Ctx, &ctx, Ctx.on_repeat);

    const key = make_key(.a, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) != null);
}

test "a failed repeat rolls the binding back" {
    const hook = try testing.allocator.create(Hook);
    defer testing.allocator.destroy(hook);

    try hook.init(.{});
    defer hook.deinit();

    var ctx = Ctx{};

    _ = try hook.bind("Ctrl+A").repeat(100).on(Ctx, &ctx, Ctx.on_repeat);

    const result = hook.bind("Ctrl+B").repeat(100).on(Ctx, &ctx, Ctx.on_repeat);

    try testing.expectError(error.RepeatsExhausted, result);

    const key = make_key(.b, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) == null);
}

test "a toggle chain registers both of its bindings" {
    const hook = try testing.allocator.create(Hook);
    defer testing.allocator.destroy(hook);

    try hook.init(.{});
    defer hook.deinit();

    var ctx = Ctx{};

    _ = try hook.bind("Ctrl+D").toggle("Ctrl+T").on(Ctx, &ctx, Ctx.on_key);

    const action_key = make_key(.d, modifier.Set.from(.{ .ctrl = true }));
    const toggle_key = make_key(.t, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&action_key) != null);
    try testing.expect(hook.registry.find(&toggle_key) != null);
}

test "a failed toggle rolls both of its bindings back" {
    const hook = try testing.allocator.create(Hook);
    defer testing.allocator.destroy(hook);

    try hook.init(.{});
    defer hook.deinit();

    var ctx = Ctx{};

    _ = try hook.bind("Ctrl+Y").on(Ctx, &ctx, Ctx.on_key);

    const result = hook.bind("Ctrl+D").toggle("Ctrl+Y").on(Ctx, &ctx, Ctx.on_key);

    try testing.expectError(error.BindingDuplicate, result);

    const action_key = make_key(.d, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&action_key) == null);
}

test "a oneshot chain registers the binding and the oneshot" {
    const hook = try testing.allocator.create(Hook);
    defer testing.allocator.destroy(hook);

    try hook.init(.{});
    defer hook.deinit();

    var ctx = Ctx{};

    _ = try hook.bind("Ctrl+O").once().on(Ctx, &ctx, Ctx.on_key);

    const key = make_key(.o, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) != null);
}

test "creating a macro wires its play binding" {
    const hook = try testing.allocator.create(Hook);
    defer testing.allocator.destroy(hook);

    try hook.init(.{});
    defer hook.deinit();

    _ = try hook.macro("play_macro")
        .text("hello")
        .bind("Ctrl+G")
        .create();

    try testing.expect(hook.macro_registry.find_by_name("play_macro") != null);

    const key = make_key(.g, modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) != null);
}

test "a failed play binding rolls the macro back" {
    const hook = try testing.allocator.create(Hook);
    defer testing.allocator.destroy(hook);

    try hook.init(.{});
    defer hook.deinit();

    var ctx = Ctx{};

    _ = try hook.bind("Ctrl+H").on(Ctx, &ctx, Ctx.on_key);

    const result = hook.macro("rollback_macro")
        .text("hello")
        .bind("Ctrl+H")
        .create();

    try testing.expectError(error.BindingDuplicate, result);
    try testing.expect(hook.macro_registry.find_by_name("rollback_macro") == null);
}

test "a macro too long for its action table is a capacity error" {
    const hook = try testing.allocator.create(Hook);
    defer testing.allocator.destroy(hook);

    try hook.init(.{});
    defer hook.deinit();

    const long: [macro_registry.text_step_bytes_max + 1]u8 = @splat('a');
    const result = hook.macro("long_macro").text(&long).create();

    try testing.expectError(error.TextTooLong, result);
    try testing.expect(hook.macro_registry.find_by_name("long_macro") == null);
}
