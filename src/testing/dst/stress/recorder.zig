const std = @import("std");
const assert = std.debug.assert;

const common = @import("common");
const simulator = @import("simulator.zig");

const StressVOPR = simulator.StressVOPR;
const StressEvent = simulator.StressEvent;
const StressEventKind = simulator.StressEventKind;
const StressState = simulator.StressState;
const TimingConfig = simulator.TimingConfig;

pub const Format = common.Format;

const max_recording_size: usize = 10 * 1024 * 1024;
const max_events: usize = 100_000;
const max_seed: u64 = std.math.maxInt(u64);
const max_ticks: u64 = 10_000_000;

pub const HeaderExtra = extern struct {
    reserved: [32]u8 = [_]u8{0} ** 32,
};

pub const Header = common.Header("STRS", HeaderExtra);

const JsonStats = struct {
    inputs_queued: u64,
    inputs_processed: u64,
    inputs_dropped: u64,
    timing_misses: u64,
    bursts_generated: u64,
    bindings_triggered: u64,
    max_queue_depth: u32,
    total_delay_ns: u64,
    stress_ticks: u64,
};

const JsonFinalState = struct {
    coalesced_inputs: u64,
    expired_inputs: u64,
    modifier_races: u64,
    timing_misses: u64 = 0,
    hook_deaths: u64 = 0,
    hook_restores: u64 = 0,
};

const JsonTiming = struct {
    processing_delay_min_ns: u64,
    processing_delay_max_ns: u64,
    slow_callback_probability: u32,
    stall_probability: u32,
    cpu_spike_probability: u32,
    hook_timeout_probability: u32,
    slow_callback_min_ns: u64 = 0,
    slow_callback_max_ns: u64 = 0,
    stall_min_ticks: u32 = 0,
    stall_max_ticks: u32 = 0,
};

const JsonEvent = struct {
    tick: u64,
    kind: []const u8,
    delay_ns: u64 = 0,
    queue_depth: u32 = 0,
    key: u16 = 0,
    coalesced_count: u32 = 0,
    duration: u64 = 0,
    cpu_load: u32 = 0,
    key1: u16 = 0,
    key2: u16 = 0,
    repeat_count: u32 = 0,
};

const JsonRecording = struct {
    type: []const u8,
    seed: u64,
    max_ticks: u64,
    total_ticks: u64,
    stats: []const JsonStats,
    final_state: []const JsonFinalState,
    timing: []const JsonTiming,
    events: []const JsonEvent,
};

pub const Recorder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),

    pub fn init(allocator: std.mem.Allocator) Recorder {
        return .{
            .allocator = allocator,
            .buffer = .{},
        };
    }

    pub fn deinit(self: *Recorder) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn record_stress_vopr(self: *Recorder, vopr: *const StressVOPR) !void {
        assert(vopr.config.max_ticks > 0);
        assert(vopr.config.max_ticks <= max_ticks);
        assert(vopr.stats.total_ticks <= vopr.config.max_ticks);

        self.buffer.clearRetainingCapacity();

        const events = try self.build_events(vopr.get_stress_events());
        defer self.allocator.free(events);

        const json_stats = [_]JsonStats{.{
            .inputs_queued = vopr.stats.inputs_queued,
            .inputs_processed = vopr.stats.inputs_processed,
            .inputs_dropped = vopr.stats.inputs_dropped,
            .timing_misses = vopr.stats.timing_misses,
            .bursts_generated = vopr.stats.bursts_generated,
            .bindings_triggered = vopr.stats.bindings_triggered,
            .max_queue_depth = vopr.stats.max_queue_depth,
            .total_delay_ns = vopr.stats.total_delay_ns,
            .stress_ticks = vopr.stats.stress_ticks,
        }};

        const state = vopr.get_stress_state();
        const json_state = [_]JsonFinalState{.{
            .coalesced_inputs = state.coalesced_inputs,
            .expired_inputs = state.expired_inputs,
            .modifier_races = state.modifier_races,
            .timing_misses = state.timing_misses,
            .hook_deaths = state.hook_deaths,
            .hook_restores = state.hook_restores,
        }};

        const timing = vopr.config.timing;
        const json_timing = [_]JsonTiming{.{
            .processing_delay_min_ns = timing.processing_delay_min_ns,
            .processing_delay_max_ns = timing.processing_delay_max_ns,
            .slow_callback_probability = timing.slow_callback_probability,
            .stall_probability = timing.stall_probability,
            .cpu_spike_probability = timing.cpu_spike_probability,
            .hook_timeout_probability = timing.hook_timeout_probability,
        }};

        const recording = JsonRecording{
            .type = "stress",
            .seed = vopr.config.seed,
            .max_ticks = vopr.config.max_ticks,
            .total_ticks = vopr.stats.total_ticks,
            .stats = &json_stats,
            .final_state = &json_state,
            .timing = &json_timing,
            .events = events,
        };

        const json_str = try std.json.Stringify.valueAlloc(self.allocator, recording, .{ .whitespace = .indent_2 });
        defer self.allocator.free(json_str);

        try self.buffer.appendSlice(self.allocator, json_str);

        assert(self.buffer.items.len > 0);
    }

    fn build_events(self: *Recorder, stress_events: []const StressEvent) ![]JsonEvent {
        const len = @min(stress_events.len, max_events);

        var events = try self.allocator.alloc(JsonEvent, len);
        errdefer self.allocator.free(events);

        for (stress_events[0..len], 0..) |event, i| {
            events[i] = .{
                .tick = event.tick,
                .kind = @tagName(event.kind),
            };

            switch (event.kind) {
                .processing_delay => {
                    events[i].delay_ns = event.data.delay_ns;
                },
                .queue_backpressure => {
                    events[i].queue_depth = event.data.queue_depth;
                },
                .timing_window_miss => {
                    events[i].key = event.data.window_miss.key;
                },
                .input_coalesced => {
                    events[i].coalesced_count = event.data.coalesced_count;
                },
                .system_stall, .hook_lost => {
                    events[i].duration = event.data.stall_duration;
                },
                .cpu_spike => {
                    events[i].cpu_load = event.data.cpu_load;
                },
                .modifier_race => {
                    events[i].key1 = event.data.race_keys[0];
                    events[i].key2 = event.data.race_keys[1];
                },
                .rapid_repeat => {
                    events[i].repeat_count = event.data.repeat_count;
                },
                else => {},
            }
        }

        return events;
    }

    pub fn get_data(self: *const Recorder) []const u8 {
        return self.buffer.items;
    }

    pub fn write_to_file(self: *const Recorder, path: []const u8) !void {
        assert(path.len > 0);
        assert(self.buffer.items.len > 0);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(self.buffer.items);
    }
};

