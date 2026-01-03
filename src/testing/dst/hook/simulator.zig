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

pub const timeout_ms: u64 = 200;
pub const timeout_ns: u64 = timeout_ms * std.time.ns_per_ms;
pub const warning_threshold_ns: u64 = 150 * std.time.ns_per_ms;

pub const iteration_max: u32 = 0xFFFFFFFF;
pub const event_capacity: u32 = 65536;
pub const event_max: u8 = 12;
pub const state_max: u8 = 6;
pub const health_max: u8 = 3;
pub const probability_max: u8 = 100;
pub const reinstall_success_threshold: u8 = 90;

pub const Event = enum(u8) {
    installed = 0,
    removed = 1,
    timeout = 2,
    reinstalled = 3,
    desktop_switched = 4,
    session_locked = 5,
    session_unlocked = 6,
    system_sleep = 7,
    system_resume = 8,
    uac_prompt = 9,
    uac_dismissed = 10,
    remote_connect = 11,
    remote_disconnect = 12,

    pub fn is_valid(self: Event) bool {
        const value = @intFromEnum(self);

        std.debug.assert(event_max == 12);

        const result = value <= event_max;

        return result;
    }
};

pub const State = enum(u8) {
    installed = 0,
    removed = 1,
    timeout_pending = 2,
    reinstalling = 3,
    blocked_secure_desktop = 4,
    blocked_uac = 5,
    blocked_session_locked = 6,

    pub fn is_valid(self: State) bool {
        const value = @intFromEnum(self);

        std.debug.assert(state_max == 6);

        const result = value <= state_max;

        return result;
    }
};

pub const Health = enum(u8) {
    healthy = 0,
    degraded = 1,
    presumed_unhooked = 2,
    confirmed_unhooked = 3,

    pub fn is_valid(self: Health) bool {
        const value = @intFromEnum(self);

        std.debug.assert(health_max == 3);

        const result = value <= health_max;

        return result;
    }
};

pub const RecordedEvent = struct {
    tick: u64,
    event: Event,
    callback_time_ns: u64,
    hook_state: State,
    health: Health,

    pub fn is_valid(self: *const RecordedEvent) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_event = self.event.is_valid();
        const valid_state = self.hook_state.is_valid();
        const valid_health = self.health.is_valid();
        const result = valid_event and valid_state and valid_health;

        return result;
    }
};

pub const Config = struct {
    seed: u64,
    max_ticks: u64 = 50000,
    timeout_probability: u8 = 2,
    slow_callback_probability: u8 = 5,
    desktop_switch_probability: u8 = 1,
    session_lock_probability: u8 = 1,
    uac_probability: u8 = 1,
    sleep_probability: u8 = 1,

    pub fn is_valid(self: *const Config) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_timeout = self.timeout_probability <= probability_max;
        const valid_slow = self.slow_callback_probability <= probability_max;
        const valid_desktop = self.desktop_switch_probability <= probability_max;
        const valid_session = self.session_lock_probability <= probability_max;
        const valid_uac = self.uac_probability <= probability_max;
        const valid_sleep = self.sleep_probability <= probability_max;
        const result = valid_timeout and valid_slow and valid_desktop and valid_session and valid_uac and valid_sleep;

        return result;
    }
};

pub const Stats = struct {
    total_callbacks: u64 = 0,
    callbacks_under_threshold: u64 = 0,
    callbacks_over_threshold: u64 = 0,
    timeouts_triggered: u64 = 0,
    silent_unhooks: u64 = 0,
    reinstall_attempts: u64 = 0,
    reinstall_successes: u64 = 0,
    reinstall_failures: u64 = 0,
    inputs_lost: u64 = 0,
    max_callback_ns: u64 = 0,
    total_callback_ns: u64 = 0,
    desktop_switches: u64 = 0,
    session_locks: u64 = 0,
    uac_prompts: u64 = 0,
    max_consecutive_slow: u64 = 0,

    pub fn is_valid(self: *const Stats) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_callbacks = self.callbacks_under_threshold + self.callbacks_over_threshold <= self.total_callbacks;
        const valid_reinstalls = self.reinstall_successes + self.reinstall_failures <= self.reinstall_attempts;
        const result = valid_callbacks and valid_reinstalls;

        return result;
    }

    pub fn avg_callback_ns(self: *const Stats) u64 {
        std.debug.assert(self.is_valid());

        if (self.total_callbacks == 0) {
            return 0;
        }

        std.debug.assert(self.total_callbacks > 0);

        const result = self.total_callback_ns / self.total_callbacks;

        return result;
    }
};

