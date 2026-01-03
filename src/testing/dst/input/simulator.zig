const std = @import("std");

const state_mod = @import("state.zig");

const fuzz = @import("fuzz");
const input_fuzz = fuzz.input;

const input = @import("input");
const keycode = input.keycode;
const modifier = input.modifier;
const binding_mod = input.binding_mod;
const state = input.state;
const response_mod = input.response;
const registry = input.registry;
const event = input.event;

const Binding = binding_mod.Binding;
const Keyboard = state.Keyboard;
const Response = response_mod.Response;
const KeyRegistry = registry.key.KeyRegistry;
const Key = event.key.Key;

const StateChecker = state_mod.StateChecker;
const Event = state_mod.Event;
const Snapshot = state_mod.Snapshot;
const Stats = state_mod.Stats;

pub const iteration_max: u32 = 0xFFFFFFFF;
pub const max_held_keys: u32 = 16;
pub const max_held_modifiers: u32 = 4;
pub const max_tracked_bindings: u32 = 256;
pub const max_pending: u32 = 16;

pub const FaultKind = enum(u8) {
    none = 0,
    drop_input = 1,
    duplicate_input = 2,
    reorder_input = 3,
    corrupt_state = 4,
    delay_processing = 5,

    pub fn is_valid(self: FaultKind) bool {
        const value = @intFromEnum(self);
        const result = value <= @intFromEnum(FaultKind.delay_processing);

        return result;
    }
};

pub const OperationKind = enum(u8) {
    key_down = 0,
    key_up = 1,
    modifier_down = 2,
    modifier_up = 3,
    register_binding = 4,
    unregister_binding = 5,
    random_sequence = 6,
    clear_keyboard = 7,
    pause_registry = 8,
    resume_registry = 9,

    pub fn is_valid(self: OperationKind) bool {
        const value = @intFromEnum(self);
        const result = value <= @intFromEnum(OperationKind.resume_registry);

        return result;
    }
};

pub const Operation = struct {
    kind: OperationKind,
    keycode: u8,
    modifiers: u16,
    binding_id: u32,
    sequence_len: u8,

    pub fn is_valid(self: *const Operation) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_kind = self.kind.is_valid();
        const valid_seq = self.sequence_len <= 8;
        const result = valid_kind and valid_seq;

        return result;
    }
};

pub const ReplayEntry = struct {
    tick: u64,
    operation: Operation,
    fault: FaultKind,
    prng_state: u64,

    pub fn is_valid(self: *const ReplayEntry) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_op = self.operation.is_valid();
        const valid_fault = self.fault.is_valid();
        const result = valid_op and valid_fault;

        return result;
    }
};

pub const TestProfile = enum {
    realistic,
    stress,
    mixed,
    exhaustive,
};

pub const RealisticConfig = struct {
    max_simultaneous_keys: u8 = 4,
    max_simultaneous_modifiers: u8 = 2,
    prevent_duplicate_modifiers: bool = true,
    prefer_lifo_release: bool = true,
    key_hold_bias: u8 = 70,
    modifier_first_probability: u8 = 80,

    pub fn is_valid(self: *const RealisticConfig) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_keys = self.max_simultaneous_keys <= max_held_keys;
        const valid_mods = self.max_simultaneous_modifiers <= max_held_modifiers;
        const result = valid_keys and valid_mods;

        return result;
    }
};

pub const OperationWeights = struct {
    key_down: u8 = 25,
    key_up: u8 = 25,
    modifier_down: u8 = 10,
    modifier_up: u8 = 10,
    register_binding: u8 = 10,
    unregister_binding: u8 = 5,
    random_sequence: u8 = 5,
    clear_keyboard: u8 = 5,
    pause_registry: u8 = 2,
    resume_registry: u8 = 3,

    pub fn total(self: *const OperationWeights) u16 {
        std.debug.assert(@intFromPtr(self) != 0);

        const result = @as(u16, self.key_down) + self.key_up + self.modifier_down +
            self.modifier_up + self.register_binding + self.unregister_binding +
            self.random_sequence + self.clear_keyboard + self.pause_registry +
            self.resume_registry;

        std.debug.assert(result > 0);

        return result;
    }
};

