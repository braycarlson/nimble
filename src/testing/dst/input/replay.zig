const std = @import("std");

const input = @import("input");
const keycode = input.keycode;
const modifier = input.modifier;
const registry = input.registry;
const state = input.state;
const response_mod = input.response;
const event = input.event;

const Response = response_mod.Response;
const Keyboard = state.Keyboard;
const KeyRegistry = registry.key.KeyRegistry;
const Key = event.key.Key;

const state_mod = @import("state.zig");
const simulator = @import("simulator.zig");
const recorder_mod = @import("recorder.zig");

const Event = state_mod.Event;
const EventKind = state_mod.EventKind;
const Snapshot = state_mod.Snapshot;
const StateChecker = state_mod.StateChecker;

const VOPR = simulator.VOPR;
const ReplayEntry = simulator.ReplayEntry;
const Operation = simulator.Operation;
const OperationKind = simulator.OperationKind;
const FaultKind = simulator.FaultKind;

const Recording = recorder_mod.Recording;

pub const iteration_max: u32 = 0xFFFFFFFF;

pub const ReplayState = enum {
    idle,
    running,
    paused,
    finished,
    error_state,

    pub fn is_valid(self: ReplayState) bool {
        const value = @intFromEnum(self);
        const result = value <= @intFromEnum(ReplayState.error_state);

        return result;
    }
};

pub const ReplayCallback = *const fn (replayer: *Replayer, current_tick: u64, event: ?*const Event) void;

fn replay_callback(_: *anyopaque, _: *const Key) Response {
    return .pass;
}

pub const Replayer = struct {
    keyboard: Keyboard,
    registry_key: KeyRegistry(1024),
    state_checker: StateChecker,
    prng: std.Random.DefaultPrng,
    recording: ?*const Recording,
    current_tick: u64,
    replay_index: u32,
    state: ReplayState,
    target_tick: u64,
    callback: ?ReplayCallback,
    callback_context: ?*anyopaque,
    divergence_tick: ?u64,

    pub fn init() Replayer {
        var result = Replayer{
            .keyboard = Keyboard.init(),
            .registry_key = KeyRegistry(1024).init(),
            .state_checker = undefined,
            .prng = std.Random.DefaultPrng.init(0),
            .recording = null,
            .current_tick = 0,
            .replay_index = 0,
            .state = .idle,
            .target_tick = 0,
            .callback = null,
            .callback_context = null,
            .divergence_tick = null,
        };

        result.state_checker = StateChecker.init(&result.keyboard, &result.registry_key);

        std.debug.assert(result.is_valid());
        std.debug.assert(result.current_tick == 0);
        std.debug.assert(result.state == .idle);

        return result;
    }

    pub fn is_valid(self: *const Replayer) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_keyboard = self.keyboard.is_valid();
        const valid_state = self.state.is_valid();
        const result = valid_keyboard and valid_state;

        return result;
    }

    pub fn deinit(self: *Replayer) void {
        std.debug.assert(self.is_valid());

        self.registry_key.clear();
    }

    pub fn load_recording(self: *Replayer, recording: *const Recording) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(recording.is_valid());

        self.recording = recording;
        self.reset();

        if (recording.replay.len > 0) {
            self.prng = std.Random.DefaultPrng.init(recording.header.seed);
        }

        std.debug.assert(self.recording != null);
    }

    pub fn set_callback(self: *Replayer, callback: ReplayCallback, context: ?*anyopaque) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(callback) != 0);

        self.callback = callback;
        self.callback_context = context;

        std.debug.assert(self.callback != null);
    }

    pub fn reset(self: *Replayer) void {
        std.debug.assert(self.is_valid());

        self.keyboard.clear();
        self.registry_key.clear();
        self.state_checker.reset();
        self.current_tick = 0;
        self.replay_index = 0;
        self.state = .idle;
        self.divergence_tick = null;

        std.debug.assert(self.current_tick == 0);
        std.debug.assert(self.replay_index == 0);
        std.debug.assert(self.state == .idle);
    }

    pub fn step(self: *Replayer) bool {
        std.debug.assert(self.is_valid());

        const recording = self.recording orelse return false;

        std.debug.assert(recording.is_valid());

        const replay_len: u32 = @intCast(recording.replay.len);

        if (self.replay_index >= replay_len) {
            self.state = .finished;
            return false;
        }

        std.debug.assert(self.replay_index < replay_len);

        const entry = &recording.replay[self.replay_index];

        std.debug.assert(entry.is_valid());

        if (entry.tick > self.current_tick) {
            self.current_tick = entry.tick;
        }

        self.state_checker.set_tick(self.current_tick);
        self.execute_entry(entry);
        self.invoke_callback(recording);

        self.replay_index += 1;
        self.current_tick += 1;

        return true;
    }

    fn invoke_callback(self: *Replayer, recording: *const Recording) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(recording.is_valid());

        if (self.callback) |cb| {
            const evt = recording.get_event_at_tick(self.current_tick);
            cb(self, self.current_tick, evt);
        }
    }

    pub fn step_to(self: *Replayer, target: u64) void {
        std.debug.assert(self.is_valid());

        var iterations: u32 = 0;

        while (self.current_tick < target and iterations < iteration_max) : (iterations += 1) {
            std.debug.assert(self.current_tick < target);

            if (!self.step()) {
                break;
            }
        }

        std.debug.assert(iterations <= iteration_max);
    }

    pub fn run_to_completion(self: *Replayer) void {
        std.debug.assert(self.is_valid());

        self.state = .running;

        var iterations: u32 = 0;

        while (self.state == .running and iterations < iteration_max) : (iterations += 1) {
            std.debug.assert(self.state == .running);

            if (!self.step()) {
                self.state = .finished;
                break;
            }
        }

        std.debug.assert(iterations <= iteration_max);
        std.debug.assert(self.state == .finished or iterations == iteration_max);
    }

    pub fn verify_snapshot(self: *Replayer, snapshot: *const Snapshot) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(snapshot.is_valid());

        const current = Snapshot.capture(&self.keyboard, &self.registry_key, self.current_tick);

        std.debug.assert(current.is_valid());

        if (!current.keyboard.eql(&snapshot.keyboard)) {
            self.divergence_tick = self.current_tick;
            return false;
        }

        return true;
    }

    fn execute_entry(self: *Replayer, entry: *const ReplayEntry) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(entry.is_valid());

        const op = entry.operation;

        std.debug.assert(op.is_valid());

        switch (op.kind) {
            .key_down => self.execute_key_down(op.keycode),
            .key_up => self.execute_key_up(op.keycode),
            .modifier_down => self.execute_modifier_down(op.keycode),
            .modifier_up => self.execute_modifier_up(op.keycode),
            .register_binding => self.execute_register_binding(op),
            .unregister_binding => self.execute_unregister_binding(op.binding_id),
            .clear_keyboard => self.execute_clear_keyboard(),
            .pause_registry => self.registry_key.set_paused(true),
            .resume_registry => self.registry_key.set_paused(false),
            .random_sequence => {},
        }
    }

    fn execute_key_down(self: *Replayer, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        self.state_checker.on_key_down(key);
        self.keyboard.keydown(key);

        self.process_key_event(key);
    }

    fn process_key_event(self: *Replayer, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        const key_event = Key{
            .value = key,
            .scan = 0,
            .down = true,
            .injected = false,
            .extended = false,
            .extra = 0,
            .modifiers = self.keyboard.get_modifiers(),
        };

        if (self.registry_key.process(&key_event)) |resp| {
            self.state_checker.on_binding_triggered(key, 0, resp);
        }
    }

    fn execute_key_up(self: *Replayer, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        self.state_checker.on_key_up(key);
        self.keyboard.keyup(key);
    }

    fn execute_modifier_down(self: *Replayer, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        self.state_checker.on_key_down(key);
        self.keyboard.keydown(key);
    }

    fn execute_modifier_up(self: *Replayer, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        self.state_checker.on_key_up(key);
        self.keyboard.keyup(key);
    }

    fn execute_register_binding(self: *Replayer, op: Operation) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(op.is_valid());

        const mods = modifier.Set{ .flags = @truncate(op.modifiers) };

        if (self.registry_key.register(
            op.keycode,
            mods,
            &replay_callback,
            null,
            .{},
        )) |id| {
            self.state_checker.on_binding_registered(op.keycode, id, mods);
        } else |_| {}
    }

    fn execute_unregister_binding(self: *Replayer, binding_id: u32) void {
        std.debug.assert(self.is_valid());

        if (binding_id == 0) {
            return;
        }

        self.registry_key.unregister(binding_id) catch {};
        self.state_checker.on_binding_unregistered(binding_id);
    }

    fn execute_clear_keyboard(self: *Replayer) void {
        std.debug.assert(self.is_valid());

        self.keyboard.clear();
        self.state_checker.shadow_keyboard.clear();

        std.debug.assert(self.keyboard.count() == 0);
    }
};

