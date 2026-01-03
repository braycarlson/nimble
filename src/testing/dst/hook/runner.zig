const std = @import("std");

const common = @import("common");
const simulator = @import("simulator.zig");
const recorder_mod = @import("recorder.zig");
const replay_mod = @import("replay.zig");

const Simulator = simulator.Simulator;
const Config = simulator.Config;
const Recorder = recorder_mod.Recorder;
const Recording = recorder_mod.Recording;
const Replayer = replay_mod.Replayer;

pub const iteration_max: u64 = 0xFFFFFFFF;
pub const default_max_ticks: u64 = 50000;
pub const default_timeout_probability: u8 = 2;
pub const default_slow_callback_probability: u8 = 5;

pub const RunnerConfig = struct {
    seed: ?u64 = null,
    max_ticks: u64 = default_max_ticks,
    output_path: ?[]const u8 = null,
    replay_path: ?[]const u8 = null,
    verbose: bool = false,
    timeout_probability: u8 = default_timeout_probability,
    slow_callback_probability: u8 = default_slow_callback_probability,

    pub fn is_valid(self: *const RunnerConfig) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_ticks = self.max_ticks > 0;
        const valid_timeout = self.timeout_probability <= 100;
        const valid_slow = self.slow_callback_probability <= 100;
        const result = valid_ticks and valid_timeout and valid_slow;

        return result;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = try parse_args(allocator);
    defer {
        if (config.output_path) |p| allocator.free(p);
        if (config.replay_path) |p| allocator.free(p);
    }

    std.debug.assert(config.is_valid());

    if (config.replay_path) |path| {
        std.debug.assert(path.len > 0);
        try run_replay(allocator, path, config.verbose);
    } else {
        try run_simulator(allocator, config);
    }
}

fn parse_args(allocator: std.mem.Allocator) !RunnerConfig {
    var config = RunnerConfig{};
    var parser = try common.ArgParser.init(allocator);
    defer parser.deinit();

    var iteration: u32 = 0;

    while (parser.next()) |arg| {
        std.debug.assert(iteration < iteration_max);

        if (std.mem.startsWith(u8, arg, "--seed=")) {
            config.seed = common.parse_int_arg(u64, arg, "--seed=", 0);
            if (config.seed == 0) config.seed = null;
        } else if (std.mem.startsWith(u8, arg, "--ticks=")) {
            config.max_ticks = common.parse_int_arg(u64, arg, "--ticks=", default_max_ticks);
        } else if (std.mem.startsWith(u8, arg, "--output=")) {
            config.output_path = common.parse_string_arg(allocator, arg, "--output=");
        } else if (std.mem.startsWith(u8, arg, "--replay=")) {
            config.replay_path = common.parse_string_arg(allocator, arg, "--replay=");
        } else if (std.mem.startsWith(u8, arg, "--timeout=")) {
            config.timeout_probability = common.parse_int_arg(u8, arg, "--timeout=", default_timeout_probability);
        } else if (std.mem.startsWith(u8, arg, "--slow=")) {
            config.slow_callback_probability = common.parse_int_arg(u8, arg, "--slow=", default_slow_callback_probability);
        } else if (common.matches_flag(arg, "-v", "--verbose")) {
            config.verbose = true;
        }

        iteration += 1;
    }

    std.debug.assert(config.is_valid());

    return config;
}

fn run_simulator(allocator: std.mem.Allocator, config: RunnerConfig) !void {
    std.debug.assert(config.is_valid());

    const seed = config.seed orelse common.random_seed();

    common.print_header("Hook Simulator Starting");
    common.print_field("Seed", seed);
    common.print_field("Max Ticks", config.max_ticks);
    common.print_field("Timeout Probability", config.timeout_probability);
    common.print_field("Slow Callback Probability", config.slow_callback_probability);

    const sim_config = Config{
        .seed = seed,
        .max_ticks = config.max_ticks,
        .timeout_probability = config.timeout_probability,
        .slow_callback_probability = config.slow_callback_probability,
    };

    std.debug.assert(sim_config.is_valid());

    var sim = Simulator.init(allocator, sim_config);
    defer sim.deinit();

    std.debug.assert(sim.is_valid());

    const start_time = std.time.milliTimestamp();
    sim.run();
    const end_time = std.time.milliTimestamp();

    std.debug.assert(sim.is_valid());

    const stats = sim.get_stats();

    std.debug.assert(stats.is_valid());

    common.print_section("Hook Simulator Completed");
    common.print_duration(start_time, end_time);

    print_callback_statistics(&stats);
    print_hook_statistics(&stats);
    print_system_events(&stats);
    print_timing_statistics(&stats);

    if (config.output_path) |path| {
        std.debug.assert(path.len > 0);
        try write_recording(allocator, &sim, path);
    }

    if (stats.inputs_lost > 0) {
        common.print_warning("{d} inputs lost during simulation!", .{stats.inputs_lost});
    }
}

