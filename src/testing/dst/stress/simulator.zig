const std = @import("std");
const assert = std.debug.assert;

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

const max_queue_size: usize = 256;
const max_events: usize = 10000;
const max_ticks: u64 = 10_000_000;
const max_held_keys: usize = 16;
const max_held_modifiers: usize = 8;
const max_registered_bindings: usize = 64;
const max_iterations_per_tick: u32 = 1000;

pub const StressEventKind = enum(u8) {
    processing_delay = 0,
    queue_backpressure = 1,
    timing_window_miss = 2,
    input_coalesced = 3,
    system_stall = 4,
    hook_lost = 5,
    hook_restored = 6,
    cpu_spike = 7,
    cpu_normal = 8,
    input_reordered = 9,
    modifier_race = 10,
    rapid_repeat = 11,
    throttle_activated = 12,
    input_expired = 13,
    priority_drop = 14,
};

pub const StressEvent = struct {
    tick: u64,
    kind: StressEventKind,
    data: EventData,

    pub const EventData = union {
        delay_ns: u64,
        queue_depth: u32,
        window_miss: struct {
            key: u8,
            expected_tick: u64,
            actual_tick: u64,
            binding_id: u32,
        },
        coalesced_count: u32,
        stall_duration: u64,
        cpu_load: u8,
        race_keys: [2]u8,
        repeat_count: u32,
        none: void,
    };
};

pub const StressState = struct {
    timing_misses: u64 = 0,
    max_queue_depth: u32 = 0,
    total_processing_delay_ns: u64 = 0,
    coalesced_inputs: u64 = 0,
    expired_inputs: u64 = 0,
    throttle_activations: u64 = 0,
    hook_lost_drops: u64 = 0,
    stall_drops: u64 = 0,
    backpressure_drops: u64 = 0,
    hook_deaths: u64 = 0,
    hook_restores: u64 = 0,
    modifier_races: u64 = 0,
    in_stall: bool = false,
    cpu_load: u8 = 0,
    hook_alive: bool = true,
};

pub const TimingConfig = struct {
    processing_delay_min_ns: u64 = 1000,
    processing_delay_max_ns: u64 = 50000,
    slow_callback_probability: u8 = 5,
    slow_callback_min_ns: u64 = 100 * std.time.ns_per_ms,
    slow_callback_max_ns: u64 = 500 * std.time.ns_per_ms,
    stall_probability: u8 = 2,
    stall_min_ticks: u64 = 10,
    stall_max_ticks: u64 = 100,
    cpu_spike_probability: u8 = 3,
    cpu_spike_min_load: u8 = 50,
    cpu_spike_max_load: u8 = 100,
    hook_timeout_probability: u8 = 1,
    input_queue_capacity: usize = 64,
    use_resilient_queue: bool = false,

    pub fn validate(self: *const TimingConfig) bool {
        if (self.processing_delay_min_ns > self.processing_delay_max_ns) return false;
        if (self.slow_callback_min_ns > self.slow_callback_max_ns) return false;
        if (self.stall_min_ticks > self.stall_max_ticks) return false;
        if (self.cpu_spike_min_load > self.cpu_spike_max_load) return false;
        if (self.input_queue_capacity == 0) return false;
        if (self.input_queue_capacity > max_queue_size) return false;
        return true;
    }
};

pub const QueuedInput = struct {
    keycode: u8,
    down: bool,
    queued_at: u64,
    scheduled_for: u64,
    original_tick: u64,
    is_modifier: bool,
    coalesced_count: u32 = 0,
};

