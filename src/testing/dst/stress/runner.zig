const std = @import("std");
const common = @import("common");

const dst = @import("dst");
const StressVOPR = dst.stress.StressVOPR;
const StressVOPRConfig = dst.stress.StressVOPRConfig;
const TimingConfig = dst.stress.TimingConfig;

const Recorder = dst.stress.Recorder;
const Recording = dst.stress.Recording;
const Replayer = dst.stress.Replayer;

const input = @import("input");
const modifier = input.modifier;

pub const RunnerConfig = struct {
    seed: ?u64 = null,
    max_ticks: u64 = 10000,
    output_path: ?[]const u8 = null,
    replay_path: ?[]const u8 = null,
    verbose: bool = false,
    stall_probability: u8 = 2,
    cpu_spike_probability: u8 = 5,
    hook_timeout_probability: u8 = 1,
    burst_probability: u8 = 10,
    queue_capacity: u32 = 64,
    use_resilient_queue: bool = true,
    compare_mode: bool = false,
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

    if (config.replay_path) |path| {
        try run_replay(allocator, path, config.verbose);
    } else if (config.compare_mode) {
        try run_comparison(allocator, config);
    } else {
        try run_stress_vopr(allocator, config);
    }
}

fn parse_args(allocator: std.mem.Allocator) !RunnerConfig {
    var config = RunnerConfig{};
    var parser = try common.ArgParser.init(allocator);
    defer parser.deinit();

    while (parser.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--seed=")) {
            config.seed = common.parse_int_arg(u64, arg, "--seed=", 0);
            if (config.seed == 0) config.seed = null;
        } else if (std.mem.startsWith(u8, arg, "--ticks=")) {
            config.max_ticks = common.parse_int_arg(u64, arg, "--ticks=", 10000);
        } else if (std.mem.startsWith(u8, arg, "--output=")) {
            config.output_path = common.parse_string_arg(allocator, arg, "--output=");
        } else if (std.mem.startsWith(u8, arg, "--replay=")) {
            config.replay_path = common.parse_string_arg(allocator, arg, "--replay=");
        } else if (std.mem.startsWith(u8, arg, "--stall=")) {
            config.stall_probability = common.parse_int_arg(u8, arg, "--stall=", 2);
        } else if (std.mem.startsWith(u8, arg, "--cpu-spike=")) {
            config.cpu_spike_probability = common.parse_int_arg(u8, arg, "--cpu-spike=", 5);
        } else if (std.mem.startsWith(u8, arg, "--hook-timeout=")) {
            config.hook_timeout_probability = common.parse_int_arg(u8, arg, "--hook-timeout=", 1);
        } else if (std.mem.startsWith(u8, arg, "--burst=")) {
            config.burst_probability = common.parse_int_arg(u8, arg, "--burst=", 10);
        } else if (std.mem.startsWith(u8, arg, "--queue=")) {
            config.queue_capacity = common.parse_int_arg(u32, arg, "--queue=", 64);
        } else if (common.matches_flag(arg, "-v", "--verbose")) {
            config.verbose = true;
        } else if (common.matches_flag(arg, "--legacy", "--legacy")) {
            config.use_resilient_queue = false;
        } else if (common.matches_flag(arg, "--compare", "--compare")) {
            config.compare_mode = true;
        }
    }

    return config;
}