pub const FaultWeights = struct {
    none: u8 = 80,
    drop_input: u8 = 5,
    duplicate_input: u8 = 5,
    reorder_input: u8 = 0,
    corrupt_state: u8 = 0,
    delay_processing: u8 = 10,

    pub fn total(self: *const FaultWeights) u16 {
        std.debug.assert(@intFromPtr(self) != 0);

        const result = @as(u16, self.none) + self.drop_input + self.duplicate_input +
            self.reorder_input + self.corrupt_state + self.delay_processing;

        std.debug.assert(result > 0);

        return result;
    }
};

pub const VOPRConfig = struct {
    seed: u64,
    max_ticks: u64 = 100000,
    max_bindings: u32 = 64,
    snapshot_interval: u64 = 500,
    fault_probability: u8 = 5,
    test_profile: TestProfile = .realistic,
    realistic: RealisticConfig = .{},
    operation_weights: OperationWeights = .{},
    fault_weights: FaultWeights = .{},

    pub fn is_valid(self: *const VOPRConfig) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_ticks = self.max_ticks > 0 and self.max_ticks <= iteration_max;
        const valid_bindings = self.max_bindings <= max_tracked_bindings;
        const valid_interval = self.snapshot_interval > 0;
        const valid_realistic = self.realistic.is_valid();
        const result = valid_ticks and valid_bindings and valid_interval and valid_realistic;

        return result;
    }
};

pub const VOPRStats = Stats;

pub const VOPRResult = enum {
    success,
    invariant_failure,
    timeout,
    fault_detected,
};

pub const PendingInput = struct {
    keycode: u8,
    down: bool,
    delay: u64,

    pub fn is_valid(self: *const PendingInput) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_keycode = keycode.is_valid(self.keycode);
        const result = valid_keycode;

        return result;
    }
};

pub const CallbackContext = struct {
    vopr: *VOPR,
    triggered_count: u32 = 0,
    last_response: Response = .pass,
};

pub const Workload = struct {
    operations: []const Operation,
    expected_final_state: ?Snapshot,
};

pub const FaultInjector = struct {
    enabled: bool = true,
    probability: u8 = 5,
    weights: FaultWeights = .{},

    pub fn is_valid(self: *const FaultInjector) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_probability = self.probability <= 100;
        const result = valid_probability;

        return result;
    }

    pub fn should_inject(self: *const FaultInjector, random: *std.Random) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(random) != 0);

        if (!self.enabled) {
            return false;
        }

        const roll = random.intRangeLessThan(u8, 0, 100);
        const result = roll < self.probability;

        return result;
    }

    pub fn select_fault(self: *const FaultInjector, random: *std.Random) FaultKind {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(random) != 0);

        const total = self.weights.total();

        std.debug.assert(total > 0);

        var choice = random.intRangeLessThan(u16, 0, total);

        if (choice < self.weights.none) return .none;
        choice -= self.weights.none;

        if (choice < self.weights.drop_input) return .drop_input;
        choice -= self.weights.drop_input;

        if (choice < self.weights.duplicate_input) return .duplicate_input;
        choice -= self.weights.duplicate_input;

        if (choice < self.weights.reorder_input) return .reorder_input;
        choice -= self.weights.reorder_input;

        if (choice < self.weights.corrupt_state) return .corrupt_state;

        return .delay_processing;
    }
};