pub const StressSimulator = struct {
    prng: std.Random.DefaultPrng,
    config: TimingConfig,
    current_tick: u64,
    simulated_time_ns: u64,
    legacy_queue: [max_queue_size]QueuedInput,
    queue_head: usize,
    queue_tail: usize,
    queue_count: usize,
    events_buf: [max_events]StressEvent,
    events_len: usize,
    stress_state: StressState,
    stall_end_tick: u64,
    cpu_spike_end_tick: u64,
    pending_modifier: ?u8,

    pub fn init(seed: u64, config: TimingConfig) StressSimulator {
        assert(config.validate());

        const sim = StressSimulator{
            .prng = std.Random.DefaultPrng.init(seed),
            .config = config,
            .current_tick = 0,
            .simulated_time_ns = 0,
            .legacy_queue = undefined,
            .queue_head = 0,
            .queue_tail = 0,
            .queue_count = 0,
            .events_buf = undefined,
            .events_len = 0,
            .stress_state = .{},
            .stall_end_tick = 0,
            .cpu_spike_end_tick = 0,
            .pending_modifier = null,
        };

        assert(sim.queue_count == 0);
        assert(sim.events_len == 0);

        return sim;
    }

    pub fn tick(self: *StressSimulator) void {
        assert(self.current_tick < max_ticks);
        assert(self.queue_count <= self.config.input_queue_capacity);

        self.current_tick += 1;
        self.simulated_time_ns += std.time.ns_per_ms;

        self.update_system_state();
        self.process_queue();

        assert(self.queue_head < max_queue_size);
        assert(self.queue_tail < max_queue_size);
    }

    fn update_system_state(self: *StressSimulator) void {
        var random = self.prng.random();

        if (self.stress_state.in_stall and self.current_tick >= self.stall_end_tick) {
            self.stress_state.in_stall = false;
            self.record_event(.{
                .tick = self.current_tick,
                .kind = .hook_restored,
                .data = .{ .none = {} },
            });
            self.stress_state.hook_restores += 1;
        }

        if (self.stress_state.cpu_load > 0 and self.current_tick >= self.cpu_spike_end_tick) {
            self.stress_state.cpu_load = 0;
            self.record_event(.{
                .tick = self.current_tick,
                .kind = .cpu_normal,
                .data = .{ .none = {} },
            });
        }

        if (!self.stress_state.in_stall and random.intRangeLessThan(u8, 0, 100) < self.config.stall_probability) {
            const duration = random.intRangeAtMost(u64, self.config.stall_min_ticks, self.config.stall_max_ticks);
            self.stress_state.in_stall = true;
            self.stall_end_tick = self.current_tick + duration;
            self.record_event(.{
                .tick = self.current_tick,
                .kind = .system_stall,
                .data = .{ .stall_duration = duration },
            });
        }

        if (self.stress_state.cpu_load == 0 and random.intRangeLessThan(u8, 0, 100) < self.config.cpu_spike_probability) {
            self.stress_state.cpu_load = random.intRangeAtMost(u8, self.config.cpu_spike_min_load, self.config.cpu_spike_max_load);
            self.cpu_spike_end_tick = self.current_tick + random.intRangeAtMost(u64, 5, 50);
            self.record_event(.{
                .tick = self.current_tick,
                .kind = .cpu_spike,
                .data = .{ .cpu_load = self.stress_state.cpu_load },
            });
        }

        if (self.stress_state.hook_alive and random.intRangeLessThan(u8, 0, 100) < self.config.hook_timeout_probability) {
            self.stress_state.hook_alive = false;
            self.stress_state.hook_deaths += 1;
            self.record_event(.{
                .tick = self.current_tick,
                .kind = .hook_lost,
                .data = .{ .stall_duration = 0 },
            });
        }

        if (!self.stress_state.hook_alive and random.intRangeLessThan(u8, 0, 100) < 20) {
            self.stress_state.hook_alive = true;
            self.stress_state.hook_restores += 1;
            self.record_event(.{
                .tick = self.current_tick,
                .kind = .hook_restored,
                .data = .{ .none = {} },
            });
        }
    }

    pub fn queue_input(self: *StressSimulator, key: u8, down: bool) bool {
        assert(key >= keycode.value_min);
        assert(key <= keycode.value_max);

        if (self.queue_count >= self.config.input_queue_capacity) {
            self.stress_state.backpressure_drops += 1;
            self.record_event(.{
                .tick = self.current_tick,
                .kind = .queue_backpressure,
                .data = .{ .queue_depth = @intCast(self.queue_count) },
            });
            return false;
        }

        if (!self.stress_state.hook_alive) {
            self.stress_state.hook_lost_drops += 1;
            return false;
        }

        if (self.stress_state.in_stall) {
            self.stress_state.stall_drops += 1;
            return false;
        }

        var random = self.prng.random();
        var delay: u64 = random.intRangeAtMost(u64, self.config.processing_delay_min_ns, self.config.processing_delay_max_ns);

        if (random.intRangeLessThan(u8, 0, 100) < self.config.slow_callback_probability) {
            delay = random.intRangeAtMost(u64, self.config.slow_callback_min_ns, self.config.slow_callback_max_ns);
        }

        if (self.stress_state.cpu_load > 0) {
            delay = delay * (100 + @as(u64, self.stress_state.cpu_load)) / 100;
        }

        const is_modifier = keycode.is_modifier(key);

        self.legacy_queue[self.queue_tail] = .{
            .keycode = key,
            .down = down,
            .queued_at = self.simulated_time_ns,
            .scheduled_for = self.simulated_time_ns + delay,
            .original_tick = self.current_tick,
            .is_modifier = is_modifier,
            .coalesced_count = 0,
        };

        self.queue_tail = (self.queue_tail + 1) % max_queue_size;
        self.queue_count += 1;

        if (self.queue_count > self.stress_state.max_queue_depth) {
            self.stress_state.max_queue_depth = @intCast(self.queue_count);
        }

        self.stress_state.total_processing_delay_ns += delay;

        if (is_modifier) {
            self.pending_modifier = key;
        }

        assert(self.queue_count <= self.config.input_queue_capacity);
        return true;
    }

    fn process_queue(self: *StressSimulator) void {
        var iterations: u32 = 0;

        while (self.queue_count > 0) {
            if (iterations >= max_iterations_per_tick) {
                break;
            }

            const input_item = self.legacy_queue[self.queue_head];

            if (input_item.scheduled_for > self.simulated_time_ns) {
                break;
            }

            const age_ns = self.simulated_time_ns - input_item.queued_at;
            if (age_ns > 100 * std.time.ns_per_ms) {
                self.record_event(.{
                    .tick = self.current_tick,
                    .kind = .timing_window_miss,
                    .data = .{
                        .window_miss = .{
                            .key = input_item.keycode,
                            .expected_tick = input_item.original_tick,
                            .actual_tick = self.current_tick,
                            .binding_id = 0,
                        },
                    },
                });
                self.stress_state.timing_misses += 1;
            }

            if (input_item.is_modifier and self.pending_modifier != null and self.pending_modifier.? == input_item.keycode) {
                self.pending_modifier = null;
            }

            self.queue_head = (self.queue_head + 1) % max_queue_size;
            self.queue_count -= 1;
            iterations += 1;
        }

        assert(iterations <= max_iterations_per_tick);
    }

    pub fn get_next_ready_input(self: *StressSimulator) ?QueuedInput {
        if (self.queue_count == 0) return null;

        const input_item = self.legacy_queue[self.queue_head];
        if (input_item.scheduled_for <= self.simulated_time_ns) {
            self.queue_head = (self.queue_head + 1) % max_queue_size;
            self.queue_count -= 1;
            return input_item;
        }

        return null;
    }

    fn record_event(self: *StressSimulator, evt: StressEvent) void {
        if (self.events_len < max_events) {
            self.events_buf[self.events_len] = evt;
            self.events_len += 1;
        }
    }

    pub fn get_events(self: *const StressSimulator) []const StressEvent {
        return self.events_buf[0..self.events_len];
    }

    pub fn get_state(self: *const StressSimulator) StressState {
        return self.stress_state;
    }

    pub fn get_queue_depth(self: *StressSimulator) usize {
        return self.queue_count;
    }

    pub fn is_under_stress(self: *StressSimulator) bool {
        const threshold = self.config.input_queue_capacity / 2;

        return self.stress_state.in_stall or
            self.stress_state.cpu_load > 50 or
            !self.stress_state.hook_alive or
            self.queue_count > threshold;
    }
};

