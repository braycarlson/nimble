const std = @import("std");

const common = @import("common");
const state_mod = @import("state.zig");
const simulator = @import("simulator.zig");
const recorder_mod = @import("recorder.zig");
const replay_mod = @import("replay.zig");

const VOPR = simulator.VOPR;
const VOPRConfig = simulator.VOPRConfig;
const VOPRResult = simulator.VOPRResult;
const TestProfile = simulator.TestProfile;
const Recorder = recorder_mod.Recorder;
const Format = recorder_mod.Format;
const Recording = recorder_mod.Recording;
const Replayer = replay_mod.Replayer;
const Event = state_mod.Event;
const Stats = state_mod.Stats;

const InputStats = common.schema.StatsPrinter(@embedFile("schema.json"));

pub const iteration_max: u32 = 256;

pub const RunnerConfig = struct {
    seed: ?u64 = null,
    max_ticks: u64 = 10000,
    fault_probability: u8 = 5,
    output_path: ?[]const u8 = null,
    output_format: Format = .json,
    verbose: bool = false,
    replay_path: ?[]const u8 = null,
    test_profile: TestProfile = .realistic,
    max_keys: u8 = 4,
    max_modifiers: u8 = 2,
    prevent_duplicate_mods: bool = true,

    pub fn is_valid(self: *const RunnerConfig) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_ticks = self.max_ticks > 0;
        const valid_fault = self.fault_probability <= 100;
        const valid_keys = self.max_keys <= 16;
        const valid_mods = self.max_modifiers <= 4;
        const result = valid_ticks and valid_fault and valid_keys and valid_mods;

        return result;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();
    const config = try parse_args(allocator);

    std.debug.assert(config.is_valid());

    defer free_config_strings(allocator, &config);

    if (config.replay_path) |path| {
        std.debug.assert(path.len > 0);

        try run_replay(allocator, path, config.verbose);
    } else {
        try run_vopr(allocator, config);
    }
}

fn free_config_strings(allocator: std.mem.Allocator, config: *const RunnerConfig) void {
    std.debug.assert(@intFromPtr(&allocator) != 0);
    std.debug.assert(config.is_valid());

    if (config.output_path) |p| {
        allocator.free(p);
    }

    if (config.replay_path) |p| {
        allocator.free(p);
    }
}

fn parse_args(allocator: std.mem.Allocator) !RunnerConfig {
    std.debug.assert(@intFromPtr(&allocator) != 0);

    var config = RunnerConfig{};
    var parser = try common.ArgParser.init(allocator);
    defer parser.deinit();

    var iterations: u32 = 0;

    while (parser.next()) |arg| {
        std.debug.assert(iterations < iteration_max);

        parse_single_arg(&config, allocator, arg);

        iterations += 1;

        if (iterations >= iteration_max) {
            break;
        }
    }

    std.debug.assert(iterations <= iteration_max);
    std.debug.assert(config.is_valid());

    return config;
}

fn parse_single_arg(config: *RunnerConfig, allocator: std.mem.Allocator, arg: []const u8) void {
    std.debug.assert(@intFromPtr(config) != 0);
    std.debug.assert(@intFromPtr(&allocator) != 0);
    std.debug.assert(arg.len > 0);

    if (std.mem.startsWith(u8, arg, "--seed=")) {
        const seed = common.parse_int_arg(u64, arg, "--seed=", 0);
        config.seed = if (seed == 0) null else seed;
        return;
    }

    if (std.mem.startsWith(u8, arg, "--ticks=")) {
        config.max_ticks = common.parse_int_arg(u64, arg, "--ticks=", 10000);
        return;
    }

    if (std.mem.startsWith(u8, arg, "--faults=")) {
        config.fault_probability = common.parse_int_arg(u8, arg, "--faults=", 5);
        return;
    }

    if (std.mem.startsWith(u8, arg, "--output=")) {
        config.output_path = common.parse_string_arg(allocator, arg, "--output=");
        return;
    }

    if (std.mem.eql(u8, arg, "--json")) {
        config.output_format = .json;
        return;
    }

    if (std.mem.eql(u8, arg, "--binary")) {
        config.output_format = .binary;
        return;
    }

    if (common.matches_flag(arg, "-v", "--verbose")) {
        config.verbose = true;
        return;
    }

    if (std.mem.startsWith(u8, arg, "--replay=")) {
        config.replay_path = common.parse_string_arg(allocator, arg, "--replay=");
        return;
    }

    if (std.mem.startsWith(u8, arg, "--profile=")) {
        config.test_profile = parse_profile(arg[10..]);
        return;
    }

    if (std.mem.startsWith(u8, arg, "--max-keys=")) {
        config.max_keys = common.parse_int_arg(u8, arg, "--max-keys=", 4);
        return;
    }

    if (std.mem.startsWith(u8, arg, "--max-mods=")) {
        config.max_modifiers = common.parse_int_arg(u8, arg, "--max-mods=", 2);
        return;
    }
}

fn parse_profile(profile_str: []const u8) TestProfile {
    if (std.mem.eql(u8, profile_str, "realistic")) {
        return .realistic;
    }

    if (std.mem.eql(u8, profile_str, "stress")) {
        return .stress;
    }

    if (std.mem.eql(u8, profile_str, "mixed")) {
        return .mixed;
    }

    return .realistic;
}