pub const HealthMonitor = struct {
    consecutive_slow: u64 = 0,
    consecutive_fast: u64 = 0,
    last_callback_ns: u64 = 0,
    total_samples: u64 = 0,
    slow_samples: u64 = 0,

    const degraded_threshold: u64 = 5;
    const presumed_unhooked_threshold: u64 = 10;

    pub fn init() HealthMonitor {
        const result = HealthMonitor{};

        std.debug.assert(result.consecutive_slow == 0);
        std.debug.assert(result.consecutive_fast == 0);
        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn is_valid(self: *const HealthMonitor) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_samples = self.slow_samples <= self.total_samples;
        const result = valid_samples;

        return result;
    }

    pub fn record_callback(self: *HealthMonitor, duration_ns: u64) void {
        std.debug.assert(self.is_valid());

        self.last_callback_ns = duration_ns;
        self.total_samples += 1;

        if (duration_ns > warning_threshold_ns) {
            self.consecutive_slow += 1;
            self.consecutive_fast = 0;
            self.slow_samples += 1;
        } else {
            self.consecutive_fast += 1;
            self.consecutive_slow = 0;
        }

        std.debug.assert(self.is_valid());
    }

    pub fn get_health(self: *const HealthMonitor) Health {
        std.debug.assert(self.is_valid());

        if (self.consecutive_slow >= presumed_unhooked_threshold) {
            return .presumed_unhooked;
        }

        if (self.consecutive_slow >= degraded_threshold) {
            return .degraded;
        }

        return .healthy;
    }

    pub fn reset(self: *HealthMonitor) void {
        std.debug.assert(self.is_valid());

        self.consecutive_slow = 0;
        self.consecutive_fast = 0;
        self.last_callback_ns = 0;

        std.debug.assert(self.consecutive_slow == 0);
        std.debug.assert(self.consecutive_fast == 0);
        std.debug.assert(self.is_valid());
    }
};

