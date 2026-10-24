const std = @import("std");

const builder = @import("builder/keyboard.zig");
const chord_registry = @import("registry/chord.zig");
const command_registry = @import("registry/command.zig");
const key_event = @import("event/key.zig");
const key_registry = @import("registry/key.zig");
const keycode = @import("keycode.zig");
const macro_registry = @import("registry/macro.zig");
const middleware_base = @import("middleware/base.zig");
const modifier = @import("modifier.zig");
const oneshot_registry = @import("registry/oneshot.zig");
const pattern_module = @import("builder/pattern.zig");
const platform = @import("platform.zig");
const repeat_registry = @import("registry/repeat.zig");
const response_module = @import("response.zig");
const runtime = @import("runtime.zig");
const sequence_registry = @import("registry/sequence.zig");
const state = @import("state.zig");
const sync = @import("sync.zig");
const timer_registry = @import("registry/timer.zig");
const toggle_registry = @import("registry/toggle.zig");

const assert = std.debug.assert;

const simulate_key = platform.backend.simulate.key;

const Key = key_event.Key;
const KeyboardState = state.Keyboard;
const Keycode = keycode.Keycode;
const Modifier = modifier.Set;
const Mutex = sync.Mutex;
const Response = response_module.Response;

pub const CapacityError = chord_registry.CapacityError ||
    command_registry.CapacityError ||
    key_registry.CapacityError ||
    macro_registry.CapacityError ||
    middleware_base.CapacityError ||
    oneshot_registry.CapacityError ||
    repeat_registry.CapacityError ||
    sequence_registry.CapacityError ||
    timer_registry.CapacityError ||
    toggle_registry.CapacityError;

pub const PlatformError = error{
    HookInstallFailed,
    WorkerStartFailed,
};

pub const RequestError = error{HookDuplicate} ||
    chord_registry.RequestError ||
    command_registry.RequestError ||
    key_registry.RequestError ||
    macro_registry.RequestError ||
    middleware_base.RequestError ||
    oneshot_registry.RequestError ||
    repeat_registry.RequestError ||
    sequence_registry.RequestError ||
    timer_registry.RequestError ||
    toggle_registry.RequestError;

pub const KeyboardCapacity = struct {
    binding_count_max: u32 = 0,
    chord_count_max: u32 = 0,
    command_count_max: u8 = 0,
    macro_count_max: u8 = 0,
    middleware_count_max: u8 = 0,
    oneshot_count_max: u32 = 0,
    repeat_count_max: u32 = 0,
    sequence_count_max: u32 = 0,
    timer_count_max: u32 = 0,
    toggle_count_max: u32 = 0,
};

pub const KeyboardOptions = struct {
    pass_injected: bool = false,
};

const KeyCallback = *const fn (context: *anyopaque, key: *const Key) Response;

const modifier_keys = [_]Keycode{
    .control_left,
    .control_right,
    .alt_left,
    .alt_right,
    .shift_left,
    .shift_right,
    .super_left,
    .super_right,
};