pub const VOPR = struct {
    config: VOPRConfig,
    prng: std.Random.DefaultPrng,
    keyboard: Keyboard,
    registry_key: KeyRegistry(1024),
    state_checker: StateChecker,
    current_tick: u64,
    stats: Stats,
    held_keys: [max_held_keys]u8,
    held_keys_count: u32,
    held_modifiers: [max_held_modifiers]u8,
    held_modifiers_count: u32,
    registered_ids: [max_tracked_bindings]u32,
    registered_count: u32,
    pending_inputs: [max_pending]PendingInput,
    pending_count: u32,
    fault_injector: FaultInjector,
    callback_context: CallbackContext,

    pub fn init(config: VOPRConfig) VOPR {
        std.debug.assert(config.is_valid());

        const result = VOPR{
            .config = config,
            .prng = std.Random.DefaultPrng.init(config.seed),
            .keyboard = Keyboard.init(),
            .registry_key = KeyRegistry(1024).init(),
            .state_checker = undefined,
            .current_tick = 0,
            .stats = .{},
            .held_keys = undefined,
            .held_keys_count = 0,
            .held_modifiers = undefined,
            .held_modifiers_count = 0,
            .registered_ids = undefined,
            .registered_count = 0,
            .pending_inputs = undefined,
            .pending_count = 0,
            .fault_injector = .{
                .enabled = config.fault_probability > 0,
                .probability = config.fault_probability,
                .weights = config.fault_weights,
            },
            .callback_context = undefined,
        };

        std.debug.assert(result.current_tick == 0);
        std.debug.assert(result.held_keys_count == 0);

        return result;
    }

    pub fn is_valid(self: *const VOPR) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_config = self.config.is_valid();
        const valid_keyboard = self.keyboard.is_valid();
        const valid_held = self.held_keys_count <= max_held_keys;
        const valid_mods = self.held_modifiers_count <= max_held_modifiers;
        const valid_registered = self.registered_count <= max_tracked_bindings;
        const valid_pending = self.pending_count <= max_pending;
        const result = valid_config and valid_keyboard and valid_held and
            valid_mods and valid_registered and valid_pending;

        return result;
    }

    pub fn init_references(self: *VOPR) void {
        std.debug.assert(self.config.is_valid());

        self.state_checker = StateChecker.init(&self.keyboard, &self.registry_key);
        self.callback_context = .{ .vopr = self };

        std.debug.assert(self.state_checker.is_valid());
    }

    pub fn deinit(self: *VOPR) void {
        std.debug.assert(self.is_valid());

        self.registry_key.clear();
    }

    pub fn reset(self: *VOPR, seed: u64) void {
        std.debug.assert(self.is_valid());

        self.prng = std.Random.DefaultPrng.init(seed);
        self.keyboard.clear();
        self.registry_key.clear();
        self.state_checker.reset();
        self.current_tick = 0;
        self.stats = .{};
        self.held_keys_count = 0;
        self.held_modifiers_count = 0;
        self.registered_count = 0;
        self.pending_count = 0;
        self.callback_context = .{ .vopr = self };

        std.debug.assert(self.current_tick == 0);
        std.debug.assert(self.held_keys_count == 0);
    }

    pub fn run(self: *VOPR) VOPRResult {
        std.debug.assert(self.config.is_valid());

        self.init_references();

        var tick: u64 = 0;

        while (tick < self.config.max_ticks and tick < iteration_max) : (tick += 1) {
            std.debug.assert(tick < self.config.max_ticks);

            const result = self.execute_tick();

            if (result != .success) {
                return result;
            }

            self.current_tick += 1;
            self.stats.total_ticks = self.current_tick;
        }

        std.debug.assert(tick == self.config.max_ticks or tick == iteration_max);

        return .success;
    }

    fn execute_tick(self: *VOPR) VOPRResult {
        std.debug.assert(self.is_valid());

        self.state_checker.set_tick(self.current_tick);
        self.process_pending_inputs();

        const operation = self.generate_operation();
        const fault = self.maybe_inject_fault();

        std.debug.assert(operation.is_valid());
        std.debug.assert(fault.is_valid());

        if (fault != .none) {
            self.stats.faults_injected += 1;
            self.state_checker.on_fault_injected(@intFromEnum(fault));
        }

        if (fault != .drop_input) {
            self.execute_operation(operation, fault);
            self.stats.total_operations += 1;
        }

        if (self.current_tick % self.config.snapshot_interval == 0) {
            return self.check_and_snapshot();
        }

        return .success;
    }

    fn check_and_snapshot(self: *VOPR) VOPRResult {
        std.debug.assert(self.is_valid());

        self.state_checker.take_snapshot();

        if (!self.state_checker.check_invariants()) {
            self.stats.invariant_violations += 1;
            return .invariant_failure;
        }

        return .success;
    }

    fn process_pending_inputs(self: *VOPR) void {
        std.debug.assert(self.is_valid());

        var i: u32 = 0;
        var iterations: u32 = 0;

        while (i < self.pending_count and iterations < max_pending) : (iterations += 1) {
            std.debug.assert(i < self.pending_count);

            if (self.pending_inputs[i].delay == 0) {
                self.process_single_pending(i);
            } else {
                self.pending_inputs[i].delay -= 1;
                i += 1;
            }
        }

        std.debug.assert(iterations <= max_pending);
    }

    fn process_single_pending(self: *VOPR, index: u32) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(index < self.pending_count);

        const pending = self.pending_inputs[index];

        std.debug.assert(pending.is_valid());

        if (pending.down) {
            self.state_checker.on_key_down(pending.keycode);
            self.keyboard.keydown(pending.keycode);
        } else {
            self.state_checker.on_key_up(pending.keycode);
            self.keyboard.keyup(pending.keycode);
        }

        self.stats.key_events += 1;
        self.pending_inputs[index] = self.pending_inputs[self.pending_count - 1];
        self.pending_count -= 1;
    }

    fn generate_operation(self: *VOPR) Operation {
        std.debug.assert(self.is_valid());

        var random = self.prng.random();
        const kind = self.select_operation_kind(&random);

        const result = self.build_operation_for_kind(kind, &random);

        std.debug.assert(result.is_valid());

        return result;
    }

    fn build_operation_for_kind(self: *VOPR, kind: OperationKind, random: *std.Random) Operation {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(random) != 0);

        return switch (kind) {
            .key_down => self.build_key_down_op(random),
            .key_up => self.build_key_up_op(random),
            .modifier_down => self.build_modifier_down_op(random),
            .modifier_up => self.build_modifier_up_op(random),
            .register_binding => self.build_register_op(random),
            .unregister_binding => self.build_unregister_op(random),
            .random_sequence => self.build_sequence_op(random),
            .clear_keyboard => Operation{ .kind = .clear_keyboard, .keycode = 0, .modifiers = 0, .binding_id = 0, .sequence_len = 0 },
            .pause_registry => Operation{ .kind = .pause_registry, .keycode = 0, .modifiers = 0, .binding_id = 0, .sequence_len = 0 },
            .resume_registry => Operation{ .kind = .resume_registry, .keycode = 0, .modifiers = 0, .binding_id = 0, .sequence_len = 0 },
        };
    }

    fn build_key_down_op(self: *VOPR, random: *std.Random) Operation {
        _ = self;

        return Operation{
            .kind = .key_down,
            .keycode = input_fuzz.random_non_modifier_key_keycode(random),
            .modifiers = 0,
            .binding_id = 0,
            .sequence_len = 0,
        };
    }

    fn build_key_up_op(self: *VOPR, random: *std.Random) Operation {
        const key = if (self.held_keys_count > 0)
            self.held_keys[random.intRangeLessThan(u32, 0, self.held_keys_count)]
        else
            input_fuzz.random_non_modifier_key_keycode(random);

        return Operation{
            .kind = .key_up,
            .keycode = key,
            .modifiers = 0,
            .binding_id = 0,
            .sequence_len = 0,
        };
    }

    fn build_modifier_down_op(self: *VOPR, random: *std.Random) Operation {
        _ = self;

        return Operation{
            .kind = .modifier_down,
            .keycode = input_fuzz.random_modifier_keycode(random),
            .modifiers = 0,
            .binding_id = 0,
            .sequence_len = 0,
        };
    }

    fn build_modifier_up_op(self: *VOPR, random: *std.Random) Operation {
        const key = if (self.held_modifiers_count > 0)
            self.held_modifiers[random.intRangeLessThan(u32, 0, self.held_modifiers_count)]
        else
            input_fuzz.random_modifier_keycode(random);

        return Operation{
            .kind = .modifier_up,
            .keycode = key,
            .modifiers = 0,
            .binding_id = 0,
            .sequence_len = 0,
        };
    }

    fn build_register_op(self: *VOPR, random: *std.Random) Operation {
        _ = self;

        return Operation{
            .kind = .register_binding,
            .keycode = input_fuzz.random_non_modifier_key_keycode(random),
            .modifiers = random.int(u16) & 0x0F,
            .binding_id = 0,
            .sequence_len = 0,
        };
    }

    fn build_unregister_op(self: *VOPR, random: *std.Random) Operation {
        const id = if (self.registered_count > 0)
            self.registered_ids[random.intRangeLessThan(u32, 0, self.registered_count)]
        else
            0;

        return Operation{
            .kind = .unregister_binding,
            .keycode = 0,
            .modifiers = 0,
            .binding_id = id,
            .sequence_len = 0,
        };
    }

    fn build_sequence_op(self: *VOPR, random: *std.Random) Operation {
        _ = self;

        return Operation{
            .kind = .random_sequence,
            .keycode = 0,
            .modifiers = 0,
            .binding_id = 0,
            .sequence_len = random.intRangeAtMost(u8, 1, 8),
        };
    }

    fn select_operation_kind(self: *VOPR, random: *std.Random) OperationKind {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(random) != 0);

        const weights = self.config.operation_weights;
        const total = weights.total();

        std.debug.assert(total > 0);

        var choice = random.intRangeLessThan(u16, 0, total);

        if (choice < weights.key_down) return .key_down;
        choice -= weights.key_down;

        if (choice < weights.key_up) return .key_up;
        choice -= weights.key_up;

        if (choice < weights.modifier_down) return .modifier_down;
        choice -= weights.modifier_down;

        if (choice < weights.modifier_up) return .modifier_up;
        choice -= weights.modifier_up;

        if (choice < weights.register_binding) return .register_binding;
        choice -= weights.register_binding;

        if (choice < weights.unregister_binding) return .unregister_binding;
        choice -= weights.unregister_binding;

        if (choice < weights.random_sequence) return .random_sequence;
        choice -= weights.random_sequence;

        if (choice < weights.clear_keyboard) return .clear_keyboard;
        choice -= weights.clear_keyboard;

        if (choice < weights.pause_registry) return .pause_registry;

        return .resume_registry;
    }

    fn maybe_inject_fault(self: *VOPR) FaultKind {
        std.debug.assert(self.is_valid());

        var random = self.prng.random();

        if (self.fault_injector.should_inject(&random)) {
            const result = self.fault_injector.select_fault(&random);

            std.debug.assert(result.is_valid());

            return result;
        }

        return .none;
    }

    fn execute_operation(self: *VOPR, operation: Operation, fault: FaultKind) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(operation.is_valid());
        std.debug.assert(fault.is_valid());

        switch (operation.kind) {
            .key_down => self.execute_key_down(operation.keycode, fault),
            .key_up => self.execute_key_up(operation.keycode, fault),
            .modifier_down => self.execute_modifier_down(operation.keycode, fault),
            .modifier_up => self.execute_modifier_up(operation.keycode, fault),
            .register_binding => self.execute_register_binding(operation),
            .unregister_binding => self.execute_unregister_binding(operation.binding_id),
            .random_sequence => self.execute_random_sequence(operation.sequence_len),
            .clear_keyboard => self.execute_clear_keyboard(),
            .pause_registry => self.registry_key.set_paused(true),
            .resume_registry => self.registry_key.set_paused(false),
        }
    }

    fn execute_key_down(self: *VOPR, key: u8, fault: FaultKind) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        self.state_checker.on_key_down(key);
        self.keyboard.keydown(key);
        self.add_held_key(key);
        self.stats.key_events += 1;

        self.process_key_through_registry(key);
        self.apply_key_down_fault(key, fault);
    }

    fn process_key_through_registry(self: *VOPR, key: u8) void {
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
            self.record_response(resp);
        }
    }

    fn record_response(self: *VOPR, resp: Response) void {
        std.debug.assert(self.is_valid());

        switch (resp) {
            .pass => self.stats.passes += 1,
            .consume => self.stats.consumes += 1,
            .replace => self.stats.replaces += 1,
        }
    }

    fn apply_key_down_fault(self: *VOPR, key: u8, fault: FaultKind) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        if (fault == .duplicate_input) {
            self.state_checker.on_key_down(key);
            self.keyboard.keydown(key);
            self.stats.key_events += 1;
        }

        if (fault == .delay_processing and self.pending_count < max_pending) {
            self.queue_delayed_input(key, true);
        }
    }

    fn queue_delayed_input(self: *VOPR, key: u8, down: bool) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.pending_count < max_pending);

        self.pending_inputs[self.pending_count] = .{
            .keycode = key,
            .down = down,
            .delay = self.prng.random().intRangeAtMost(u64, 1, 10),
        };
        self.pending_count += 1;
    }

    fn execute_key_up(self: *VOPR, key: u8, fault: FaultKind) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        self.state_checker.on_key_up(key);
        self.keyboard.keyup(key);
        self.remove_held_key(key);
        self.stats.key_events += 1;

        if (fault == .duplicate_input) {
            self.state_checker.on_key_up(key);
            self.keyboard.keyup(key);
            self.stats.key_events += 1;
        }
    }

    fn execute_modifier_down(self: *VOPR, key: u8, fault: FaultKind) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        self.state_checker.on_key_down(key);
        self.keyboard.keydown(key);
        self.add_held_modifier(key);
        self.stats.key_events += 1;

        self.process_key_through_registry(key);

        if (fault == .duplicate_input) {
            self.state_checker.on_key_down(key);
            self.keyboard.keydown(key);
            self.stats.key_events += 1;
        }
    }

    fn execute_modifier_up(self: *VOPR, key: u8, fault: FaultKind) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        self.state_checker.on_key_up(key);
        self.keyboard.keyup(key);
        self.remove_held_modifier(key);
        self.stats.key_events += 1;

        if (fault == .duplicate_input) {
            self.state_checker.on_key_up(key);
            self.keyboard.keyup(key);
            self.stats.key_events += 1;
        }
    }

    fn execute_register_binding(self: *VOPR, operation: Operation) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(operation.is_valid());

        if (self.registered_count >= self.config.max_bindings) {
            return;
        }

        if (self.registered_count >= max_tracked_bindings) {
            return;
        }

        std.debug.assert(self.registered_count < max_tracked_bindings);

        const mods = modifier.Set{ .flags = @truncate(operation.modifiers) };

        const id = self.registry_key.register(
            operation.keycode,
            mods,
            &vopr_callback,
            @ptrCast(&self.callback_context),
            .{},
        ) catch {
            return;
        };

        self.registered_ids[self.registered_count] = id;
        self.registered_count += 1;
        self.stats.bindings_registered += 1;
        self.state_checker.on_binding_registered(operation.keycode, id, mods);

        std.debug.assert(self.registered_count <= max_tracked_bindings);
    }

    fn execute_unregister_binding(self: *VOPR, id: u32) void {
        std.debug.assert(self.is_valid());

        if (id == 0) {
            return;
        }

        self.registry_key.unregister(id) catch {
            return;
        };

        self.remove_registered_id(id);
        self.stats.bindings_unregistered += 1;
        self.state_checker.on_binding_unregistered(id);
    }

    fn remove_registered_id(self: *VOPR, id: u32) void {
        std.debug.assert(self.is_valid());

        var i: u32 = 0;

        while (i < self.registered_count and i < max_tracked_bindings) : (i += 1) {
            std.debug.assert(i < self.registered_count);

            if (self.registered_ids[i] == id) {
                self.registered_ids[i] = self.registered_ids[self.registered_count - 1];
                self.registered_count -= 1;
                break;
            }
        }

        std.debug.assert(i <= max_tracked_bindings);
    }

    fn execute_random_sequence(self: *VOPR, len: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(len <= 8);

        var random = self.prng.random();
        var seq = input_fuzz.KeySequence.init();

        self.build_key_sequence(&seq, &random, len);
        self.execute_sequence_down(&seq);
        self.execute_sequence_up(&seq);
    }

    fn build_key_sequence(self: *VOPR, seq: *input_fuzz.KeySequence, random: *std.Random, len: u8) void {
        _ = self;

        var i: u8 = 0;

        while (i < len and i < 8) : (i += 1) {
            std.debug.assert(i < len);

            const key = input_fuzz.random_non_modifier_key_keycode(random);
            seq.push(key);
        }

        std.debug.assert(i == len or i == 8);
    }

    fn execute_sequence_down(self: *VOPR, seq: *const input_fuzz.KeySequence) void {
        std.debug.assert(self.is_valid());

        for (seq.slice()) |key| {
            self.state_checker.on_key_down(key);
            self.keyboard.keydown(key);
            self.stats.key_events += 1;
        }
    }

    fn execute_sequence_up(self: *VOPR, seq: *const input_fuzz.KeySequence) void {
        std.debug.assert(self.is_valid());

        var j: u8 = seq.len;

        while (j > 0) {
            j -= 1;

            const key = seq.keys[j];

            self.state_checker.on_key_up(key);
            self.keyboard.keyup(key);
            self.stats.key_events += 1;
        }

        std.debug.assert(j == 0);
    }

    fn execute_clear_keyboard(self: *VOPR) void {
        std.debug.assert(self.is_valid());

        self.keyboard.clear();
        self.state_checker.shadow_keyboard.clear();
        self.held_keys_count = 0;
        self.held_modifiers_count = 0;

        std.debug.assert(self.held_keys_count == 0);
        std.debug.assert(self.held_modifiers_count == 0);
    }

    fn add_held_key(self: *VOPR, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        if (self.held_keys_count >= max_held_keys) {
            return;
        }

        std.debug.assert(self.held_keys_count < max_held_keys);

        self.held_keys[self.held_keys_count] = key;
        self.held_keys_count += 1;

        std.debug.assert(self.held_keys_count <= max_held_keys);
    }

    fn remove_held_key(self: *VOPR, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        var i: u32 = 0;

        while (i < self.held_keys_count and i < max_held_keys) : (i += 1) {
            std.debug.assert(i < self.held_keys_count);

            if (self.held_keys[i] == key) {
                self.held_keys[i] = self.held_keys[self.held_keys_count - 1];
                self.held_keys_count -= 1;
                break;
            }
        }

        std.debug.assert(i <= max_held_keys);
    }

    fn add_held_modifier(self: *VOPR, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        if (self.held_modifiers_count >= max_held_modifiers) {
            return;
        }

        std.debug.assert(self.held_modifiers_count < max_held_modifiers);

        self.held_modifiers[self.held_modifiers_count] = key;
        self.held_modifiers_count += 1;

        std.debug.assert(self.held_modifiers_count <= max_held_modifiers);
    }

    fn remove_held_modifier(self: *VOPR, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        var i: u32 = 0;

        while (i < self.held_modifiers_count and i < max_held_modifiers) : (i += 1) {
            std.debug.assert(i < self.held_modifiers_count);

            if (self.held_modifiers[i] == key) {
                self.held_modifiers[i] = self.held_modifiers[self.held_modifiers_count - 1];
                self.held_modifiers_count -= 1;
                break;
            }
        }

        std.debug.assert(i <= max_held_modifiers);
    }

    fn vopr_callback(ctx: *anyopaque, _: *const Key) Response {
        const context: *CallbackContext = @ptrCast(@alignCast(ctx));

        std.debug.assert(@intFromPtr(context) != 0);
        std.debug.assert(@intFromPtr(context.vopr) != 0);

        context.triggered_count += 1;

        var random = context.vopr.prng.random();
        const choice = random.intRangeLessThan(u8, 0, 100);

        if (choice < 60) {
            context.last_response = .pass;
        } else if (choice < 90) {
            context.last_response = .consume;
        } else {
            context.last_response = .replace;
        }

        return context.last_response;
    }
};