const testing = std.testing;

test "Replayer init" {
    var replayer = Replayer.init();
    defer replayer.deinit();

    std.debug.assert(replayer.is_valid());
    std.debug.assert(replayer.state == .idle);
    std.debug.assert(replayer.current_tick == 0);

    try testing.expectEqual(ReplayState.idle, replayer.state);
    try testing.expectEqual(@as(u64, 0), replayer.current_tick);
}

test "Replayer reset" {
    var replayer = Replayer.init();
    defer replayer.deinit();

    std.debug.assert(replayer.is_valid());

    replayer.keyboard.keydown('A');
    replayer.current_tick = 100;
    replayer.state = .running;

    std.debug.assert(replayer.current_tick == 100);
    std.debug.assert(replayer.keyboard.count() > 0);

    replayer.reset();

    std.debug.assert(replayer.current_tick == 0);
    std.debug.assert(replayer.keyboard.count() == 0);
    std.debug.assert(replayer.state == .idle);

    try testing.expectEqual(@as(u64, 0), replayer.current_tick);
    try testing.expectEqual(@as(u32, 0), replayer.keyboard.count());
    try testing.expectEqual(ReplayState.idle, replayer.state);
}

test "Replayer state transitions" {
    var replayer = Replayer.init();
    defer replayer.deinit();

    std.debug.assert(replayer.state == .idle);
    std.debug.assert(replayer.state.is_valid());

    replayer.state = .running;

    std.debug.assert(replayer.state == .running);
    std.debug.assert(replayer.state.is_valid());

    replayer.state = .finished;

    std.debug.assert(replayer.state == .finished);
    std.debug.assert(replayer.state.is_valid());

    try testing.expectEqual(ReplayState.finished, replayer.state);
}