pub fn KeyboardType(comptime capacity: KeyboardCapacity) type {
    comptime validate(capacity);

    return struct {
        const Instance = @This();
        const Source = platform.backend.keyboard.SourceType(Instance);
        const ChordRegistry = TableType(capacity.chord_count_max, chord_registry.ChordRegistryType);
        const MacroRegistry = TableType(capacity.macro_count_max, macro_registry.MacroRegistryType);
        const Pipeline = TableType(capacity.middleware_count_max, middleware_base.PipelineType);
        const Registry = TableType(capacity.binding_count_max, key_registry.KeyRegistryType);
        const TimerRegistry = TableType(capacity.timer_count_max, timer_registry.TimerRegistryType);

        const CommandRegistry = TableType(
            capacity.command_count_max,
            command_registry.CommandRegistryType,
        );

        const OneshotRegistry = TableType(
            capacity.oneshot_count_max,
            oneshot_registry.OneShotRegistryType,
        );

        const RepeatRegistry = TableType(
            capacity.repeat_count_max,
            repeat_registry.RepeatRegistryType,
        );

        const SequenceRegistry = TableType(
            capacity.sequence_count_max,
            sequence_registry.SequenceRegistryType,
        );

        const ToggleRegistry = TableType(
            capacity.toggle_count_max,
            toggle_registry.ToggleRegistryType,
        );

        options: KeyboardOptions = .{},
        registry: Registry = table(Registry),
        chord_registry: ChordRegistry = table(ChordRegistry),
        command_registry: CommandRegistry = table(CommandRegistry),
        macro_registry: MacroRegistry = table(MacroRegistry),
        oneshot_registry: OneshotRegistry = table(OneshotRegistry),
        pipeline: Pipeline = table(Pipeline),
        repeat_registry: RepeatRegistry = table(RepeatRegistry),
        sequence_registry: SequenceRegistry = table(SequenceRegistry),
        timer_registry: TimerRegistry = table(TimerRegistry),
        toggle_registry: ToggleRegistry = table(ToggleRegistry),
        keyboard: KeyboardState = KeyboardState.init(),
        blocked: std.atomic.Value(bool) = .init(false),
        running: std.atomic.Value(bool) = .init(false),
        mutex: Mutex = .{},
        source: Source = Source.init(),
        key_callback: ?KeyCallback = null,
        key_context: ?*anyopaque = null,

        pub const Binding = enum(u32) { _ };
        pub const Chord = enum(u32) { _ };
        pub const Command = enum(u32) { _ };
        pub const Macro = enum(u32) { _ };
        pub const Middleware = enum(u8) { _ };
        pub const Oneshot = enum(u32) { _ };
        pub const Repeat = enum(u32) { _ };
        pub const Sequence = enum(u32) { _ };
        pub const Timer = enum(u32) { _ };
        pub const Toggle = enum(u32) { _ };

        pub fn init(instance: *Instance, options: KeyboardOptions) PlatformError!void {
            instance.* = .{ .options = options };

            if (capacity.macro_count_max > 0) {
                instance.macro_registry.start() catch return error.WorkerStartFailed;
            }

            errdefer if (capacity.macro_count_max > 0) instance.macro_registry.deinit();

            if (capacity.repeat_count_max > 0) {
                instance.repeat_registry.start() catch return error.WorkerStartFailed;
            }

            assert(!instance.is_running());
            assert(!instance.is_blocked());
        }

        pub fn deinit(instance: *Instance) void {
            instance.stop();

            if (capacity.repeat_count_max > 0) {
                instance.repeat_registry.deinit();
            }

            if (capacity.macro_count_max > 0) {
                instance.macro_registry.deinit();
            }

            instance.* = undefined;
        }

        pub fn add_middleware(
            instance: *Instance,
            comptime T: type,
            middleware: *T,
        ) CapacityError!Middleware {
            comptime require(Instance, "pipeline", "middleware_count_max");

            const slot = try instance.pipeline.add(T, middleware);
            return @fromBackingInt(slot);
        }

        pub fn bind(
            instance: *Instance,
            comptime pattern: []const u8,
        ) builder.BindBuilderType(Instance) {
            comptime require(Instance, "registry", "binding_count_max");

            const parsed = comptime pattern_module.parse(pattern);
            return .{ .hook = instance, .key = parsed.key, .modifiers = parsed.modifiers };
        }

        pub fn bind_key(
            instance: *Instance,
            key: Keycode,
            modifiers: Modifier,
        ) builder.BindBuilderType(Instance) {
            comptime require(Instance, "registry", "binding_count_max");

            return .{ .hook = instance, .key = key, .modifiers = modifiers };
        }

        pub fn block(instance: *Instance) void {
            const was_blocked = instance.blocked.swap(true, .seq_cst);

            if (!was_blocked) release_modifiers();

            assert(instance.is_blocked());
        }

        pub fn chord(
            instance: *Instance,
            keys: []const Keycode,
        ) builder.ChordBuilderType(Instance) {
            comptime require(Instance, "chord_registry", "chord_count_max");

            return .{ .hook = instance, .keys = keys };
        }

        pub fn clear_key_callback(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            instance.key_callback = null;
            instance.key_context = null;
        }

        pub fn command(
            instance: *Instance,
            name: []const u8,
        ) builder.CommandBuilderType(Instance) {
            comptime require(Instance, "command_registry", "command_count_max");

            return .{ .hook = instance, .name = name };
        }

        pub fn get_modifiers(instance: *const Instance) Modifier {
            return instance.keyboard.get_modifiers();
        }

        pub fn group(instance: *Instance) builder.GroupBuilderType(Instance) {
            comptime require(Instance, "registry", "binding_count_max");

            return .{ .hook = instance };
        }

        pub fn is_blocked(instance: *const Instance) bool {
            return instance.blocked.load(.seq_cst);
        }

        pub fn is_running(instance: *const Instance) bool {
            return instance.running.load(.seq_cst);
        }

        pub fn macro(
            instance: *Instance,
            comptime name: []const u8,
        ) builder.MacroBuilderType(Instance) {
            comptime require(Instance, "macro_registry", "macro_count_max");
            comptime assert(name.len > 0);

            const player = struct {
                fn play(pointer: *anyopaque, key: *const Key) Response {
                    assert(key.is_valid());

                    const hook: *Instance = @ptrCast(@alignCast(pointer));

                    _ = hook.macro_registry.play_by_name(name);

                    return .consume;
                }
            };

            return .{ .hook = instance, .name = name, .play_callback = player.play };
        }

        pub fn process(instance: *Instance, event: *const Key) Response {
            assert(event.is_valid());

            return runtime.clamp(instance.resolve(event));
        }

        pub fn remove_middleware(instance: *Instance, handle: Middleware) RequestError!void {
            comptime require(Instance, "pipeline", "middleware_count_max");

            return instance.pipeline.remove(@backingInt(handle));
        }

        pub fn sequence(
            instance: *Instance,
            text: []const u8,
        ) builder.SequenceBuilderType(Instance) {
            comptime require(Instance, "sequence_registry", "sequence_count_max");

            return .{ .hook = instance, .text = text };
        }

        pub fn set_key_callback(
            instance: *Instance,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner, *const Key) Response,
        ) void {
            const wrapper = struct {
                fn invoke(pointer: *anyopaque, key: *const Key) Response {
                    const typed: *Owner = @ptrCast(@alignCast(pointer));
                    return callback(typed, key);
                }
            };

            instance.mutex.lock();
            defer instance.mutex.unlock();

            instance.key_callback = wrapper.invoke;
            instance.key_context = owner;
        }

        pub fn start(instance: *Instance) (PlatformError || RequestError)!void {
            assert(runtime.is_open());

            instance.mutex.lock();
            defer instance.mutex.unlock();

            if (instance.is_running()) return;

            instance.blocked.store(false, .seq_cst);

            try instance.source.install(instance);

            if (capacity.timer_count_max > 0) {
                instance.timer_registry.arm();
            }

            instance.running.store(true, .seq_cst);

            assert(instance.is_running());
        }

        pub fn start_timer(instance: *Instance, handle: Timer) RequestError!void {
            comptime require(Instance, "timer_registry", "timer_count_max");

            return instance.timer_registry.start(@backingInt(handle));
        }

        pub fn stop(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            if (!instance.is_running()) return;

            instance.running.store(false, .seq_cst);

            instance.source.remove();

            if (capacity.timer_count_max > 0) {
                instance.timer_registry.disarm();
            }

            instance.blocked.store(false, .seq_cst);

            assert(!instance.is_running());
            assert(!instance.is_blocked());
        }

        pub fn stop_timer(instance: *Instance, handle: Timer) RequestError!void {
            comptime require(Instance, "timer_registry", "timer_count_max");

            return instance.timer_registry.stop(@backingInt(handle));
        }

        pub fn timer(instance: *Instance, interval_ms: u32) builder.TimerBuilderType(Instance) {
            comptime require(Instance, "timer_registry", "timer_count_max");

            return .{ .hook = instance, .interval_ms = interval_ms };
        }

        pub fn unbind(instance: *Instance, handle: Binding) RequestError!void {
            comptime require(Instance, "registry", "binding_count_max");

            return instance.registry.unregister(@backingInt(handle));
        }

        pub fn unbind_chord(instance: *Instance, handle: Chord) RequestError!void {
            comptime require(Instance, "chord_registry", "chord_count_max");

            return instance.chord_registry.unregister(@backingInt(handle));
        }

        pub fn unbind_sequence(instance: *Instance, handle: Sequence) RequestError!void {
            comptime require(Instance, "sequence_registry", "sequence_count_max");

            return instance.sequence_registry.unregister(@backingInt(handle));
        }

        pub fn unblock(instance: *Instance) void {
            const was_blocked = instance.blocked.swap(false, .seq_cst);

            if (was_blocked) release_modifiers();

            assert(!instance.is_blocked());
        }

        fn resolve(instance: *Instance, event: *const Key) Response {
            assert(event.is_valid());

            if (instance.options.pass_injected) {
                if (event.injected) return .pass;
            }

            instance.keyboard.sync();

            if (event.down) {
                instance.keyboard.keydown(event.value);
            } else {
                instance.keyboard.keyup(event.value);
                instance.release_repeats(event.value);
            }

            const key = event.with_modifiers(instance.keyboard.get_modifiers());
            const verdict = instance.dispatch_callback(&key);
            if (verdict != .pass) return verdict;

            const was_blocked = instance.is_blocked();

            if (event.down) instance.dispatch_sequences(event.value, was_blocked);

            if (instance.is_blocked()) return instance.dispatch_blocked(&key);
            if (!event.down) return .pass;
            if (capacity.middleware_count_max == 0) return instance.dispatch_registries(&key);

            const final = middleware_base.Next{
                .context = instance,
                .call = dispatch_final,
            };

            return instance.pipeline.process(&key, final);
        }

        fn release_repeats(instance: *Instance, value: Keycode) void {
            if (capacity.repeat_count_max == 0) return;

            instance.repeat_registry.release(value);
        }

        fn dispatch_sequences(instance: *Instance, value: Keycode, was_blocked: bool) void {
            if (capacity.sequence_count_max == 0) return;

            _ = instance.sequence_registry.process(value, was_blocked);
        }

        fn dispatch_blocked(instance: *Instance, key: *const Key) Response {
            assert(key.is_valid());

            if (key.injected) return .pass;

            if (capacity.binding_count_max > 0) {
                if (key.down) {
                    _ = instance.registry.process_blocked(key);
                }
            }

            return .consume;
        }

        fn dispatch_final(context: *anyopaque, key: *const Key) Response {
            assert(key.is_valid());

            const instance: *Instance = @ptrCast(@alignCast(context));
            return instance.dispatch_registries(key);
        }

        fn dispatch_callback(instance: *Instance, key: *const Key) Response {
            assert(key.is_valid());

            instance.mutex.lock();

            const callback_snapshot = instance.key_callback;
            const context_snapshot = instance.key_context;

            instance.mutex.unlock();

            const callback = callback_snapshot orelse return .pass;
            const context = context_snapshot orelse return .pass;

            return callback(context, key);
        }

        fn dispatch_registries(instance: *Instance, key: *const Key) Response {
            assert(key.is_valid());
            assert(key.down);

            if (capacity.chord_count_max > 0) {
                const now_ms = platform.backend.time.now_ms();
                if (instance.chord_registry.process(key, now_ms) == .consume) return .consume;
            }

            if (capacity.command_count_max > 0) {
                if (instance.command_registry.process(key) == .consume) return .consume;
            }

            if (capacity.binding_count_max == 0) return .pass;

            const invocation = instance.registry.resolve(key) orelse return .pass;

            assert(invocation.id >= 1);

            if (instance.dispatch_chains(invocation.id, key)) |verdict| return verdict;
            return invocation.callback(invocation.context, key);
        }

        fn dispatch_chains(instance: *Instance, binding_id: u32, key: *const Key) ?Response {
            assert(binding_id >= 1);
            assert(key.down);

            if (capacity.toggle_count_max > 0) {
                if (instance.toggle_registry.process_toggle(binding_id)) return .consume;
                if (instance.toggle_registry.process(binding_id, key)) |verdict| return verdict;
            }

            if (capacity.oneshot_count_max > 0) {
                if (instance.oneshot_registry.process(binding_id, key)) |verdict| return verdict;
            }

            if (capacity.repeat_count_max > 0) {
                if (instance.repeat_registry.press(binding_id)) return .consume;
            }

            return null;
        }
    };
}