const testing = std.testing;

test "VOPR init" {
    const config = VOPRConfig{ .seed = 42 };

    std.debug.assert(config.is_valid());

    var vopr = VOPR.init(config);
    vopr.init_references();
    defer vopr.deinit();

    std.debug.assert(vopr.is_valid());
    std.debug.assert(vopr.current_tick == 0);

    try testing.expectEqual(@as(u64, 0), vopr.current_tick);
    try testing.expectEqual(@as(u32, 0), vopr.registered_count);
}

test "VOPR run basic" {
    const config = VOPRConfig{
        .seed = 42,
        .max_ticks = 1000,
        .fault_probability = 0,
    };

    std.debug.assert(config.is_valid());

    var vopr = VOPR.init(config);
    defer vopr.deinit();

    const result = vopr.run();

    std.debug.assert(vopr.stats.total_ticks > 0);
    std.debug.assert(vopr.stats.total_operations > 0);

    try testing.expect(result == .success);
    try testing.expect(vopr.stats.total_ticks > 0);
    try testing.expect(vopr.stats.total_operations > 0);
}

test "VOPR realistic profile" {
    const config = VOPRConfig{
        .seed = 42,
        .max_ticks = 1000,
        .test_profile = .realistic,
        .fault_probability = 0,
    };

    std.debug.assert(config.is_valid());

    var vopr = VOPR.init(config);
    defer vopr.deinit();

    _ = vopr.run();

    std.debug.assert(vopr.held_keys_count <= vopr.config.realistic.max_simultaneous_keys);
    std.debug.assert(vopr.held_modifiers_count <= vopr.config.realistic.max_simultaneous_modifiers);

    try testing.expect(vopr.held_keys_count <= vopr.config.realistic.max_simultaneous_keys);
    try testing.expect(vopr.held_modifiers_count <= vopr.config.realistic.max_simultaneous_modifiers);
}