fn run_stress_vopr(allocator: std.mem.Allocator, config: RunnerConfig) !void {
    const seed = config.seed orelse common.random_seed();

    common.print_header("Stress VOPR Starting");
    common.print_field("Seed", seed);
    common.print_field("Max Ticks", config.max_ticks);
    common.print_field("Queue Mode", if (config.use_resilient_queue) "resilient" else "legacy");

    common.print_section("Timing Configuration");
    common.print_field("Stall Probability", config.stall_probability);
    common.print_field("CPU Spike Probability", config.cpu_spike_probability);
    common.print_field("Hook Timeout Probability", config.hook_timeout_probability);
    common.print_field("Burst Probability", config.burst_probability);
    common.print_field("Queue Capacity", config.queue_capacity);

    var vopr = StressVOPR.init(.{
        .seed = seed,
        .max_ticks = config.max_ticks,
        .burst_probability = config.burst_probability,
        .timing = .{
            .stall_probability = config.stall_probability,
            .cpu_spike_probability = config.cpu_spike_probability,
            .hook_timeout_probability = config.hook_timeout_probability,
            .input_queue_capacity = config.queue_capacity,
            .use_resilient_queue = config.use_resilient_queue,
        },
    });
    defer vopr.deinit();

    const start_time = std.time.milliTimestamp();
    vopr.run();
    const end_time = std.time.milliTimestamp();

    const stats = vopr.get_stats();
    const stress_state = vopr.get_stress_state();

    common.print_section("Stress VOPR Completed");
    common.print_duration(start_time, end_time);

    common.print_section("Input Statistics");
    common.print_field("Total Ticks", stats.total_ticks);
    common.print_field("Inputs Queued", stats.inputs_queued);
    common.print_field("Inputs Processed", stats.inputs_processed);
    common.print_field("Inputs Dropped", stats.inputs_dropped);

    const total_inputs = stats.inputs_queued + stats.inputs_dropped;
    const drop_rate = if (total_inputs > 0)
        @as(f64, @floatFromInt(stats.inputs_dropped)) / @as(f64, @floatFromInt(total_inputs)) * 100.0
    else
        0.0;
    common.print_field_fmt("Drop Rate", "{d:.2}%", .{drop_rate});

    const process_rate = if (stats.inputs_queued > 0)
        @as(f64, @floatFromInt(stats.inputs_processed)) / @as(f64, @floatFromInt(stats.inputs_queued)) * 100.0
    else
        0.0;
    common.print_field_fmt("Process Rate", "{d:.2}%", .{process_rate});

    common.print_section("Timing Statistics");
    common.print_field("Timing Misses", stats.timing_misses);
    common.print_field("Max Queue Depth", stats.max_queue_depth);
    common.print_field_fmt("Total Delay", "{d}ms", .{stats.total_delay_ns / 1_000_000});
    common.print_field_fmt("Avg Delay per Input", "{d}us", .{
        if (stats.inputs_processed > 0)
            stats.total_delay_ns / stats.inputs_processed / 1000
        else
            0,
    });

    common.print_section("Stress Statistics");
    common.print_field_fmt("Stress Ticks", "{d} ({d:.1}%)", .{
        stats.stress_ticks,
        @as(f64, @floatFromInt(stats.stress_ticks)) / @as(f64, @floatFromInt(stats.total_ticks)) * 100.0,
    });
    common.print_field("Bursts Generated", stats.bursts_generated);
    common.print_field("Bindings Triggered", stats.bindings_triggered);

    common.print_section("Resilience Statistics");
    common.print_field("Coalesced Inputs", stats.coalesced);
    common.print_field("Expired Inputs", stats.expired);
    common.print_field("Throttle Activations", stats.throttle_activations);
    common.print_field("Modifier Races", stress_state.modifier_races);

    common.print_section("Drop Breakdown");
    common.print_field("Hook Lost Drops", stats.hook_lost_drops);
    common.print_field("Stall Drops", stats.stall_drops);
    common.print_field("Backpressure Drops", stats.backpressure_drops);
    common.print_field("Total Drops", stats.inputs_dropped);

    common.print_section("Hook Health");
    common.print_field("Hook Deaths", stats.hook_deaths);
    common.print_field("Hook Restores", stats.hook_restores);

    const stress_events = vopr.get_stress_events();
    if (config.verbose and stress_events.len > 0) {
        common.print_section("Stress Events (last 20)");
        const start_idx = if (stress_events.len > 20) stress_events.len - 20 else 0;
        for (stress_events[start_idx..]) |event| {
            std.debug.print("  [{d}] {s}\n", .{ event.tick, @tagName(event.kind) });
        }
    }

    if (config.output_path) |path| {
        common.print_section("Recording");
        common.print_field("Path", path);

        var recorder = Recorder.init(allocator);
        defer recorder.deinit();

        try recorder.record_stress_vopr(&vopr);
        try recorder.write_to_file(path);

        common.print_field("Size", recorder.get_data().len);
        common.print_field("Events", stress_events.len);
    }

    if (stats.timing_misses > 0) {
        common.print_warning("{d} timing window misses detected!", .{stats.timing_misses});
        if (config.use_resilient_queue) {
            std.debug.print("These inputs were expired (>100ms old) and dropped.\n", .{});
        } else {
            std.debug.print("This indicates inputs were delayed beyond acceptable thresholds.\n", .{});
        }
    }

    if (stats.backpressure_drops > 0) {
        common.print_warning("{d} inputs dropped due to queue backpressure!", .{stats.backpressure_drops});
    }

    if (stats.hook_lost_drops > 0) {
        common.print_warning("{d} inputs lost while hook was dead (UAC/secure desktop/timeout)!", .{stats.hook_lost_drops});
        std.debug.print("Production mitigation: health.zig monitors hook state and auto-reinstalls.\n", .{});
    }

    if (stats.hook_deaths > 0) {
        std.debug.print("Note: Hook died {d} times, restored {d} times during simulation.\n", .{ stats.hook_deaths, stats.hook_restores });
    }
}

