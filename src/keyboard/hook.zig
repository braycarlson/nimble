const std = @import("std");

const w32 = @import("win32").everything;

const primitive = @import("../hook.zig");
const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const state = @import("../state.zig");
const response_mod = @import("../response.zig");
const key_event = @import("../event/key.zig");
const key_registry = @import("../registry/key.zig");
const chord_registry = @import("../registry/chord.zig");
const command_mod = @import("../registry/command.zig");
const timer_registry = @import("../registry/timer.zig");
const repeat_registry = @import("../automation/repeat.zig");
const macro_registry = @import("../automation/macro.zig");
const toggle_registry = @import("../automation/toggle.zig");
const sequence_registry = @import("../registry/sequence.zig");
const sender = @import("../sender/key.zig");
const typer_mod = @import("../sender/typer.zig");
const clipboard_mod = @import("../clipboard.zig");

const builder = @import("../builder/keyboard/root.zig");

const Key = key_event.Key;
const Response = response_mod.Response;
const KeyboardState = state.Keyboard;

pub const keycode_silent: u8 = keycode.silent;

pub const Error = error{
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
    pass_injected: bool = false,
};

pub const KeyCallback = *const fn (ctx: *anyopaque, value: u8, down: bool, extra: u64) ?u32;

pub fn KeyboardHook(comptime config: Config) type {
    const capacity = config.capacity;
    const capacity_chord = config.capacity_chord;
    const capacity_command = config.capacity_command;
    const capacity_timer = config.capacity_timer;
    const capacity_repeat = config.capacity_repeat;
    const capacity_macro = config.capacity_macro;
    const capacity_toggle = config.capacity_toggle;
    const capacity_sequence = config.capacity_sequence;

    return struct {
        const Self = @This();

        var instance: ?*Self = null;

        const Registry = key_registry.KeyRegistry(capacity);
        const ChordRegistry = chord_registry.ChordRegistry(capacity_chord);
        const CommandRegistry = command_mod.CommandRegistry(capacity_command);
        const TimerRegistry = timer_registry.TimerRegistry(capacity_timer);
        const RepeatRegistry = repeat_registry.RepeatRegistry(capacity_repeat);
        const MacroRegistry = macro_registry.MacroRegistry(capacity_macro);
        const ToggleRegistry = toggle_registry.ToggleRegistry(capacity_toggle);
        const SequenceRegistry = sequence_registry.SequenceRegistry(capacity_sequence);

        registry: Registry = Registry.init(),
        chord_registry: ChordRegistry = ChordRegistry.init(),
        command_registry: CommandRegistry = CommandRegistry.init(),
        timer_registry: TimerRegistry = TimerRegistry.init(),
        repeat_registry: RepeatRegistry = RepeatRegistry.init(),
        macro_registry: MacroRegistry = MacroRegistry.init(),
        toggle_registry: ToggleRegistry = ToggleRegistry.init(),
        sequence_registry: SequenceRegistry = SequenceRegistry.init(),
        keyboard: KeyboardState = KeyboardState.init(),
        blocked: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        mutex: std.Thread.Mutex = .{},
        hook_handle: ?primitive.Hook = null,
        module_handle: ?w32.HINSTANCE = null,
        key_callback: ?KeyCallback = null,
        key_context: ?*anyopaque = null,

        pub fn init() Self {
            return Self{};
        }

        pub fn deinit(self: *Self) void {
            self.stop();
            self.repeat_registry.stop_all();
            self.macro_registry.stop();
            self.timer_registry.clear_global();
            self.registry.clear();
            self.chord_registry.clear();
            self.command_registry.clear();
            self.timer_registry.clear();
            self.repeat_registry.clear();
            self.macro_registry.clear();
            self.toggle_registry.clear();
            self.sequence_registry.clear();
        }

        pub fn set_key_callback(self: *Self, callback: KeyCallback, context: *anyopaque) void {
            self.key_callback = callback;
            self.key_context = context;
        }

        pub fn clear_key_callback(self: *Self) void {
            self.key_callback = null;
            self.key_context = null;
        }

        pub fn start(self: *Self) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.running.load(.seq_cst)) {
                return;
            }

            self.module_handle = primitive.module();

            if (self.module_handle == null) {
                return error.HookInstallFailed;
            }

            self.timer_registry.set_global();
            self.blocked.store(false, .seq_cst);

            instance = self;

            self.hook_handle = primitive.Hook.install(.keyboard, hook_callback, self.module_handle.?);

            if (self.hook_handle == null) {
                instance = null;
                return error.HookInstallFailed;
            }

            self.running.store(true, .seq_cst);
        }

        pub fn stop(self: *Self) void {
            self.mutex.lock();

            if (!self.running.load(.seq_cst)) {
                self.mutex.unlock();
                return;
            }

            self.running.store(false, .seq_cst);
            self.mutex.unlock();

            if (self.hook_handle) |h| {
                _ = h.remove();
                self.hook_handle = null;
            }

            instance = null;
            self.blocked.store(false, .seq_cst);
        }

        pub fn is_running(self: *Self) bool {
            return self.running.load(.seq_cst);
        }

        pub fn is_paused(self: *Self) bool {
            return self.registry.is_paused();
        }

        pub fn set_paused(self: *Self, value: bool) void {
            self.registry.set_paused(value);
        }

        pub fn is_blocked(self: *Self) bool {
            return self.blocked.load(.seq_cst);
        }

        pub fn set_blocked(self: *Self, value: bool) void {
            self.blocked.store(value, .seq_cst);
            if (value) {
                self.sequence_registry.reset();
            }
        }

        pub fn bind(self: *Self, comptime pattern: []const u8) builder.BindBuilder(Self) {
            return builder.BindBuilder(Self).init(self, pattern);
        }

        pub fn chord(self: *Self, seq: []const u8) builder.ChordBuilder(Self) {
            return builder.ChordBuilder(Self).init(self, seq);
        }

        pub fn command(self: *Self, name: []const u8) builder.CommandBuilder(Self) {
            return builder.CommandBuilder(Self).init(self, name);
        }

        pub fn group(self: *Self) builder.GroupBuilder(Self) {
            return builder.GroupBuilder(Self).init(self);
        }

        pub fn modifier_binding(self: *Self) builder.ModifierBuilder(Self) {
            return builder.ModifierBuilder(Self).init(self);
        }

        pub fn timer(self: *Self, interval_ms: u32) builder.TimerBuilder(Self.TimerRegistry) {
            return builder.TimerBuilder(Self.TimerRegistry).init(&self.timer_registry, interval_ms);
        }

        pub fn macro_builder(self: *Self, comptime name: []const u8) builder.MacroBuilder(Self) {
            return builder.MacroBuilder(Self).init(self, name);
        }

        pub fn sequence(self: *Self, pattern: []const u8) builder.SequenceBuilder(Self) {
            return builder.SequenceBuilder(Self).init(self, pattern);
        }

        pub fn press(_: *Self, value: u8) bool {
            return sender.press(value);
        }

        pub fn key_down(_: *Self, value: u8) bool {
            return sender.key_down(value);
        }

        pub fn key_up(_: *Self, value: u8) bool {
            return sender.key_up(value);
        }

        pub fn send_chord(_: *Self, value: u8, modifiers: modifier.Set) bool {
            return sender.send_chord(value, modifiers);
        }

        pub fn typer(_: *Self) typer_mod.Typer {
            return typer_mod.Typer.init();
        }

        pub fn clipboard(_: *Self) clipboard_mod.Clipboard {
            return clipboard_mod.Clipboard.init();
        }

        pub fn get_modifiers(self: *Self) *modifier.Set {
            return self.keyboard.get_modifiers();
        }

        fn hook_callback(
            code: c_int,
            wparam: w32.WPARAM,
            lparam: w32.LPARAM,
        ) callconv(.c) w32.LRESULT {
            if (code < 0) {
                return primitive.next(code, wparam, lparam);
            }

            const self = instance orelse return primitive.next(code, wparam, lparam);

            const parsed = Key.parse(wparam, lparam) orelse {
                return primitive.next(code, wparam, lparam);
            };

            if (config.pass_injected and parsed.injected) {
                return primitive.next(code, wparam, lparam);
            }

            self.keyboard.sync();

            if (parsed.down) {
                self.keyboard.keydown(parsed.value);
            } else {
                self.keyboard.keyup(parsed.value);
            }

            const key = parsed.with_modifiers(self.keyboard.get_modifiers());

            if (self.key_callback) |callback| {
                if (self.key_context) |context| {
                    if (callback(context, parsed.value, parsed.down, parsed.extra)) |result| {
                        if (result == 0) {
                            return 1;
                        }
                    }
                }
            }

            const was_blocked = self.blocked.load(.seq_cst);

            if (parsed.down) {
                _ = self.sequence_registry.process(parsed.value, was_blocked);
            }

            const currently_blocked = self.blocked.load(.seq_cst);

            if (currently_blocked) {
                if (!parsed.down) {
                    return primitive.next(code, wparam, lparam);
                }

                if (self.registry.process_blocked(&key)) |response| {
                    if (response == .consume) {
                        return 1;
                    }
                }

                return 1;
            }

            if (parsed.down) {
                const now_ms = std.time.milliTimestamp();

                const chord_response = self.chord_registry.process(&key, now_ms);

                if (chord_response == .consume) {
                    return 1;
                }

                const command_response = self.command_registry.process(&key);

                if (command_response == .consume) {
                    return 1;
                }

                if (self.registry.process(&key)) |response| {
                    if (response == .consume) {
                        return 1;
                    }
                }
            }

            return primitive.next(code, wparam, lparam);
        }
    };
}
