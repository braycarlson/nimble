const std = @import("std");

const simulator = @import("simulator.zig");

const Simulator = simulator.Simulator;
const Config = simulator.Config;
const Stats = simulator.Stats;
const RecordedEvent = simulator.RecordedEvent;
const HookEvent = simulator.Event;

pub const iteration_max: u32 = 0xFFFFFFFF;
pub const file_size_max: u32 = 100 * 1024 * 1024;

const JsonConfig = struct {
    seed: u64,
    max_ticks: u64,
    timeout_probability: u8,
    slow_callback_probability: u8,
};

const JsonStats = struct {
    total_callbacks: u64,
    callbacks_under_threshold: u64,
    callbacks_over_threshold: u64,
    timeouts_triggered: u64,
    silent_unhooks: u64,
    reinstall_attempts: u64,
    reinstall_successes: u64,
    reinstall_failures: u64,
    inputs_lost: u64,
    max_callback_ns: u64,
    desktop_switches: u64,
    session_locks: u64,
    uac_prompts: u64,
    max_consecutive_slow: u64,
};

const JsonEvent = struct {
    tick: u64,
    event: []const u8,
    callback_time_ns: u64,
    hook_state: []const u8,
    health: []const u8,
};

const JsonRecording = struct {
    type: []const u8,
    seed: u64,
    max_ticks: u64,
    config: []const JsonConfig,
    stats: []const JsonStats,
    events: []const JsonEvent,
};

pub const Recorder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator) Recorder {
        const result = Recorder{
            .allocator = allocator,
            .buffer = .{},
        };

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn is_valid(self: *const Recorder) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        return true;
    }

    pub fn deinit(self: *Recorder) void {
        std.debug.assert(self.is_valid());

        self.buffer.deinit(self.allocator);
    }

    pub fn record(self: *Recorder, sim: *const Simulator) !void {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(sim) != 0);
        std.debug.assert(sim.is_valid());

        self.buffer.clearRetainingCapacity();

        const events = try self.build_events(sim);
        defer self.allocator.free(events);

        const json_config = [_]JsonConfig{.{
            .seed = sim.config.seed,
            .max_ticks = sim.config.max_ticks,
            .timeout_probability = sim.config.timeout_probability,
            .slow_callback_probability = sim.config.slow_callback_probability,
        }};

        const json_stats = [_]JsonStats{.{
            .total_callbacks = sim.stats.total_callbacks,
            .callbacks_under_threshold = sim.stats.callbacks_under_threshold,
            .callbacks_over_threshold = sim.stats.callbacks_over_threshold,
            .timeouts_triggered = sim.stats.timeouts_triggered,
            .silent_unhooks = sim.stats.silent_unhooks,
            .reinstall_attempts = sim.stats.reinstall_attempts,
            .reinstall_successes = sim.stats.reinstall_successes,
            .reinstall_failures = sim.stats.reinstall_failures,
            .inputs_lost = sim.stats.inputs_lost,
            .max_callback_ns = sim.stats.max_callback_ns,
            .desktop_switches = sim.stats.desktop_switches,
            .session_locks = sim.stats.session_locks,
            .uac_prompts = sim.stats.uac_prompts,
            .max_consecutive_slow = sim.stats.max_consecutive_slow,
        }};

        const recording = JsonRecording{
            .type = "hook",
            .seed = sim.config.seed,
            .max_ticks = sim.config.max_ticks,
            .config = &json_config,
            .stats = &json_stats,
            .events = events,
        };

        const json_str = try std.json.Stringify.valueAlloc(self.allocator, recording, .{ .whitespace = .indent_2 });
        defer self.allocator.free(json_str);

        try self.buffer.appendSlice(self.allocator, json_str);

        std.debug.assert(self.is_valid());
    }

    fn build_events(self: *Recorder, sim: *const Simulator) ![]JsonEvent {
        std.debug.assert(self.is_valid());
        std.debug.assert(sim.is_valid());

        const len = @min(sim.events.items.len, iteration_max);
        var events = try self.allocator.alloc(JsonEvent, len);
        errdefer self.allocator.free(events);

        for (sim.events.items[0..len], 0..) |evt, i| {
            std.debug.assert(evt.is_valid());

            events[i] = .{
                .tick = evt.tick,
                .event = @tagName(evt.event),
                .callback_time_ns = evt.callback_time_ns,
                .hook_state = @tagName(evt.hook_state),
                .health = @tagName(evt.health),
            };
        }

        return events;
    }

    pub fn get_data(self: *const Recorder) []const u8 {
        std.debug.assert(self.is_valid());

        const result = self.buffer.items;

        std.debug.assert(result.len <= file_size_max);

        return result;
    }

    pub fn write_to_file(self: *const Recorder, path: []const u8) !void {
        std.debug.assert(self.is_valid());
        std.debug.assert(path.len > 0);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(self.buffer.items);
    }
};

