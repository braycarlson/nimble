const std = @import("std");

const input = @import("input");
const keycode = input.keycode;
const modifier = input.modifier;
const state = input.state;
const registry = input.registry;
const response_mod = input.response;

const Keyboard = state.Keyboard;
const Response = response_mod.Response;

pub const flag_count: u32 = 2;
pub const bits_per_flag: u8 = 128;
pub const key_count_max: u32 = 256;
pub const active_count_max: u8 = 32;

pub const max_events: u32 = 32768;
pub const max_snapshots: u32 = 256;
pub const iteration_max: u32 = 65536;

pub const EventKind = enum(u8) {
    key_down = 0,
    key_up = 1,
    binding_triggered = 2,
    binding_blocked = 3,
    binding_replaced = 4,
    reg_keyistered = 5,
    binding_unregistered = 6,
    state_divergence = 7,
    tick = 8,
    snapshot = 9,
    fault_injected = 10,
    invariant_violated = 11,

    pub fn is_valid(self: EventKind) bool {
        const value = @intFromEnum(self);
        const result = value <= @intFromEnum(EventKind.invariant_violated);

        return result;
    }
};

pub const Event = struct {
    tick: u64,
    kind: EventKind,
    keycode: u8 = 0,
    binding_id: u32 = 0,
    response: ?Response = null,

    pub fn is_valid(self: *const Event) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_kind = self.kind.is_valid();
        const result = valid_kind;

        return result;
    }
};

pub const Stats = struct {
    total_ticks: u64 = 0,
    total_operations: u64 = 0,
    key_events: u64 = 0,
    bindings_registered: u32 = 0,
    bindings_unregistered: u32 = 0,
    passes: u64 = 0,
    consumes: u64 = 0,
    replaces: u64 = 0,
    faults_injected: u32 = 0,
    invariant_violations: u32 = 0,

    pub fn is_valid(self: *const Stats) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_operations = self.total_operations <= self.total_ticks * 10;
        const result = valid_operations;

        return result;
    }

    pub fn blocks(self: *const Stats) u64 {
        std.debug.assert(self.is_valid());

        const result = self.consumes + self.replaces;

        std.debug.assert(result >= self.consumes);
        std.debug.assert(result >= self.replaces);

        return result;
    }

    pub fn allows(self: *const Stats) u64 {
        std.debug.assert(self.is_valid());

        const result = self.passes;

        return result;
    }

    pub fn active_bindings(self: *const Stats) u32 {
        std.debug.assert(self.is_valid());

        if (self.bindings_unregistered > self.bindings_registered) {
            return 0;
        }

        const result = self.bindings_registered - self.bindings_unregistered;

        std.debug.assert(result <= self.bindings_registered);

        return result;
    }
};

pub const KeyboardSnapshot = struct {
    flags: [flag_count]u128 = .{ 0, 0 },
    active_count: u8 = 0,

    pub fn is_valid(self: *const KeyboardSnapshot) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_count = self.active_count <= active_count_max;
        const result = valid_count;

        return result;
    }

    pub fn eql(self: *const KeyboardSnapshot, other: *const KeyboardSnapshot) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(other.is_valid());

        if (self.active_count != other.active_count) {
            return false;
        }

        if (self.flags[0] != other.flags[0]) {
            return false;
        }

        if (self.flags[1] != other.flags[1]) {
            return false;
        }

        return true;
    }
};

pub const RegistrySnapshot = struct {
    count: u32 = 0,
    paused: bool = false,

    pub fn is_valid(self: *const RegistrySnapshot) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_count = self.count <= 1024;
        const result = valid_count;

        return result;
    }
};

pub const Snapshot = struct {
    tick: u64,
    keyboard: KeyboardSnapshot,
    registry: RegistrySnapshot,

    pub fn is_valid(self: *const Snapshot) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_keyboard = self.keyboard.is_valid();
        const valid_registry = self.registry.is_valid();
        const result = valid_keyboard and valid_registry;

        return result;
    }

    pub fn capture(
        keyboard: *const Keyboard,
        reg_key: *const registry.key.KeyRegistry(1024),
        tick: u64,
    ) Snapshot {
        std.debug.assert(keyboard.is_valid());
        std.debug.assert(@intFromPtr(reg_key) != 0);

        const result = Snapshot{
            .tick = tick,
            .keyboard = .{
                .flags = keyboard.flags,
                .active_count = keyboard.active_count,
            },
            .registry = .{
                .count = reg_key.count,
                .paused = reg_key.is_paused(),
            },
        };

        std.debug.assert(result.is_valid());

        return result;
    }
};

pub const InvariantKind = enum {
    keyboard_count_mismatch,
    keyboard_state_mismatch,
    registry_count_mismatch,
    binding_not_found,
    unexpected_response,
};