pub const Simulator = struct {
    allocator: std.mem.Allocator,
    config: Config,
    prng: std.Random.DefaultPrng,
    keyboard: Keyboard,
    registry_key: KeyRegistry(1024),
    current_tick: u64,
    hook_state: State,
    health: Health,
    health_monitor: HealthMonitor,
    stats: Stats,
    events: std.ArrayListUnmanaged(RecordedEvent),
    session_locked: bool,
    in_uac: bool,
    in_sleep: bool,
    desktop_secure: bool,

    const callback_min_ns: u64 = 1000;
    const callback_max_ns: u64 = 50000;

    pub fn init(allocator: std.mem.Allocator, config: Config) Simulator {
        std.debug.assert(config.is_valid());

        const result = Simulator{
            .allocator = allocator,
            .config = config,
            .prng = std.Random.DefaultPrng.init(config.seed),
            .keyboard = Keyboard.init(),
            .registry_key = KeyRegistry(1024).init(),
            .current_tick = 0,
            .hook_state = .installed,
            .health = .healthy,
            .health_monitor = HealthMonitor.init(),
            .stats = .{},
            .events = .{},
            .session_locked = false,
            .in_uac = false,
            .in_sleep = false,
            .desktop_secure = false,
        };

        std.debug.assert(result.current_tick == 0);
        std.debug.assert(result.hook_state == .installed);
        std.debug.assert(result.health == .healthy);
        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn is_valid(self: *const Simulator) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_config = self.config.is_valid();
        const valid_state = self.hook_state.is_valid();
        const valid_health = self.health.is_valid();
        const valid_monitor = self.health_monitor.is_valid();
        const valid_stats = self.stats.is_valid();
        const result = valid_config and valid_state and valid_health and valid_monitor and valid_stats;

        return result;
    }

    pub fn deinit(self: *Simulator) void {
        std.debug.assert(self.is_valid());

        self.events.deinit(self.allocator);
        self.registry_key.clear();
    }

    pub fn get_stats(self: *const Simulator) Stats {
        std.debug.assert(self.is_valid());

        const result = self.stats;

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn get_events(self: *const Simulator) []const RecordedEvent {
        std.debug.assert(self.is_valid());

        const result = self.events.items;

        return result;
    }

    pub fn reset(self: *Simulator, seed: u64) void {
        std.debug.assert(self.is_valid());

        self.prng = std.Random.DefaultPrng.init(seed);
        self.keyboard.clear();
        self.registry_key.clear();
        self.current_tick = 0;
        self.hook_state = .installed;
        self.health = .healthy;
        self.health_monitor.reset();
        self.stats = .{};
        self.events.clearRetainingCapacity();
        self.session_locked = false;
        self.in_uac = false;
        self.in_sleep = false;
        self.desktop_secure = false;

        std.debug.assert(self.current_tick == 0);
        std.debug.assert(self.hook_state == .installed);
        std.debug.assert(self.health == .healthy);
        std.debug.assert(self.is_valid());
    }

    pub fn run(self: *Simulator) void {
        std.debug.assert(self.is_valid());

        var iteration: u64 = 0;

        while (iteration < self.config.max_ticks and iteration < iteration_max) : (iteration += 1) {
            std.debug.assert(iteration < self.config.max_ticks);
            std.debug.assert(iteration < iteration_max);

            self.tick();
            self.current_tick += 1;
        }

        std.debug.assert(iteration == self.config.max_ticks or iteration == iteration_max);
        std.debug.assert(self.is_valid());
    }

    fn tick(self: *Simulator) void {
        std.debug.assert(self.is_valid());

        var random = self.prng.random();

        self.check_system_events(&random);

        if (self.hook_state == .installed) {
            self.simulate_callback(&random);
        }

        self.health = self.health_monitor.get_health();

        std.debug.assert(self.health.is_valid());
        std.debug.assert(self.is_valid());
    }

    fn check_system_events(self: *Simulator, random: *std.Random) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(random) != 0);

        self.check_session_lock(random);
        self.check_uac(random);
        self.check_desktop_switch(random);

        std.debug.assert(self.is_valid());
    }

    fn check_session_lock(self: *Simulator, random: *std.Random) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(random) != 0);

        const roll = random.intRangeLessThan(u8, 0, probability_max);

        if (roll >= self.config.session_lock_probability) {
            return;
        }

        if (self.session_locked) {
            self.record_event(.session_unlocked);
            self.session_locked = false;
            self.hook_state = .installed;
            self.health = .healthy;
        } else {
            self.record_event(.session_locked);
            self.session_locked = true;
            self.hook_state = .blocked_session_locked;
            self.health = .confirmed_unhooked;
            self.stats.session_locks += 1;
        }

        std.debug.assert(self.is_valid());
    }

    fn check_uac(self: *Simulator, random: *std.Random) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(random) != 0);

        if (self.session_locked) {
            return;
        }

        const roll = random.intRangeLessThan(u8, 0, probability_max);

        if (roll >= self.config.uac_probability) {
            return;
        }

        if (self.in_uac) {
            self.record_event(.uac_dismissed);
            self.in_uac = false;
            self.desktop_secure = false;
            self.hook_state = .installed;
            self.health = .healthy;
        } else {
            self.record_event(.uac_prompt);
            self.in_uac = true;
            self.desktop_secure = true;
            self.hook_state = .blocked_uac;
            self.health = .presumed_unhooked;
            self.stats.uac_prompts += 1;
        }

        std.debug.assert(self.is_valid());
    }

    fn check_desktop_switch(self: *Simulator, random: *std.Random) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(random) != 0);

        const roll = random.intRangeLessThan(u8, 0, probability_max);

        if (roll >= self.config.desktop_switch_probability) {
            return;
        }

        self.record_event(.desktop_switched);
        self.stats.desktop_switches += 1;

        std.debug.assert(self.is_valid());
    }

    fn simulate_callback(self: *Simulator, random: *std.Random) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(random) != 0);

        var callback_ns: u64 = random.intRangeAtMost(u64, callback_min_ns, callback_max_ns);

        const slow_roll = random.intRangeLessThan(u8, 0, probability_max);

        if (slow_roll < self.config.slow_callback_probability) {
            callback_ns = random.intRangeAtMost(u64, warning_threshold_ns, timeout_ns * 2);
        }

        self.health_monitor.record_callback(callback_ns);
        self.stats.total_callbacks += 1;
        self.stats.total_callback_ns += callback_ns;

        if (callback_ns > self.stats.max_callback_ns) {
            self.stats.max_callback_ns = callback_ns;
        }

        if (callback_ns < warning_threshold_ns) {
            self.stats.callbacks_under_threshold += 1;
        } else {
            self.stats.callbacks_over_threshold += 1;
        }

        if (self.health_monitor.consecutive_slow > self.stats.max_consecutive_slow) {
            self.stats.max_consecutive_slow = self.health_monitor.consecutive_slow;
        }

        if (callback_ns > timeout_ns) {
            self.record_event(.timeout);
            self.stats.timeouts_triggered += 1;
            self.attempt_reinstall(random);
        }

        std.debug.assert(self.stats.is_valid());
        std.debug.assert(self.is_valid());
    }

    fn attempt_reinstall(self: *Simulator, random: *std.Random) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(random) != 0);

        self.stats.reinstall_attempts += 1;
        self.hook_state = .reinstalling;

        const success_roll = random.intRangeLessThan(u8, 0, probability_max);

        if (success_roll < reinstall_success_threshold) {
            self.record_event(.reinstalled);
            self.hook_state = .installed;
            self.health_monitor.reset();
            self.stats.reinstall_successes += 1;
        } else {
            self.hook_state = .removed;
            self.health = .confirmed_unhooked;
            self.stats.reinstall_failures += 1;
        }

        std.debug.assert(self.stats.is_valid());
        std.debug.assert(self.is_valid());
    }

    fn record_event(self: *Simulator, evt: Event) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(evt.is_valid());

        if (self.events.items.len >= event_capacity) {
            return;
        }

        std.debug.assert(self.events.items.len < event_capacity);

        const recorded = RecordedEvent{
            .tick = self.current_tick,
            .event = evt,
            .callback_time_ns = self.health_monitor.last_callback_ns,
            .hook_state = self.hook_state,
            .health = self.health,
        };

        std.debug.assert(recorded.is_valid());

        self.events.append(self.allocator, recorded) catch {};
    }
};

