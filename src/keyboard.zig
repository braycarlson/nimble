const std = @import("std");

const builder = @import("builder.zig").keyboard;
const chord_registry = @import("registry.zig").chord;
const command_registry = @import("registry.zig").command;
const key_event = @import("event.zig").key;
const key_registry = @import("registry.zig").key;
const keycode = @import("keycode.zig");
const macro_registry = @import("registry.zig").macro;
const middleware_module = @import("middleware.zig");
const modifier = @import("modifier.zig");
const oneshot_registry = @import("registry.zig").oneshot;
const pattern_module = @import("builder.zig").pattern;
const platform = @import("platform.zig");
const repeat_registry = @import("registry.zig").repeat;
const response_module = @import("response.zig");
const runtime_module = @import("runtime.zig");
const sequence_registry = @import("registry.zig").sequence;
const state = @import("state.zig");
const sync = @import("sync.zig");
const timer_registry = @import("registry.zig").timer;
const toggle_registry = @import("registry.zig").toggle;

const assert = std.debug.assert;

const ChordRegistryType = chord_registry.ChordRegistryType;
const CommandRegistryType = command_registry.CommandRegistryType;
const Key = key_event.Key;
const KeyboardState = state.Keyboard;
const Keycode = keycode.Keycode;
const KeyRegistryType = key_registry.KeyRegistryType;
const MacroRegistryType = macro_registry.MacroRegistryType;
const Modifier = modifier.Set;
const Mutex = sync.Mutex;
const OneShotRegistryType = oneshot_registry.OneShotRegistryType;
const RepeatRegistryType = repeat_registry.RepeatRegistryType;
const Response = response_module.Response;
const RuntimeType = runtime_module.RuntimeType;
const SequenceRegistryType = sequence_registry.SequenceRegistryType;
const TimerRegistryType = timer_registry.TimerRegistryType;
const ToggleRegistryType = toggle_registry.ToggleRegistryType;

pub const CapacityError = chord_registry.CapacityError ||
    command_registry.CapacityError ||
    key_registry.CapacityError ||
    macro_registry.CapacityError ||
    middleware_module.CapacityError ||
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
    middleware_module.RequestError ||
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