test "VOPR run with faults" {
    const config = VOPRConfig{
        .seed = 12345,
        .max_ticks = 500,
        .fault_probability = 20,
    };

    std.debug.assert(config.is_valid());

    var vopr = VOPR.init(config);
    defer vopr.deinit();

    _ = vopr.run();

    std.debug.assert(vopr.stats.faults_injected > 0);

    try testing.expect(vopr.stats.faults_injected > 0);
}

test "VOPR determinism" {
    const config = VOPRConfig{ .seed = 99999, .max_ticks = 100 };

    std.debug.assert(config.is_valid());

    var vopr1 = VOPR.init(config);
    defer vopr1.deinit();
    _ = vopr1.run();

    var vopr2 = VOPR.init(config);
    defer vopr2.deinit();
    _ = vopr2.run();

    std.debug.assert(vopr1.stats.total_operations == vopr2.stats.total_operations);
    std.debug.assert(vopr1.stats.key_events == vopr2.stats.key_events);

    try testing.expectEqual(vopr1.stats.total_operations, vopr2.stats.total_operations);
    try testing.expectEqual(vopr1.stats.key_events, vopr2.stats.key_events);
    try testing.expectEqual(vopr1.state_checker.events_len, vopr2.state_checker.events_len);
}

test "VOPR reset" {
    const config = VOPRConfig{ .seed = 42, .max_ticks = 100 };

    std.debug.assert(config.is_valid());

    var vopr = VOPR.init(config);
    defer vopr.deinit();

    _ = vopr.run();
    const first_ops = vopr.stats.total_operations;

    std.debug.assert(first_ops > 0);

    vopr.reset(42);
    _ = vopr.run();

    std.debug.assert(vopr.stats.total_operations == first_ops);

    try testing.expectEqual(first_ops, vopr.stats.total_operations);
}

test "VOPR stress profile" {
    const config = VOPRConfig{
        .seed = 42,
        .max_ticks = 500,
        .test_profile = .stress,
    };

    std.debug.assert(config.is_valid());

    var vopr = VOPR.init(config);
    defer vopr.deinit();

    const result = vopr.run();

    std.debug.assert(vopr.current_tick == config.max_ticks);

    try testing.expect(result == .success);
}

test "VOPR mixed profile" {
    const config = VOPRConfig{
        .seed = 42,
        .max_ticks = 500,
        .test_profile = .mixed,
    };

    std.debug.assert(config.is_valid());

    var vopr = VOPR.init(config);
    defer vopr.deinit();

    const result = vopr.run();

    std.debug.assert(vopr.current_tick == config.max_ticks);

    try testing.expect(result == .success);
}