pub const StateChecker = struct {
    keyboard: *Keyboard,
    registry_key: *registry.key.KeyRegistry(1024),
    shadow_keyboard: Keyboard,
    current_tick: u64,
    events: [max_events]Event,
    events_len: u32,
    snapshots: [max_snapshots]Snapshot,
    snapshots_len: u32,

    pub fn init(
        keyboard: *Keyboard,
        reg_key: *registry.key.KeyRegistry(1024),
    ) StateChecker {
        std.debug.assert(@intFromPtr(keyboard) != 0);
        std.debug.assert(@intFromPtr(reg_key) != 0);

        const result = StateChecker{
            .keyboard = keyboard,
            .registry_key = reg_key,
            .shadow_keyboard = Keyboard.init(),
            .current_tick = 0,
            .events = undefined,
            .events_len = 0,
            .snapshots = undefined,
            .snapshots_len = 0,
        };

        std.debug.assert(result.events_len == 0);
        std.debug.assert(result.snapshots_len == 0);

        return result;
    }

    pub fn is_valid(self: *const StateChecker) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_keyboard = @intFromPtr(self.keyboard) != 0;
        const valid_registry = @intFromPtr(self.registry_key) != 0;
        const valid_events = self.events_len <= max_events;
        const valid_snapshots = self.snapshots_len <= max_snapshots;
        const result = valid_keyboard and valid_registry and valid_events and valid_snapshots;

        return result;
    }

    pub fn reset(self: *StateChecker) void {
        std.debug.assert(self.is_valid());

        self.shadow_keyboard.clear();
        self.current_tick = 0;
        self.events_len = 0;
        self.snapshots_len = 0;

        std.debug.assert(self.current_tick == 0);
        std.debug.assert(self.events_len == 0);
    }

    pub fn set_tick(self: *StateChecker, tick: u64) void {
        std.debug.assert(self.is_valid());

        self.current_tick = tick;

        std.debug.assert(self.current_tick == tick);
    }

    pub fn on_key_down(self: *StateChecker, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        self.shadow_keyboard.keydown(key);

        self.record_event(.{
            .tick = self.current_tick,
            .kind = .key_down,
            .keycode = key,
        });
    }

    pub fn on_key_up(self: *StateChecker, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        self.shadow_keyboard.keyup(key);

        self.record_event(.{
            .tick = self.current_tick,
            .kind = .key_up,
            .keycode = key,
        });
    }

    pub fn on_binding_triggered(self: *StateChecker, key: u8, binding_id: u32, resp: Response) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        const kind = response_to_event_kind(resp);

        self.record_event(.{
            .tick = self.current_tick,
            .kind = kind,
            .keycode = key,
            .binding_id = binding_id,
            .response = resp,
        });
    }

    fn response_to_event_kind(resp: Response) EventKind {
        return switch (resp) {
            .pass => .binding_triggered,
            .consume => .binding_blocked,
            .replace => .binding_replaced,
        };
    }

    pub fn on_binding_registered(self: *StateChecker, key: u8, binding_id: u32, mods: modifier.Set) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));
        _ = mods;

        self.record_event(.{
            .tick = self.current_tick,
            .kind = .reg_keyistered,
            .keycode = key,
            .binding_id = binding_id,
        });
    }

    pub fn on_binding_unregistered(self: *StateChecker, binding_id: u32) void {
        std.debug.assert(self.is_valid());

        self.record_event(.{
            .tick = self.current_tick,
            .kind = .binding_unregistered,
            .binding_id = binding_id,
        });
    }

    pub fn on_fault_injected(self: *StateChecker, fault_kind: u8) void {
        std.debug.assert(self.is_valid());

        self.record_event(.{
            .tick = self.current_tick,
            .kind = .fault_injected,
            .keycode = fault_kind,
        });
    }

    pub fn take_snapshot(self: *StateChecker) void {
        std.debug.assert(self.is_valid());

        if (self.snapshots_len >= max_snapshots) {
            return;
        }

        std.debug.assert(self.snapshots_len < max_snapshots);

        self.snapshots[self.snapshots_len] = build_snapshot(self);
        self.snapshots_len += 1;

        self.record_event(.{
            .tick = self.current_tick,
            .kind = .snapshot,
        });

        std.debug.assert(self.snapshots_len <= max_snapshots);
    }

    fn build_snapshot(self: *const StateChecker) Snapshot {
        std.debug.assert(self.is_valid());

        const result = Snapshot{
            .tick = self.current_tick,
            .keyboard = .{
                .flags = self.shadow_keyboard.flags,
                .active_count = self.shadow_keyboard.active_count,
            },
            .registry = .{
                .count = self.registry_key.base.slot.count,
                .paused = self.registry_key.is_paused(),
            },
        };

        return result;
    }

    pub fn check_invariants(self: *StateChecker) bool {
        std.debug.assert(self.is_valid());

        const keyboard_count = self.keyboard.count();
        const shadow_count = self.shadow_keyboard.count();

        if (keyboard_count != shadow_count) {
            self.record_invariant_violation();
            return false;
        }

        std.debug.assert(keyboard_count == shadow_count);

        return true;
    }

    fn record_invariant_violation(self: *StateChecker) void {
        std.debug.assert(self.is_valid());

        self.record_event(.{
            .tick = self.current_tick,
            .kind = .invariant_violated,
        });
    }

    fn record_event(self: *StateChecker, evt: Event) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(evt.is_valid());

        if (self.events_len >= max_events) {
            return;
        }

        std.debug.assert(self.events_len < max_events);

        self.events[self.events_len] = evt;
        self.events_len += 1;

        std.debug.assert(self.events_len <= max_events);
    }
};