pub const StressVOPRConfig = struct {
    seed: u64,
    max_ticks: u64 = 100000,
    timing: TimingConfig = .{},
    realistic_keys: bool = true,
    max_simultaneous_keys: u8 = 4,
    burst_probability: u8 = 10,
    burst_min_length: u8 = 3,
    burst_max_length: u8 = 10,
    burst_interval_min: u64 = 1,
    burst_interval_max: u64 = 5,

    pub fn validate(self: *const StressVOPRConfig) bool {
        if (self.max_ticks == 0) return false;
        if (self.max_ticks > max_ticks) return false;
        if (self.burst_min_length > self.burst_max_length) return false;
        if (self.burst_interval_min > self.burst_interval_max) return false;
        if (self.max_simultaneous_keys == 0) return false;
        if (self.max_simultaneous_keys > max_held_keys) return false;
        if (!self.timing.validate()) return false;
        return true;
    }
};

pub const StressVOPR = struct {
    keyboard: Keyboard,
    registry_key: KeyRegistry(1024),
    stress_sim: StressSimulator,
    prng: std.Random.DefaultPrng,
    config: StressVOPRConfig,
    current_tick: u64,
    held_keys: [max_held_keys]u8,
    held_keys_count: usize,
    held_modifiers: [max_held_modifiers]u8,
    held_modifiers_count: usize,
    in_burst: bool,
    burst_remaining: u8,
    burst_interval: u64,
    last_burst_tick: u64,
    registered_ids: [max_registered_bindings]u32,
    registered_count: usize,
    stats: StressStats,
    callback_context: CallbackContext,

    const CallbackContext = struct {
        vopr: *StressVOPR,
        triggered_count: u64,
    };

    pub const StressStats = struct {
        total_ticks: u64 = 0,
        inputs_queued: u64 = 0,
        inputs_processed: u64 = 0,
        inputs_dropped: u64 = 0,
        timing_misses: u64 = 0,
        bursts_generated: u64 = 0,
        bindings_triggered: u64 = 0,
        max_queue_depth: u32 = 0,
        total_delay_ns: u64 = 0,
        stress_ticks: u64 = 0,
        coalesced: u64 = 0,
        expired: u64 = 0,
        throttle_activations: u64 = 0,
        hook_lost_drops: u64 = 0,
        stall_drops: u64 = 0,
        backpressure_drops: u64 = 0,
        hook_deaths: u64 = 0,
        hook_restores: u64 = 0,
    };

    const common_keys = [_]u8{
        'A',           'B',               'C',         'D',            'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M',
        'N',           'O',               'P',         'Q',            'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
        keycode.space, keycode.@"return", keycode.tab, keycode.escape,
    };

    pub fn init(config: StressVOPRConfig) StressVOPR {
        assert(config.validate());

        const vopr = StressVOPR{
            .keyboard = Keyboard.init(),
            .registry_key = KeyRegistry(1024).init(),
            .stress_sim = StressSimulator.init(config.seed, config.timing),
            .prng = std.Random.DefaultPrng.init(config.seed +% 0x12345),
            .config = config,
            .current_tick = 0,
            .held_keys = [_]u8{0} ** max_held_keys,
            .held_keys_count = 0,
            .held_modifiers = [_]u8{0} ** max_held_modifiers,
            .held_modifiers_count = 0,
            .in_burst = false,
            .burst_remaining = 0,
            .burst_interval = 0,
            .last_burst_tick = 0,
            .registered_ids = [_]u32{0} ** max_registered_bindings,
            .registered_count = 0,
            .stats = .{},
            .callback_context = undefined,
        };

        assert(vopr.current_tick == 0);
        assert(vopr.held_keys_count == 0);

        return vopr;
    }

    pub fn deinit(self: *StressVOPR) void {
        self.registry_key.clear();
    }

    pub fn run(self: *StressVOPR) void {
        assert(self.config.max_ticks <= max_ticks);

        self.callback_context = .{
            .vopr = self,
            .triggered_count = 0,
        };

        while (self.current_tick < self.config.max_ticks) {
            self.generate_inputs();
            self.stress_sim.tick();
            self.process_ready_inputs();

            if (self.stress_sim.is_under_stress()) {
                self.stats.stress_ticks += 1;
            }

            self.current_tick += 1;
            self.stats.total_ticks = self.current_tick;

            assert(self.held_keys_count <= max_held_keys);
            assert(self.held_modifiers_count <= max_held_modifiers);
        }

        self.finalize_stats();

        assert(self.stats.total_ticks == self.config.max_ticks);
    }

    fn generate_inputs(self: *StressVOPR) void {
        var random = self.prng.random();

        if (self.in_burst) {
            self.generate_burst_input(&random);
            return;
        }

        if (random.intRangeLessThan(u8, 0, 100) < self.config.burst_probability) {
            self.start_burst(&random);
            return;
        }

        self.generate_normal_input(&random);
    }

    fn generate_normal_input(self: *StressVOPR, random: *std.Random) void {
        const total_held = self.held_keys_count + self.held_modifiers_count;

        if (total_held > 0 and random.intRangeLessThan(u8, 0, 100) < 60) {
            self.release_key(random);
            return;
        }

        if (self.held_keys_count >= self.config.max_simultaneous_keys) {
            self.release_key(random);
            return;
        }

        if (self.held_modifiers_count == 0 and random.intRangeLessThan(u8, 0, 100) < 30) {
            self.press_modifier(random);
            return;
        }

        self.press_key(random);
    }

    fn start_burst(self: *StressVOPR, random: *std.Random) void {
        assert(self.config.burst_min_length <= self.config.burst_max_length);

        self.in_burst = true;
        self.burst_remaining = random.intRangeAtMost(u8, self.config.burst_min_length, self.config.burst_max_length);
        self.burst_interval = random.intRangeAtMost(u64, self.config.burst_interval_min, self.config.burst_interval_max);
        self.last_burst_tick = self.current_tick;
        self.stats.bursts_generated += 1;

        assert(self.burst_remaining >= self.config.burst_min_length);
    }

    fn generate_burst_input(self: *StressVOPR, random: *std.Random) void {
        if (self.current_tick - self.last_burst_tick < self.burst_interval) {
            return;
        }

        self.last_burst_tick = self.current_tick;
        self.burst_remaining -= 1;

        if (self.burst_remaining == 0) {
            self.in_burst = false;
        }

        const key = self.select_key(random);

        if (self.stress_sim.queue_input(key, true)) {
            self.stats.inputs_queued += 1;
        }

        if (self.stress_sim.queue_input(key, false)) {
            self.stats.inputs_queued += 1;
        }
    }

    fn press_key(self: *StressVOPR, random: *std.Random) void {
        const key = self.select_key(random);

        if (self.stress_sim.queue_input(key, true)) {
            self.stats.inputs_queued += 1;
            self.add_held_key(key);
        }
    }

    fn release_key(self: *StressVOPR, random: *std.Random) void {
        if (self.held_keys_count > 0 and random.intRangeLessThan(u8, 0, 100) < 70) {
            const idx = random.intRangeLessThan(usize, 0, self.held_keys_count);
            const key = self.held_keys[idx];

            if (self.stress_sim.queue_input(key, false)) {
                self.stats.inputs_queued += 1;
                self.remove_held_key(key);
            }
        } else if (self.held_modifiers_count > 0) {
            const idx = random.intRangeLessThan(usize, 0, self.held_modifiers_count);
            const mod = self.held_modifiers[idx];

            if (self.stress_sim.queue_input(mod, false)) {
                self.stats.inputs_queued += 1;
                self.remove_held_modifier(mod);
            }
        }
    }

    fn press_modifier(self: *StressVOPR, random: *std.Random) void {
        const modifiers = [_]u8{ keycode.lctrl, keycode.lmenu, keycode.lshift, keycode.lwin };
        const mod = modifiers[random.intRangeLessThan(usize, 0, modifiers.len)];

        if (self.stress_sim.queue_input(mod, true)) {
            self.stats.inputs_queued += 1;
            self.add_held_modifier(mod);
        }
    }

    fn select_key(self: *StressVOPR, random: *std.Random) u8 {
        if (self.config.realistic_keys) {
            return common_keys[random.intRangeLessThan(usize, 0, common_keys.len)];
        }

        return random.intRangeAtMost(u8, keycode.value_min, keycode.value_max);
    }

    fn process_ready_inputs(self: *StressVOPR) void {
        var iterations: u32 = 0;

        while (iterations < max_iterations_per_tick) {
            const input_item = self.stress_sim.get_next_ready_input() orelse break;

            if (input_item.down) {
                self.keyboard.keydown(input_item.keycode);
            } else {
                self.keyboard.keyup(input_item.keycode);
            }

            const key = Key{
                .value = input_item.keycode,
                .scan = 0,
                .down = input_item.down,
                .injected = false,
                .extended = false,
                .extra = 0,
                .modifiers = self.keyboard.get_modifiers(),
            };

            if (self.registry_key.process(&key)) |_| {
                self.stats.bindings_triggered += 1;
            }

            self.stats.inputs_processed += 1;
            iterations += 1;
        }

        assert(iterations <= max_iterations_per_tick);
    }

    fn add_held_key(self: *StressVOPR, key: u8) void {
        if (self.held_keys_count < max_held_keys) {
            self.held_keys[self.held_keys_count] = key;
            self.held_keys_count += 1;
        }
    }

    fn remove_held_key(self: *StressVOPR, key: u8) void {
        for (0..self.held_keys_count) |i| {
            if (self.held_keys[i] == key) {
                self.held_keys[i] = self.held_keys[self.held_keys_count - 1];
                self.held_keys_count -= 1;
                return;
            }
        }
    }

    fn add_held_modifier(self: *StressVOPR, mod: u8) void {
        if (self.held_modifiers_count < max_held_modifiers) {
            self.held_modifiers[self.held_modifiers_count] = mod;
            self.held_modifiers_count += 1;
        }
    }

    fn remove_held_modifier(self: *StressVOPR, mod: u8) void {
        for (0..self.held_modifiers_count) |i| {
            if (self.held_modifiers[i] == mod) {
                self.held_modifiers[i] = self.held_modifiers[self.held_modifiers_count - 1];
                self.held_modifiers_count -= 1;
                return;
            }
        }
    }

    fn finalize_stats(self: *StressVOPR) void {
        const stress_state = self.stress_sim.get_state();
        self.stats.timing_misses = stress_state.timing_misses;
        self.stats.max_queue_depth = stress_state.max_queue_depth;
        self.stats.total_delay_ns = stress_state.total_processing_delay_ns;
        self.stats.coalesced = stress_state.coalesced_inputs;
        self.stats.expired = stress_state.expired_inputs;
        self.stats.throttle_activations = stress_state.throttle_activations;
        self.stats.hook_lost_drops = stress_state.hook_lost_drops;
        self.stats.stall_drops = stress_state.stall_drops;
        self.stats.backpressure_drops = stress_state.backpressure_drops;
        self.stats.hook_deaths = stress_state.hook_deaths;
        self.stats.hook_restores = stress_state.hook_restores;
        self.stats.inputs_dropped = self.stats.hook_lost_drops + self.stats.stall_drops + self.stats.backpressure_drops;

        assert(self.stats.inputs_processed <= self.stats.inputs_queued);
    }

    pub fn register_binding(self: *StressVOPR, key: u8, mods: modifier.Set) !u32 {
        assert(self.registered_count < max_registered_bindings);

        const id = try self.registry_key.register(
            CallbackContext,
            key,
            mods,
            &self.callback_context,
            stress_callback,
        );

        if (self.registered_count < max_registered_bindings) {
            self.registered_ids[self.registered_count] = id;
            self.registered_count += 1;
        }

        return id;
    }

    fn stress_callback(_: *CallbackContext, _: *const Key) Response {
        return .pass;
    }

    pub fn get_stats(self: *const StressVOPR) StressStats {
        return self.stats;
    }

    pub fn get_stress_events(self: *const StressVOPR) []const StressEvent {
        return self.stress_sim.get_events();
    }

    pub fn get_stress_state(self: *const StressVOPR) StressState {
        return self.stress_sim.get_state();
    }
};

const testing = std.testing;

test "StressSimulator basic" {
    var sim = StressSimulator.init(42, .{ .hook_timeout_probability = 0 });

    try testing.expect(sim.queue_input('A', true));

    for (0..10) |_| {
        sim.tick();
    }
}

test "StressVOPR init" {
    var vopr = StressVOPR.init(.{
        .seed = 42,
        .max_ticks = 100,
    });
    defer vopr.deinit();

    try testing.expectEqual(@as(u64, 0), vopr.current_tick);
}

test "StressVOPR run" {
    var vopr = StressVOPR.init(.{
        .seed = 42,
        .max_ticks = 1000,
        .timing = .{ .hook_timeout_probability = 0 },
    });
    defer vopr.deinit();

    vopr.run();

    try testing.expect(vopr.stats.total_ticks == 1000);
    try testing.expect(vopr.stats.inputs_queued > 0);
}