pub fn KeyboardType(comptime Platform: type, comptime capacity: KeyboardCapacity) type {
    comptime validate(capacity);

    return struct {
        const Instance = @This();
        const Pipeline = TableType(capacity.middleware_count_max, middleware_module.PipelineType);
        const Runtime = RuntimeType(Platform);
        const TimerRegistry = TableType(capacity.timer_count_max, TimerRegistryType);

        const ChordRegistry = PlatformTableType(
            Platform,
            capacity.chord_count_max,
            ChordRegistryType,
        );

        const CommandRegistry = TableType(capacity.command_count_max, CommandRegistryType);

        const MacroRegistry = PlatformTableType(
            Platform,
            capacity.macro_count_max,
            MacroRegistryType,
        );

        const OneshotRegistry = TableType(capacity.oneshot_count_max, OneShotRegistryType);
        const Registry = PlatformTableType(Platform, capacity.binding_count_max, KeyRegistryType);

        const RepeatRegistry = PlatformTableType(
            Platform,
            capacity.repeat_count_max,
            RepeatRegistryType,
        );

        const SequenceRegistry = PlatformTableType(
            Platform,
            capacity.sequence_count_max,
            SequenceRegistryType,
        );

        const ToggleRegistry = PlatformTableType(
            Platform,
            capacity.toggle_count_max,
            ToggleRegistryType,
        );

        platform: *Platform,
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
        timer_id: ?platform.TimerId = null,
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

        pub const capabilities: platform.Capabilities = Platform.capabilities;

        pub fn init(
            instance: *Instance,
            runtime: *Runtime,
            options: KeyboardOptions,
        ) PlatformError!void {
            instance.* = .{ .platform = &runtime.platform, .options = options };

            instance.wire();

            if (capacity.macro_count_max > 0) {
                instance.macro_registry.start(instance.platform) catch {
                    return error.WorkerStartFailed;
                };
            }

            errdefer if (capacity.macro_count_max > 0) instance.macro_registry.deinit();

            if (capacity.repeat_count_max > 0) {
                instance.repeat_registry.start(instance.platform) catch {
                    return error.WorkerStartFailed;
                };
            }

            assert(!instance.is_running());
            assert(!instance.is_blocked());
        }

        fn wire(instance: *Instance) void {
            assert(instance.timer_id == null);

            if (Registry != void) instance.registry.platform = instance.platform;
            if (ChordRegistry != void) instance.chord_registry.platform = instance.platform;
            if (SequenceRegistry != void) instance.sequence_registry.platform = instance.platform;
            if (ToggleRegistry != void) instance.toggle_registry.platform = instance.platform;
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

            if (!was_blocked) instance.release_modifiers();

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

        pub fn command(instance: *Instance, name: []const u8) builder.CommandBuilderType(Instance) {
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

            return runtime_module.clamp(instance.platform.runtime_mode(), instance.resolve(event));
        }

        pub fn remove_middleware(instance: *Instance, handle: Middleware) RequestError!void {
            assert(@backingInt(handle) < capacity.middleware_count_max);

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
            assert(instance.platform.runtime_mode().is_valid());

            instance.mutex.lock();
            defer instance.mutex.unlock();

            if (instance.is_running()) return;

            instance.blocked.store(false, .seq_cst);

            try instance.platform.keyboard_install(Instance, instance);

            if (capacity.timer_count_max > 0) {
                instance.timer_arm();
            }

            instance.running.store(true, .seq_cst);

            assert(instance.is_running());
        }

        pub fn start_timer(instance: *Instance, handle: Timer) RequestError!void {
            assert(@backingInt(handle) >= 1);

            comptime require(Instance, "timer_registry", "timer_count_max");

            const now_ms = instance.platform.now_ms();

            return instance.timer_registry.start(@backingInt(handle), now_ms);
        }

        pub fn stop(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            if (!instance.is_running()) return;

            instance.running.store(false, .seq_cst);

            instance.platform.keyboard_remove();

            if (capacity.timer_count_max > 0) {
                instance.timer_disarm();
            }

            instance.blocked.store(false, .seq_cst);

            assert(!instance.is_running());
            assert(!instance.is_blocked());
        }

        pub fn stop_timer(instance: *Instance, handle: Timer) RequestError!void {
            assert(@backingInt(handle) >= 1);

            comptime require(Instance, "timer_registry", "timer_count_max");

            return instance.timer_registry.stop(@backingInt(handle));
        }

        pub fn timer(instance: *Instance, interval_ms: u32) builder.TimerBuilderType(Instance) {
            comptime require(Instance, "timer_registry", "timer_count_max");

            return .{ .hook = instance, .interval_ms = interval_ms };
        }

        pub fn unbind(instance: *Instance, handle: Binding) RequestError!void {
            assert(@backingInt(handle) >= 1);

            comptime require(Instance, "registry", "binding_count_max");

            return instance.registry.unregister(@backingInt(handle));
        }

        pub fn unbind_chord(instance: *Instance, handle: Chord) RequestError!void {
            assert(@backingInt(handle) >= 1);

            comptime require(Instance, "chord_registry", "chord_count_max");

            return instance.chord_registry.unregister(@backingInt(handle));
        }

        pub fn unbind_sequence(instance: *Instance, handle: Sequence) RequestError!void {
            assert(@backingInt(handle) >= 1);

            comptime require(Instance, "sequence_registry", "sequence_count_max");

            return instance.sequence_registry.unregister(@backingInt(handle));
        }

        pub fn unblock(instance: *Instance) void {
            const was_blocked = instance.blocked.swap(false, .seq_cst);

            if (was_blocked) instance.release_modifiers();

            assert(!instance.is_blocked());
        }

        fn resolve(instance: *Instance, event: *const Key) Response {
            assert(event.is_valid());

            if (instance.options.pass_injected) {
                if (event.injected) return .pass;
            }

            instance.keyboard.sync(Platform, instance.platform);

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

            const final = middleware_module.Next{ .context = instance, .call = dispatch_final };

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
                const now_ms = instance.platform.now_ms();
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

        fn release_modifiers(instance: *Instance) void {
            _ = instance.platform.key_dummy();

            for (modifier_keys) |value| {
                _ = instance.platform.key_up(value);
            }
        }

        fn timer_arm(instance: *Instance) void {
            if (instance.timer_id != null) return;

            const interval_ms = timer_registry.tick_interval_ms;

            instance.timer_id = instance.platform.timer_start(interval_ms, timer_tick, instance);
        }

        fn timer_disarm(instance: *Instance) void {
            const timer_id = instance.timer_id orelse return;

            _ = instance.platform.timer_stop(timer_id);

            instance.timer_id = null;
        }

        fn timer_tick(context: *anyopaque) void {
            const instance: *Instance = @ptrCast(@alignCast(context));

            assert(capacity.timer_count_max > 0);
            assert(instance.timer_id != null);

            instance.timer_registry.tick(instance.platform.now_ms());
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

fn PlatformTableType(
    comptime Platform: type,
    comptime count: u32,
    comptime Constructor: anytype,
) type {
    if (count == 0) return void;
    return Constructor(Platform, count);
}

fn table(comptime Table: type) Table {
    if (Table == void) return {};
    return Table.init();
}

const testing = std.testing;

const Fake = platform.Fake;
const FakeRuntime = RuntimeType(Fake);

const Counter = struct {
    hits: u32 = 0,

    fn on_key(counter: *Counter, _: *const Key) Response {
        counter.hits += 1;

        return .consume;
    }
};

fn runtime_create(options: platform.Options) !*FakeRuntime {
    const runtime = try testing.allocator.create(FakeRuntime);
    errdefer testing.allocator.destroy(runtime);

    try runtime.init(options);

    return runtime;
}

fn runtime_destroy(runtime: *FakeRuntime) void {
    runtime.deinit();

    testing.allocator.destroy(runtime);
}

test KeyboardType {
    const runtime = try runtime_create(.{ .mode = .grab });
    defer runtime_destroy(runtime);

    const Keyboard = FakeRuntime.KeyboardType(.{ .binding_count_max = 4 });
    const keyboard = try testing.allocator.create(Keyboard);
    defer testing.allocator.destroy(keyboard);

    try keyboard.init(runtime, .{});
    defer keyboard.deinit();

    var counter = Counter{};

    const save = try keyboard.bind("Ctrl+S").on(Counter, &counter, Counter.on_key);

    try keyboard.start();
    defer keyboard.stop();

    runtime.platform.loop.push_key(.{ .value = .control_left, .down = true });
    runtime.platform.loop.push_key(.{ .value = .s, .down = true });
    runtime.run();

    try testing.expectEqual(@as(u32, 1), counter.hits);
    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(1));

    try keyboard.unbind(save);
    try testing.expectError(error.HandleUnknown, keyboard.unbind(save));
}

test KeyboardCapacity {
    const Bare = KeyboardType(Fake, .{});
    const Chorded = KeyboardType(Fake, .{ .binding_count_max = 4, .chord_count_max = 4 });

    try testing.expect(@FieldType(Bare, "registry") == void);
    try testing.expect(@FieldType(Chorded, "registry") != void);
    try testing.expect(@FieldType(Chorded, "chord_registry") != void);
    try testing.expect(@FieldType(Chorded, "timer_registry") == void);
    try testing.expect(@sizeOf(Bare) < @sizeOf(Chorded));
}

test KeyboardOptions {
    const runtime = try runtime_create(.{ .mode = .grab });
    defer runtime_destroy(runtime);

    const Keyboard = FakeRuntime.KeyboardType(.{ .binding_count_max = 1 });
    const keyboard = try testing.allocator.create(Keyboard);
    defer testing.allocator.destroy(keyboard);

    try keyboard.init(runtime, .{ .pass_injected = true });
    defer keyboard.deinit();

    var counter = Counter{};

    _ = try keyboard.bind("A").on(Counter, &counter, Counter.on_key);

    try keyboard.start();
    defer keyboard.stop();

    runtime.platform.loop.push_key(.{ .value = .a, .down = true, .injected = true });
    runtime.platform.loop.push_key(.{ .value = .a, .down = true });
    runtime.run();

    try testing.expectEqual(@as(u32, 1), counter.hits);
    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(0));
    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(1));
}