pub const Recording = struct {
    allocator: std.mem.Allocator,
    config: Config,
    stats: Stats,
    events: []RecordedEvent,

    pub fn is_valid(self: *const Recording) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_config = self.config.is_valid();
        const valid_stats = self.stats.is_valid();
        const result = valid_config and valid_stats;

        return result;
    }

    pub fn deinit(self: *Recording) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(self.is_valid());

        self.allocator.free(self.events);
    }

    pub fn load_from_file(allocator: std.mem.Allocator, path: []const u8) !Recording {
        std.debug.assert(path.len > 0);

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, file_size_max);
        defer allocator.free(content);

        std.debug.assert(content.len > 0);
        std.debug.assert(content.len <= file_size_max);

        const result = try parse(allocator, content);

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn parse(allocator: std.mem.Allocator, content: []const u8) !Recording {
        std.debug.assert(content.len > 0);
        std.debug.assert(content.len <= file_size_max);

        const parsed = try std.json.parseFromSlice(JsonRecording, allocator, content, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        const json = parsed.value;

        std.debug.assert(json.config.len > 0);
        std.debug.assert(json.stats.len > 0);

        const config = Config{
            .seed = json.config[0].seed,
            .max_ticks = json.config[0].max_ticks,
            .timeout_probability = json.config[0].timeout_probability,
            .slow_callback_probability = json.config[0].slow_callback_probability,
        };

        const stats = Stats{
            .total_callbacks = json.stats[0].total_callbacks,
            .callbacks_under_threshold = json.stats[0].callbacks_under_threshold,
            .callbacks_over_threshold = json.stats[0].callbacks_over_threshold,
            .timeouts_triggered = json.stats[0].timeouts_triggered,
            .silent_unhooks = json.stats[0].silent_unhooks,
            .reinstall_attempts = json.stats[0].reinstall_attempts,
            .reinstall_successes = json.stats[0].reinstall_successes,
            .reinstall_failures = json.stats[0].reinstall_failures,
            .inputs_lost = json.stats[0].inputs_lost,
            .max_callback_ns = json.stats[0].max_callback_ns,
            .desktop_switches = json.stats[0].desktop_switches,
            .session_locks = json.stats[0].session_locks,
            .uac_prompts = json.stats[0].uac_prompts,
            .max_consecutive_slow = json.stats[0].max_consecutive_slow,
        };

        const events = try parse_events(allocator, json.events);

        const result = Recording{
            .allocator = allocator,
            .config = config,
            .stats = stats,
            .events = events,
        };

        std.debug.assert(result.is_valid());

        return result;
    }

    fn parse_events(allocator: std.mem.Allocator, json_events: []const JsonEvent) ![]RecordedEvent {
        var events = try allocator.alloc(RecordedEvent, json_events.len);
        errdefer allocator.free(events);

        for (json_events, 0..) |evt, i| {
            events[i] = RecordedEvent{
                .tick = evt.tick,
                .event = std.meta.stringToEnum(HookEvent, evt.event) orelse .installed,
                .callback_time_ns = evt.callback_time_ns,
                .hook_state = std.meta.stringToEnum(simulator.State, evt.hook_state) orelse .installed,
                .health = std.meta.stringToEnum(simulator.Health, evt.health) orelse .healthy,
            };

            std.debug.assert(events[i].is_valid());
        }

        return events;
    }
};