fn run_vopr(allocator: std.mem.Allocator, config: RunnerConfig) !void {
    std.debug.assert(@intFromPtr(&allocator) != 0);
    std.debug.assert(config.is_valid());

    const seed = config.seed orelse common.random_seed();

    std.debug.assert(seed > 0 or seed == 0);

    print_vopr_header(&config, seed);

    const vopr_config = build_vopr_config(&config, seed);

    std.debug.assert(vopr_config.is_valid());

    var vopr = VOPR.init(vopr_config);
    defer vopr.deinit();

    const start_time = std.time.milliTimestamp();
    const result = vopr.run();
    const end_time = std.time.milliTimestamp();

    std.debug.assert(vopr.is_valid());

    print_vopr_results(&vopr, result, start_time, end_time);

    if (config.output_path) |path| {
        std.debug.assert(path.len > 0);

        try write_recording(allocator, &vopr, path, config.output_format);
    }

    if (result == .invariant_failure) {
        common.print_warning("Invariant Violation Detected!", .{});
        common.print_reproduce_command(seed, @tagName(config.test_profile));
    }
}

fn print_vopr_header(config: *const RunnerConfig, seed: u64) void {
    std.debug.assert(config.is_valid());

    common.print_header("Input VOPR Starting");
    common.print_field("Seed", seed);
    common.print_field("Max Ticks", config.max_ticks);
    common.print_field("Fault Probability", config.fault_probability);
    common.print_field("Test Profile", @tagName(config.test_profile));
}

fn build_vopr_config(config: *const RunnerConfig, seed: u64) VOPRConfig {
    std.debug.assert(config.is_valid());

    const result = VOPRConfig{
        .seed = seed,
        .max_ticks = config.max_ticks,
        .fault_probability = config.fault_probability,
        .test_profile = config.test_profile,
        .realistic = .{
            .max_simultaneous_keys = config.max_keys,
            .max_simultaneous_modifiers = config.max_modifiers,
            .prevent_duplicate_modifiers = config.prevent_duplicate_mods,
        },
    };

    return result;
}

fn print_vopr_results(vopr: *const VOPR, result: VOPRResult, start_time: i64, end_time: i64) void {
    std.debug.assert(vopr.is_valid());

    common.print_section("Input VOPR Completed");
    common.print_field("Result", @tagName(result));
    common.print_duration(start_time, end_time);

    InputStats.print_section("Statistics", stats_to_array(&vopr.stats));

    common.print_section("Realistic State");
    common.print_field("Keys Currently Held", vopr.held_keys_count);
    common.print_field("Modifiers Currently Held", vopr.held_modifiers_count);
}

fn write_recording(allocator: std.mem.Allocator, vopr: *const VOPR, path: []const u8, format: Format) !void {
    std.debug.assert(@intFromPtr(&allocator) != 0);
    std.debug.assert(vopr.is_valid());
    std.debug.assert(path.len > 0);

    common.print_section("Recording");
    common.print_field("Path", path);

    var recorder = Recorder.init(allocator, format);
    defer recorder.deinit();

    std.debug.assert(recorder.is_valid());

    try recorder.record_vopr(vopr);
    try recorder.write_to_file(path);

    common.print_field("Format", @tagName(format));
    common.print_field("Size", recorder.get_data().len);
}

fn stats_to_array(stats: *const Stats) [InputStats.field_count]u64 {
    std.debug.assert(stats.is_valid());

    const result = .{
        stats.key_events,
        stats.active_bindings(),
        stats.blocks(),
        stats.allows(),
        stats.faults_injected,
        stats.invariant_violations,
    };

    return result;
}

fn run_replay(allocator: std.mem.Allocator, path: []const u8, verbose: bool) !void {
    std.debug.assert(@intFromPtr(&allocator) != 0);
    std.debug.assert(path.len > 0);

    common.print_header("Loading Recording");
    common.print_field("Path", path);

    var recording = try Recording.load_from_file(allocator, path);
    defer recording.deinit();

    std.debug.assert(recording.is_valid());

    print_recording_info(&recording);

    var replayer = Replayer.init();
    defer replayer.deinit();

    std.debug.assert(replayer.is_valid());

    replayer.load_recording(&recording);

    if (verbose) {
        replayer.set_callback(replay_callback, null);
    }

    common.print_section("Replaying...");
    replayer.run_to_completion();

    print_replay_results(&replayer);
}

fn print_recording_info(recording: *const Recording) void {
    std.debug.assert(recording.is_valid());

    common.print_field("Seed", recording.header.seed);
    common.print_field("Total Ticks", recording.header.total_ticks);
    common.print_field("Events", recording.events.len);
    common.print_field("Snapshots", recording.snapshots.len);
    common.print_field("Replay Entries", recording.replay.len);
}

fn print_replay_results(replayer: *const Replayer) void {
    std.debug.assert(replayer.is_valid());

    common.print_field("Final Tick", replayer.current_tick);
    common.print_field("State", @tagName(replayer.state));

    if (replayer.divergence_tick) |tick| {
        common.print_warning("Divergence at tick {d}!", .{tick});
        std.process.exit(1);
    } else {
        common.print_field("Verification", "PASSED");
    }
}

fn replay_callback(replayer: *Replayer, tick: u64, evt: ?*const Event) void {
    std.debug.assert(replayer.is_valid());

    const e = evt orelse return;

    std.debug.assert(e.is_valid());

    std.debug.print("  [{d}] {s}", .{ tick, @tagName(e.kind) });

    if (e.keycode != 0) {
        std.debug.print(" keycode={d}", .{e.keycode});
    }

    if (e.binding_id != 0) {
        std.debug.print(" binding={d}", .{e.binding_id});
    }

    std.debug.print("\n", .{});
}