pub fn require(comptime Hook: type, comptime field: []const u8, comptime bound: []const u8) void {
    if (@FieldType(Hook, field) == void) {
        @compileError("nimble: this keyboard hook was built without " ++ field ++
            ", so set " ++ bound ++ " in its KeyboardCapacity");
    }
}

fn validate(comptime capacity: KeyboardCapacity) void {
    const chained = [_]u32{
        capacity.oneshot_count_max,
        capacity.repeat_count_max,
        capacity.toggle_count_max,
    };

    for (chained) |count| {
        if (count > 0) {
            if (capacity.binding_count_max == 0) {
                @compileError("nimble: a oneshot, repeat, or toggle is a binding, " ++
                    "so it needs binding_count_max in the KeyboardCapacity");
            }
        }
    }
}

fn TableType(comptime count: u32, comptime Constructor: anytype) type {
    if (count == 0) return void;
    return Constructor(count);
}

fn table(comptime Table: type) Table {
    if (Table == void) return {};
    return Table.init();
}

fn release_modifiers() void {
    _ = simulate_key.dummy();

    for (modifier_keys) |value| {
        _ = simulate_key.key_up(value);
    }
}

const testing = std.testing;

const mock = platform.mock;

const Counter = struct {
    hits: u32 = 0,

    fn on_key(counter: *Counter, _: *const Key) Response {
        counter.hits += 1;

        return .consume;
    }
};

