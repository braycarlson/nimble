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
    pass_injected: bool = false,
};

var instance_global: std.atomic.Value(?*anyopaque) = std.atomic.Value(?*anyopaque).init(null);
var proc_global: std.atomic.Value(?*const fn (c_int, w32.WPARAM, w32.LPARAM) callconv(.c) w32.LRESULT) = std.atomic.Value(?*const fn (c_int, w32.WPARAM, w32.LPARAM) callconv(.c) w32.LRESULT).init(null);

pub fn KeyboardHook(comptime config: Config) type {
    const capacity = config.capacity;
    const capacity_chord = config.capacity_chord;
    const capacity_command = config.capacity_command;
    const capacity_timer = config.capacity_timer;
    const capacity_repeat = config.capacity_repeat;
    const capacity_macro = config.capacity_macro;
    const capacity_toggle = config.capacity_toggle;

    return struct {
        const Self = @This();

        const Registry = key_registry.KeyRegistry(capacity);
        const ChordRegistry = chord_registry.ChordRegistry(capacity_chord);
        const CommandRegistry = command_mod.CommandRegistry(capacity_command);
        const TimerRegistry = timer_registry.TimerRegistry(capacity_timer);
        const RepeatRegistry = repeat_registry.RepeatRegistry(capacity_repeat);
        const MacroRegistry = macro_registry.MacroRegistry(capacity_macro);
        const ToggleRegistry = toggle_registry.ToggleRegistry(capacity_toggle);

        registry: Registry = Registry.init(),
        chord_registry: ChordRegistry = ChordRegistry.init(),
        command_registry: CommandRegistry = CommandRegistry.init(),
        timer_registry: TimerRegistry = TimerRegistry.init(),
        repeat_registry: RepeatRegistry = RepeatRegistry.init(),
        macro_registry: MacroRegistry = MacroRegistry.init(),
        toggle_registry: ToggleRegistry = ToggleRegistry.init(),
        keyboard: KeyboardState = KeyboardState.init(),
        running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        mutex: std.Thread.Mutex = .{},
        hook_handle: ?primitive.Hook = null,
        module_handle: ?w32.HINSTANCE = null,

        pub fn init() Self {
            return Self{
                .registry = Registry.init(),
                .chord_registry = ChordRegistry.init(),
                .command_registry = CommandRegistry.init(),
                .timer_registry = TimerRegistry.init(),
                .repeat_registry = RepeatRegistry.init(),
                .macro_registry = MacroRegistry.init(),
                .toggle_registry = ToggleRegistry.init(),
                .keyboard = KeyboardState.init(),
                .running = std.atomic.Value(bool).init(false),
                .mutex = .{},
                .hook_handle = null,
                .module_handle = null,
            };
        }

        pub fn deinit(self: *Self) void {
            self.stop();
            self.timer_registry.stop_all();
            self.timer_registry.clear_global();
            self.repeat_registry.stop_all();
            self.macro_registry.stop();
            self.registry.clear();
            self.chord_registry.clear();
            self.command_registry.clear();
            self.timer_registry.clear();
            self.repeat_registry.clear();
            self.macro_registry.clear();
            self.toggle_registry.clear();
        }

        pub fn start(self: *Self) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.running.load(.acquire)) {
                return;
            }

            self.module_handle = primitive.module();

            if (self.module_handle == null) {
                return error.HookInstallFailed;
            }

            self.timer_registry.set_global();

            instance_global.store(self, .release);
            proc_global.store(Self.hook_proc, .release);

            self.hook_handle = primitive.Hook.install(.keyboard, wrapper_proc, self.module_handle.?);

            if (self.hook_handle == null) {
                instance_global.store(null, .release);
                proc_global.store(null, .release);
                return error.HookInstallFailed;
            }

            self.running.store(true, .release);
        }

        pub fn stop(self: *Self) void {
            self.mutex.lock();

            if (!self.running.load(.acquire)) {
                self.mutex.unlock();
                return;
            }

            self.running.store(false, .release);
            self.mutex.unlock();

            if (self.hook_handle) |h| {
                _ = h.remove();
                self.hook_handle = null;
            }

            instance_global.store(null, .release);
            proc_global.store(null, .release);
        }

        pub fn is_running(self: *Self) bool {
            return self.running.load(.acquire);
        }

        pub fn is_paused(self: *Self) bool {
            return self.registry.is_paused();
        }

        pub fn set_paused(self: *Self, value: bool) void {
            self.registry.set_paused(value);
        }

        pub fn bind(self: *Self, comptime pattern: []const u8) builder.BindBuilder(Self) {
            return builder.BindBuilder(Self).init(self, pattern);
        }

        pub fn chord(self: *Self, sequence: []const u8) builder.ChordBuilder(Self) {
            return builder.ChordBuilder(Self).init(self, sequence);
        }

        pub fn command(self: *Self, name: []const u8) builder.CommandBuilder(Self) {
            return builder.CommandBuilder(Self).init(self, name);
        }

        pub fn group(self: *Self) builder.GroupBuilder(Self) {
            return builder.GroupBuilder(Self).init(self);
        }

        pub fn ctrl(self: *Self) builder.ModifierBuilder(Self) {
            return builder.ModifierBuilder(Self).init(self).ctrl();
        }

        pub fn alt(self: *Self) builder.ModifierBuilder(Self) {
            return builder.ModifierBuilder(Self).init(self).alt();
        }

        pub fn shift(self: *Self) builder.ModifierBuilder(Self) {
            return builder.ModifierBuilder(Self).init(self).shift();
        }

        pub fn win(self: *Self) builder.ModifierBuilder(Self) {
            return builder.ModifierBuilder(Self).init(self).win();
        }

        pub fn timer(self: *Self, interval_ms: u32) builder.TimerBuilder(TimerRegistry) {
            return builder.TimerBuilder(TimerRegistry).init(&self.timer_registry, interval_ms);
        }

        pub fn every(self: *Self, ms: u32) builder.TimerBuilder(TimerRegistry) {
            return builder.TimerBuilder(TimerRegistry).every(&self.timer_registry, ms);
        }

        pub fn after(self: *Self, ms: u32) builder.TimerBuilder(TimerRegistry) {
            return builder.TimerBuilder(TimerRegistry).after(&self.timer_registry, ms);
        }

        pub fn macro(self: *Self, name: []const u8) builder.MacroBuilder(Self) {
            return builder.MacroBuilder(Self).init(self, name);
        }

        pub fn with_modifiers(self: *Self) builder.ModifierBuilder(Self) {
            return builder.ModifierBuilder(Self).init(self);
        }

        pub fn send(_: *Self, text: []const u8) void {
            _ = typer_mod.send(text) catch {};
        }

        pub fn send_with_delay(_: *Self, text: []const u8, delay_ms: u32) void {
            _ = typer_mod.send_with_delay(text, delay_ms) catch {};
        }

        pub fn paste_text(_: *Self, text: []const u8) !void {
            try clipboard_mod.set(text);
            _ = clipboard_mod.paste();
        }

        pub fn send_key(_: *Self, comptime pattern: []const u8) void {
            sender.send(pattern);
        }

        pub fn send_key_with_modifiers(_: *Self, value: u8, modifiers: modifier.Set) void {
            sender.send_with_modifiers(value, &modifiers);
        }

        pub fn type_text(_: *Self, text: []const u8) typer_mod.Error!u32 {
            return typer_mod.send(text);
        }

        pub fn type_text_with_delay(_: *Self, text: []const u8, delay_ms: u32) typer_mod.Error!u32 {
            return typer_mod.send_with_delay(text, delay_ms);
        }

        fn hook_proc(
            keycode_hook: c_int,
            wparam: w32.WPARAM,
            lparam: w32.LPARAM,
        ) callconv(.c) w32.LRESULT {
            if (keycode_hook < 0) {
                return primitive.next(keycode_hook, wparam, lparam);
            }

            const parsed = Key.parse(wparam, lparam) orelse {
                return primitive.next(keycode_hook, wparam, lparam);
            };

            if (parsed.injected and !config.pass_injected) {
                return primitive.next(keycode_hook, wparam, lparam);
            }

            if (parsed.value == keycode_silent) {
                return primitive.next(keycode_hook, wparam, lparam);
            }

            const instance: ?*Self = @ptrCast(@alignCast(instance_global.load(.acquire)));

            if (instance == null) {
                return primitive.next(keycode_hook, wparam, lparam);
            }

            const self = instance.?;

            self.keyboard.sync();

            if (parsed.down) {
                self.keyboard.keydown(parsed.value);
            } else {
                self.keyboard.keyup(parsed.value);
            }

            const key = parsed.with_modifiers(self.keyboard.get_modifiers());

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

            return primitive.next(keycode_hook, wparam, lparam);
        }
    };
}

fn wrapper_proc(
    keycode_hook: c_int,
    wparam: w32.WPARAM,
    lparam: w32.LPARAM,
) callconv(.c) w32.LRESULT {
    if (proc_global.load(.acquire)) |proc| {
        return proc(keycode_hook, wparam, lparam);
    }

    return primitive.next(keycode_hook, wparam, lparam);
}