const testing = std.testing;

test "Simulator init" {
    const config = Config{
        .seed = 42,
        .max_ticks = 1000,
    };

    std.debug.assert(config.is_valid());

    var sim = Simulator.init(testing.allocator, config);
    defer sim.deinit();

    try testing.expectEqual(State.installed, sim.hook_state);
    try testing.expectEqual(Health.healthy, sim.health);
    try testing.expect(sim.is_valid());
}

test "Simulator run basic" {
    const config = Config{
        .seed = 42,
        .max_ticks = 100,
        .timeout_probability = 0,
        .slow_callback_probability = 0,
    };

    std.debug.assert(config.is_valid());

    var sim = Simulator.init(testing.allocator, config);
    defer sim.deinit();

    sim.run();

    try testing.expectEqual(@as(u64, 100), sim.current_tick);
    try testing.expect(sim.stats.total_callbacks > 0);
    try testing.expect(sim.stats.is_valid());
    try testing.expect(sim.is_valid());
}

test "HealthMonitor degraded" {
    var monitor = HealthMonitor.init();

    var i: u8 = 0;

    while (i < 5) : (i += 1) {
        std.debug.assert(i < 5);

        monitor.record_callback(warning_threshold_ns + 1000);
    }

    std.debug.assert(i == 5);

    try testing.expectEqual(Health.degraded, monitor.get_health());
    try testing.expect(monitor.is_valid());
}

test "HealthMonitor healthy after reset" {
    var monitor = HealthMonitor.init();
    monitor.consecutive_slow = 10;

    monitor.reset();

    try testing.expectEqual(Health.healthy, monitor.get_health());
    try testing.expect(monitor.is_valid());
}

test "Config is_valid" {
    const valid_config = Config{
        .seed = 42,
        .max_ticks = 1000,
    };

    const invalid_config = Config{
        .seed = 42,
        .timeout_probability = 101,
    };

    try testing.expect(valid_config.is_valid());
    try testing.expect(!invalid_config.is_valid());
}

test "Stats is_valid" {
    const valid_stats = Stats{
        .total_callbacks = 100,
        .callbacks_under_threshold = 50,
        .callbacks_over_threshold = 50,
        .reinstall_attempts = 10,
        .reinstall_successes = 5,
        .reinstall_failures = 5,
    };

    const invalid_stats = Stats{
        .total_callbacks = 100,
        .callbacks_under_threshold = 60,
        .callbacks_over_threshold = 60,
    };

    try testing.expect(valid_stats.is_valid());
    try testing.expect(!invalid_stats.is_valid());
}