test KeyboardType {
    mock.reset();

    try runtime.open(.{ .mode = .grab });
    defer runtime.close();

    const Keyboard = KeyboardType(.{ .binding_count_max = 4 });
    const keyboard = try testing.allocator.create(Keyboard);
    defer testing.allocator.destroy(keyboard);

    try keyboard.init(.{});
    defer keyboard.deinit();

    var counter = Counter{};

    const save = try keyboard.bind("Ctrl+S").on(Counter, &counter, Counter.on_key);

    try keyboard.start();
    defer keyboard.stop();

    mock.loop.push_key(.{ .value = .control_left, .down = true });
    mock.loop.push_key(.{ .value = .s, .down = true });
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), counter.hits);
    try testing.expectEqual(Response.consume, mock.loop.response_at(1));

    try keyboard.unbind(save);
    try testing.expectError(error.HandleUnknown, keyboard.unbind(save));
}

test KeyboardCapacity {
    const Bare = KeyboardType(.{});
    const Chorded = KeyboardType(.{ .binding_count_max = 4, .chord_count_max = 4 });

    try testing.expect(@FieldType(Bare, "registry") == void);
    try testing.expect(@FieldType(Chorded, "registry") != void);
    try testing.expect(@FieldType(Chorded, "chord_registry") != void);
    try testing.expect(@FieldType(Chorded, "timer_registry") == void);
    try testing.expect(@sizeOf(Bare) < @sizeOf(Chorded));
}

test KeyboardOptions {
    mock.reset();

    try runtime.open(.{ .mode = .grab });
    defer runtime.close();

    const Keyboard = KeyboardType(.{ .binding_count_max = 1 });
    const keyboard = try testing.allocator.create(Keyboard);
    defer testing.allocator.destroy(keyboard);

    try keyboard.init(.{ .pass_injected = true });
    defer keyboard.deinit();

    var counter = Counter{};

    _ = try keyboard.bind("A").on(Counter, &counter, Counter.on_key);

    try keyboard.start();
    defer keyboard.stop();

    mock.loop.push_key(.{ .value = .a, .down = true, .injected = true });
    mock.loop.push_key(.{ .value = .a, .down = true });
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), counter.hits);
    try testing.expectEqual(Response.pass, mock.loop.response_at(0));
    try testing.expectEqual(Response.consume, mock.loop.response_at(1));
}