fn print_callback_statistics(stats: *const simulator.Stats) void {
    std.debug.assert(@intFromPtr(stats) != 0);
    std.debug.assert(stats.is_valid());

    common.print_section("Callback Statistics");
    common.print_field("Total Callbacks", stats.total_callbacks);
    common.print_field("Under Threshold", stats.callbacks_under_threshold);
    common.print_field("Over Threshold", stats.callbacks_over_threshold);
    common.print_field("Timeouts Triggered", stats.timeouts_triggered);
}

fn print_hook_statistics(stats: *const simulator.Stats) void {
    std.debug.assert(@intFromPtr(stats) != 0);
    std.debug.assert(stats.is_valid());

    common.print_section("Hook Statistics");
    common.print_field("Silent Unhooks", stats.silent_unhooks);
    common.print_field("Reinstall Attempts", stats.reinstall_attempts);
    common.print_field("Reinstall Successes", stats.reinstall_successes);
    common.print_field("Reinstall Failures", stats.reinstall_failures);
    common.print_field("Inputs Lost", stats.inputs_lost);
}

fn print_system_events(stats: *const simulator.Stats) void {
    std.debug.assert(@intFromPtr(stats) != 0);
    std.debug.assert(stats.is_valid());

    common.print_section("System Events");
    common.print_field("Desktop Switches", stats.desktop_switches);
    common.print_field("Session Locks", stats.session_locks);
    common.print_field("UAC Prompts", stats.uac_prompts);
}

fn print_timing_statistics(stats: *const simulator.Stats) void {
    std.debug.assert(@intFromPtr(stats) != 0);
    std.debug.assert(stats.is_valid());

    common.print_section("Timing");
    common.print_field_fmt("Max Callback", "{d}ms", .{stats.max_callback_ns / 1_000_000});
    common.print_field_fmt("Avg Callback", "{d}us", .{stats.avg_callback_ns() / 1000});
    common.print_field("Max Consecutive Slow", stats.max_consecutive_slow);
}

fn write_recording(allocator: std.mem.Allocator, sim: *const Simulator, path: []const u8) !void {
    std.debug.assert(@intFromPtr(sim) != 0);
    std.debug.assert(sim.is_valid());
    std.debug.assert(path.len > 0);

    common.print_section("Recording");
    common.print_field("Path", path);

    var recorder = Recorder.init(allocator);
    defer recorder.deinit();

    std.debug.assert(recorder.is_valid());

    try recorder.record(sim);
    try recorder.write_to_file(path);

    common.print_field("Size", recorder.get_data().len);
    common.print_field("Events", sim.get_events().len);
}

fn run_replay(allocator: std.mem.Allocator, path: []const u8, verbose: bool) !void {
    std.debug.assert(path.len > 0);

    common.print_header("Loading Recording");
    common.print_field("Path", path);

    var recording = try Recording.load_from_file(allocator, path);
    defer recording.deinit();

    std.debug.assert(recording.is_valid());

    common.print_field("Seed", recording.config.seed);
    common.print_field("Max Ticks", recording.config.max_ticks);
    common.print_field("Events", recording.events.len);

    var replayer = Replayer.init();
    defer replayer.deinit();

    std.debug.assert(replayer.is_valid());

    replayer.load_recording(&recording);

    std.debug.assert(replayer.is_valid());

    common.print_section("Replaying...");

    var events_replayed: u64 = 0;
    var iteration: u64 = 0;

    while (replayer.step() and iteration < iteration_max) : (iteration += 1) {
        std.debug.assert(iteration < iteration_max);

        events_replayed += 1;

        if (verbose) {
            const state = replayer.get_state();

            std.debug.assert(state.is_valid());

            std.debug.print("  [{d}] state={s} health={s}\n", .{
                state.tick,
                @tagName(state.hook_state),
                @tagName(state.health),
            });
        }
    }

    std.debug.assert(iteration < iteration_max);
    std.debug.assert(replayer.is_valid());

    common.print_field("Final Tick", replayer.current_tick);
    common.print_field("Events Replayed", events_replayed);
}