pub const Recording = struct {
    allocator: std.mem.Allocator,
    config: simulator.StressVOPRConfig,
    events: []StressEvent,
    stats: StressVOPR.StressStats,
    final_state: StressState,

    pub fn deinit(self: *Recording) void {
        if (self.events.len > 0) {
            self.allocator.free(self.events);
        }
    }

    pub fn load_from_file(allocator: std.mem.Allocator, path: []const u8) !Recording {
        assert(path.len > 0);

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, max_recording_size);
        defer allocator.free(content);

        assert(content.len > 0);
        assert(content.len <= max_recording_size);

        return try parse(allocator, content);
    }

    pub fn parse(allocator: std.mem.Allocator, content: []const u8) !Recording {
        assert(content.len > 0);
        assert(content.len <= max_recording_size);

        const parsed = try std.json.parseFromSlice(JsonRecording, allocator, content, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        const json = parsed.value;

        assert(json.seed <= max_seed);
        assert(json.max_ticks > 0);
        assert(json.max_ticks <= max_ticks);
        assert(json.stats.len > 0);
        assert(json.final_state.len > 0);

        const events = try parse_events(allocator, json.events);
        errdefer allocator.free(events);

        const stats = StressVOPR.StressStats{
            .inputs_queued = json.stats[0].inputs_queued,
            .inputs_processed = json.stats[0].inputs_processed,
            .inputs_dropped = json.stats[0].inputs_dropped,
            .timing_misses = json.stats[0].timing_misses,
            .bursts_generated = json.stats[0].bursts_generated,
            .bindings_triggered = json.stats[0].bindings_triggered,
            .max_queue_depth = json.stats[0].max_queue_depth,
            .total_delay_ns = json.stats[0].total_delay_ns,
            .stress_ticks = json.stats[0].stress_ticks,
        };

        const final_state = StressState{
            .coalesced_inputs = json.final_state[0].coalesced_inputs,
            .expired_inputs = json.final_state[0].expired_inputs,
            .modifier_races = json.final_state[0].modifier_races,
        };

        assert(stats.inputs_processed <= stats.inputs_queued);

        return .{
            .allocator = allocator,
            .config = .{
                .seed = json.seed,
                .max_ticks = json.max_ticks,
            },
            .events = events,
            .stats = stats,
            .final_state = final_state,
        };
    }

    fn parse_events(allocator: std.mem.Allocator, json_events: []const JsonEvent) ![]StressEvent {
        const len = @min(json_events.len, max_events);

        var events = try allocator.alloc(StressEvent, len);
        errdefer allocator.free(events);

        for (json_events[0..len], 0..) |evt, i| {
            events[i] = .{
                .tick = evt.tick,
                .kind = std.meta.stringToEnum(StressEventKind, evt.kind) orelse .processing_delay,
                .data = .{ .none = {} },
            };
        }

        return events;
    }
};
