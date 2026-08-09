const std = @import("std");

const builder = @import("builder/keyboard.zig");
const chord_registry = @import("registry/chord.zig");
const command_mod = @import("registry/command.zig");
const key_event = @import("event/key.zig");
const key_registry = @import("registry/key.zig");
const keycode = @import("keycode.zig");
const macro_registry = @import("registry/macro.zig");
const middleware_base = @import("middleware/base.zig");
const modifier = @import("modifier.zig");
const oneshot_registry = @import("registry/oneshot.zig");
const platform = @import("platform.zig");
const repeat_registry = @import("registry/repeat.zig");
const response_mod = @import("response.zig");
const runtime = @import("runtime.zig");
const sequence_registry = @import("registry/sequence.zig");
const state = @import("state.zig");
const sync = @import("sync.zig");
const timer_registry = @import("registry/timer.zig");
const toggle_registry = @import("registry/toggle.zig");

const assert = std.debug.assert;

const clipboard_mod = platform.backend.clipboard;
const simulate_key = platform.backend.simulate.key;
const simulate_text = platform.backend.simulate.text;

const Key = key_event.Key;
const Keycode = keycode.Keycode;
const KeyboardState = state.Keyboard;
const Mutex = sync.Mutex;
const Response = response_mod.Response;

pub const keycode_silent: Keycode = .silent;

pub const Error = error{
    HookAlreadyInstalled,
    HookInstallFailed,
};

pub const Config = struct {
    capacity: u32 = 128,
    capacity_chord: u32 = 32,
    capacity_command: u8 = 32,
    capacity_timer: u32 = 32,
    capacity_repeat: u32 = 32,
    capacity_macro: u32 = 16,
    capacity_toggle: u32 = 16,
    capacity_sequence: u32 = 8,
    capacity_oneshot: u32 = 32,
    capacity_middleware: u8 = 8,
    pass_injected: bool = false,
};

pub const KeyCallback = *const fn (ctx: *anyopaque, key: *const Key) ?Response;

fn require(comptime available: bool, comptime feature: []const u8) void {
    if (!available) {
        @compileError("nimble: " ++ feature ++ " is not available on this backend");
    }
}