fn run_comparison(allocator: std.mem.Allocator, config: RunnerConfig) !void {
    const seed = config.seed orelse common.random_seed();

    common.print_header("Stress VOPR Comparison");
    common.print_field("Seed", seed);
    common.print_field("Max Ticks", config.max_ticks);

    common.print_section("Running Legacy Queue...");

    var legacy_vopr = StressVOPR.init(.{
        .seed = seed,
        .max_ticks = config.max_ticks,
        .burst_probability = config.burst_probability,
        .timing = .{
            .stall_probability = config.stall_probability,
            .cpu_spike_probability = config.cpu_spike_probability,
            .hook_timeout_probability = config.hook_timeout_probability,
            .input_queue_capacity = config.queue_capacity,
            .use_resilient_queue = false,
        },
    });
    defer legacy_vopr.deinit();

    const legacy_start = std.time.milliTimestamp();
    legacy_vopr.run();
    const legacy_end = std.time.milliTimestamp();
    const legacy_stats = legacy_vopr.get_stats();

    common.print_section("Running Resilient Queue...");

    var resilient_vopr = StressVOPR.init(.{
        .seed = seed,
        .max_ticks = config.max_ticks,
        .burst_probability = config.burst_probability,
        .timing = .{
            .stall_probability = config.stall_probability,
            .cpu_spike_probability = config.cpu_spike_probability,
            .hook_timeout_probability = config.hook_timeout_probability,
            .input_queue_capacity = config.queue_capacity,
            .use_resilient_queue = true,
        },
    });
    defer resilient_vopr.deinit();

    const resilient_start = std.time.milliTimestamp();
    resilient_vopr.run();
    const resilient_end = std.time.milliTimestamp();
    const resilient_stats = resilient_vopr.get_stats();

    common.print_section("Comparison Results");

    std.debug.print("\n{s:<25} {s:>15} {s:>15} {s:>12}\n", .{ "Metric", "Legacy", "Resilient", "Improvement" });
    std.debug.print("{s:-<25} {s:->15} {s:->15} {s:->12}\n", .{ "", "", "", "" });

    print_comparison("Duration (ms)", legacy_end - legacy_start, resilient_end - resilient_start);
    print_comparison("Inputs Queued", legacy_stats.inputs_queued, resilient_stats.inputs_queued);
    print_comparison("Inputs Processed", legacy_stats.inputs_processed, resilient_stats.inputs_processed);
    print_comparison_inverse("Inputs Dropped", legacy_stats.inputs_dropped, resilient_stats.inputs_dropped);
    print_comparison_inverse("Timing Misses", legacy_stats.timing_misses, resilient_stats.timing_misses);
    print_comparison("Max Queue Depth", legacy_stats.max_queue_depth, resilient_stats.max_queue_depth);
    print_comparison("Coalesced", legacy_stats.coalesced, resilient_stats.coalesced);
    print_comparison("Throttle Activations", @as(u64, 0), resilient_stats.throttle_activations);
    print_comparison_inverse("Hook Lost Drops", legacy_stats.hook_lost_drops, resilient_stats.hook_lost_drops);
    print_comparison_inverse("Backpressure Drops", legacy_stats.backpressure_drops, resilient_stats.backpressure_drops);
    print_comparison("Hook Deaths", legacy_stats.hook_deaths, resilient_stats.hook_deaths);
    print_comparison("Hook Restores", legacy_stats.hook_restores, resilient_stats.hook_restores);

    _ = allocator;
}

fn print_comparison(name: []const u8, legacy: anytype, resilient: @TypeOf(legacy)) void {
    const legacy_f: f64 = @floatFromInt(legacy);
    const resilient_f: f64 = @floatFromInt(resilient);
    const improvement = if (legacy_f > 0) ((resilient_f - legacy_f) / legacy_f) * 100.0 else 0.0;
    const sign: []const u8 = if (improvement >= 0) "+" else "";

    std.debug.print("{s:<25} {d:>15} {d:>15} {s}{d:>10.1}%\n", .{ name, legacy, resilient, sign, improvement });
}

fn print_comparison_inverse(name: []const u8, legacy: anytype, resilient: @TypeOf(legacy)) void {
    const legacy_f: f64 = @floatFromInt(legacy);
    const resilient_f: f64 = @floatFromInt(resilient);
    const improvement = if (legacy_f > 0) ((legacy_f - resilient_f) / legacy_f) * 100.0 else 0.0;

    std.debug.print("{s:<25} {d:>15} {d:>15} {d:>11.1}%\n", .{ name, legacy, resilient, improvement });
}

fn run_replay(allocator: std.mem.Allocator, path: []const u8, verbose: bool) !void {
    common.print_header("Loading Recording");
    common.print_field("Path", path);

    var recording = try Recording.load_from_file(allocator, path);
    defer recording.deinit();

    common.print_field("Seed", recording.config.seed);
    common.print_field("Max Ticks", recording.config.max_ticks);
    common.print_field("Events", recording.events.len);

    var replayer = Replayer.init();
    defer replayer.deinit();
    replayer.load_recording(&recording);

    common.print_section("Replaying...");

    var events_replayed: u64 = 0;
    while (replayer.step()) {
        events_replayed += 1;
        if (verbose) {
            const replay_state = replayer.get_state();
            std.debug.print("  [{d}] cpu={d} focus={} stall={}\n", .{
                replay_state.tick,
                replay_state.cpu_load,
                replay_state.has_focus,
                replay_state.in_stall,
            });
        }
    }

    common.print_field("Final Tick", replayer.current_tick);
    common.print_field("Events Replayed", events_replayed);
}