pub fn KeyboardHookType(comptime config: Config) type {
    const capacity = config.capacity;
    const capacity_chord = config.capacity_chord;
    const capacity_command = config.capacity_command;
    const capacity_timer = config.capacity_timer;
    const capacity_repeat = config.capacity_repeat;
    const capacity_macro = config.capacity_macro;
    const capacity_toggle = config.capacity_toggle;
    const capacity_sequence = config.capacity_sequence;
    const capacity_oneshot = config.capacity_oneshot;
    const capacity_middleware = config.capacity_middleware;

    return struct {
        const Instance = @This();

        const Source = platform.backend.keyboard.SourceType(Instance);

        const Registry = key_registry.KeyRegistryType(capacity);
        const ChordRegistry = chord_registry.ChordRegistryType(capacity_chord);
        const CommandRegistry = command_mod.CommandRegistryType(capacity_command);
        const TimerRegistry = timer_registry.TimerRegistryType(capacity_timer);
        const RepeatRegistry = repeat_registry.RepeatRegistryType(capacity_repeat);
        const MacroRegistry = macro_registry.MacroRegistryType(capacity_macro);
        const ToggleRegistry = toggle_registry.ToggleRegistryType(capacity_toggle);
        const SequenceRegistry = sequence_registry.SequenceRegistryType(capacity_sequence);
        const OneShotRegistry = oneshot_registry.OneShotRegistryType(capacity_oneshot);
        const Pipeline = middleware_base.PipelineType(capacity_middleware);

        registry: Registry = Registry.init(),
        chord_registry: ChordRegistry = ChordRegistry.init(),
        command_registry: CommandRegistry = CommandRegistry.init(),
        timer_registry: TimerRegistry = TimerRegistry.init(),
        repeat_registry: RepeatRegistry = RepeatRegistry.init(),
        macro_registry: MacroRegistry = MacroRegistry.init(),
        toggle_registry: ToggleRegistry = ToggleRegistry.init(),
        sequence_registry: SequenceRegistry = SequenceRegistry.init(),
        oneshot_registry: OneShotRegistry = OneShotRegistry.init(),
        pipeline: Pipeline = Pipeline.init(),
        keyboard: KeyboardState = KeyboardState.init(),
        blocked: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        mutex: Mutex = .{},
        source: Source = Source.init(),
        key_callback: ?KeyCallback = null,
        key_context: ?*anyopaque = null,

        pub fn init() Instance {
            return Instance{};
        }

        pub fn deinit(instance: *Instance) void {
            instance.stop();
            instance.repeat_registry.stop_all();
            instance.macro_registry.stop();
            instance.registry.clear();
            instance.chord_registry.clear();
            instance.command_registry.clear();
            instance.timer_registry.clear();
            instance.repeat_registry.clear();
            instance.macro_registry.clear();
            instance.toggle_registry.clear();
            instance.sequence_registry.clear();
            instance.oneshot_registry.clear();
        }

        pub fn add_middleware(instance: *Instance, comptime T: type, pointer: *T) !u8 {
            return instance.pipeline.add(T, pointer);
        }

        pub fn remove_middleware(instance: *Instance, slot: u8) !void {
            return instance.pipeline.remove(slot);
        }

        pub fn bind_once(
            instance: *Instance,
            binding_id: u32,
            callback: oneshot_registry.Callback,
            context: *anyopaque,
        ) !u32 {
            assert(binding_id >= 1);

            return instance.oneshot_registry.register(binding_id, callback, context);
        }

        pub fn set_key_callback(
            instance: *Instance,
            callback: KeyCallback,
            context: *anyopaque,
        ) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            instance.key_callback = callback;
            instance.key_context = context;
        }

        pub fn clear_key_callback(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            instance.key_callback = null;
            instance.key_context = null;
        }

        pub fn start(instance: *Instance) !void {
            assert(runtime.is_open());

            instance.mutex.lock();
            defer instance.mutex.unlock();

            if (instance.running.load(.seq_cst)) {
                return;
            }

            instance.blocked.store(false, .seq_cst);

            try instance.source.install(instance);

            instance.timer_registry.set_global();
            instance.running.store(true, .seq_cst);

            assert(instance.running.load(.seq_cst));
        }

        pub fn stop(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            if (!instance.running.load(.seq_cst)) {
                return;
            }

            instance.running.store(false, .seq_cst);

            instance.source.remove();

            instance.timer_registry.clear_global();
            instance.blocked.store(false, .seq_cst);

            assert(!instance.running.load(.seq_cst));
            assert(!instance.blocked.load(.seq_cst));
        }

        pub fn is_running(instance: *Instance) bool {
            return instance.running.load(.seq_cst);
        }

        pub fn is_paused(instance: *Instance) bool {
            return instance.registry.is_paused();
        }

        pub fn set_paused(instance: *Instance, value: bool) void {
            instance.registry.set_paused(value);
        }

        pub fn is_blocked(instance: *Instance) bool {
            return instance.blocked.load(.seq_cst);
        }

        pub fn set_blocked(instance: *Instance, value: bool) void {
            const was_blocked = instance.blocked.load(.seq_cst);
            instance.blocked.store(value, .seq_cst);

            if (was_blocked != value) {
                instance.release_modifier();
            }
        }

        fn release_modifier(_: *Instance) void {
            const keys = [_]Keycode{
                Keycode.control_left, Keycode.control_right,
                Keycode.alt_left,     Keycode.alt_right,
                Keycode.shift_left,   Keycode.shift_right,
                Keycode.super_left,   Keycode.super_right,
            };

            _ = simulate_key.dummy();

            for (keys) |key| {
                _ = simulate_key.key_up(key);
            }
        }

        pub fn bind(
            instance: *Instance,
            comptime pattern: []const u8,
        ) builder.BindBuilderType(Instance) {
            return builder.BindBuilderType(Instance).init(instance, pattern);
        }

        pub fn chord(instance: *Instance, seq: []const u8) builder.ChordBuilderType(Instance) {
            return builder.ChordBuilderType(Instance).init(instance, seq);
        }

        pub fn command(instance: *Instance, name: []const u8) builder.CommandBuilderType(Instance) {
            return builder.CommandBuilderType(Instance).init(instance, name);
        }

        pub fn group(instance: *Instance) builder.GroupBuilderType(Instance) {
            return builder.GroupBuilderType(Instance).init(instance);
        }

        pub fn modifier_binding(instance: *Instance) builder.ModifierBuilderType(Instance) {
            return builder.ModifierBuilderType(Instance).init(instance);
        }

        pub fn timer(
            instance: *Instance,
            interval_ms: u32,
        ) builder.TimerBuilderType(Instance.TimerRegistry) {
            const Timer = builder.TimerBuilderType(Instance.TimerRegistry);

            return Timer.every(&instance.timer_registry, interval_ms);
        }

        pub fn macro_builder(
            instance: *Instance,
            comptime name: []const u8,
        ) builder.MacroBuilderType(Instance) {
            return builder.MacroBuilderType(Instance).init(instance, name);
        }

        pub fn sequence(
            instance: *Instance,
            pattern: []const u8,
        ) builder.SequenceBuilderType(Instance) {
            return builder.SequenceBuilderType(Instance).init(instance, pattern);
        }

        pub fn press(_: *Instance, value: Keycode) bool {
            return simulate_key.press(value);
        }

        pub fn key_down(_: *Instance, value: Keycode) bool {
            return simulate_key.key_down(value);
        }

        pub fn key_up(_: *Instance, value: Keycode) bool {
            return simulate_key.key_up(value);
        }

        pub fn send_chord(_: *Instance, value: Keycode, modifiers: modifier.Set) bool {
            return simulate_key.combination(&modifiers, value);
        }

        pub fn typer(_: *Instance) simulate_text.Typer {
            return simulate_text.Typer.init();
        }

        pub fn clipboard(_: *Instance) clipboard_mod.Clipboard {
            comptime require(platform.capabilities.clipboard, "clipboard");

            return clipboard_mod.Clipboard.init();
        }

        pub fn get_modifiers(instance: *Instance) modifier.Set {
            return instance.keyboard.get_modifiers();
        }

        pub fn process(instance: *Instance, parsed: *const Key) Response {
            assert(parsed.is_valid());

            return runtime.clamp(instance.resolve(parsed));
        }

        fn resolve(instance: *Instance, parsed: *const Key) Response {
            assert(parsed.is_valid());

            if (config.pass_injected and parsed.injected) {
                return .pass;
            }

            instance.keyboard.sync();

            if (parsed.down) {
                instance.keyboard.keydown(parsed.value);
            } else {
                instance.keyboard.keyup(parsed.value);
            }

            const key = parsed.with_modifiers(instance.keyboard.get_modifiers());

            if (instance.dispatch_callback(&key)) |response| {
                if (response != .pass) {
                    return response;
                }
            }

            const was_blocked = instance.blocked.load(.seq_cst);

            if (parsed.down) {
                _ = instance.sequence_registry.process(parsed.value, was_blocked);
            }

            const currently_blocked = instance.blocked.load(.seq_cst);

            if (currently_blocked) {
                if (parsed.injected) {
                    return .pass;
                }

                _ = instance.registry.process_blocked(&key);

                return .consume;
            }

            if (parsed.down) {
                const final = middleware_base.Next{
                    .context = instance,
                    .call = dispatch_final,
                };

                return instance.pipeline.process(&key, final);
            }

            return .pass;
        }

        fn dispatch_final(context: *anyopaque, key: *const Key) Response {
            assert(key.is_valid());

            const self: *Instance = @ptrCast(@alignCast(context));

            return self.dispatch_registries(key);
        }

        fn dispatch_callback(instance: *Instance, key: *const Key) ?Response {
            assert(key.is_valid());

            instance.mutex.lock();

            const callback_snapshot = instance.key_callback;
            const context_snapshot = instance.key_context;

            instance.mutex.unlock();

            const callback = callback_snapshot orelse return null;
            const context = context_snapshot orelse return null;

            return callback(context, key);
        }

        fn dispatch_registries(instance: *Instance, key: *const Key) Response {
            assert(key.is_valid());
            assert(key.down);

            const now_ms = platform.backend.time.now_ms();

            const chord_response = instance.chord_registry.process(key, now_ms);

            if (chord_response == .consume) {
                return .consume;
            }

            const command_response = instance.command_registry.process(key);

            if (command_response == .consume) {
                return .consume;
            }

            const invocation = instance.registry.resolve(key) orelse return .pass;

            assert(invocation.id >= 1);

            if (instance.oneshot_registry.process(invocation.id, key)) |response| {
                if (response == .consume) {
                    return .consume;
                }
            }

            const response = invocation.callback(invocation.context, key);

            if (response == .consume) {
                return .consume;
            }

            return .pass;
        }
    };
}
