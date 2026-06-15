const std = @import("std");

const w32 = @import("win32").everything;

const common = @import("common.zig");
const input_test = @import("input.zig");
const registry_fuzz = @import("registry.zig");
const simulator_mod = @import("simulator.zig");
const property = @import("property");
const properties = property.properties;

const Simulator = simulator_mod.Simulator;

pub const mode_max: u8 = 2;
pub const iteration_max: u32 = 0xFFFFFFFF;
pub const progress_interval: u32 = 1000;
pub const steps_per_sim: u32 = 100;
pub const arg_max: u32 = 64;
pub const seed_prefix_len: u8 = 7;
pub const iterations_prefix_len: u8 = 13;
pub const duration_prefix_len: u8 = 11;

pub const Mode = enum(u8) {
    smoke = 0,
    full = 1,
    stress = 2,

    pub fn is_valid(self: Mode) bool {
        const value = @intFromEnum(self);

        std.debug.assert(mode_max == 2);

        const result = value <= mode_max;

        return result;
    }

    pub fn batch_size(self: Mode) u32 {
        std.debug.assert(self.is_valid());

        const result: u32 = switch (self) {
            .smoke => 10,
            .full => 100,
            .stress => 1000,
        };

        std.debug.assert(result > 0);

        return result;
    }

    pub fn default_iterations(self: Mode) u32 {
        std.debug.assert(self.is_valid());

        const result: u32 = switch (self) {
            .smoke => 100,
            .full => 10000,
            .stress => 100000,
        };

        std.debug.assert(result > 0);

        return result;
    }

    pub fn sim_steps(self: Mode) u32 {
        std.debug.assert(self.is_valid());

        const result: u32 = switch (self) {
            .smoke => 50,
            .full => 200,
            .stress => 1000,
        };

        std.debug.assert(result > 0);

        return result;
    }
};

pub const Config = struct {
    seed: u64,
    mode: Mode,
    iterations: u32,
    duration_seconds: ?u64,

    pub fn is_valid(self: *const Config) bool {
        std.debug.assert(iteration_max == 0xFFFFFFFF);

        const valid_mode = self.mode.is_valid();
        const valid_iterations = self.iterations > 0;
        const result = valid_mode and valid_iterations;

        return result;
    }

    pub fn parse(process_args: std.process.Args, allocator: std.mem.Allocator) Config {
        var args = process_args.iterateAllocator(allocator) catch {
            return default_config();
        };

        defer args.deinit();

        _ = args.skip();

        var config = Config{
            .seed = common.get_seed_from_env(),
            .mode = .full,
            .iterations = Mode.full.default_iterations(),
            .duration_seconds = null,
        };

        parse_arguments(&args, &config);

        std.debug.assert(config.is_valid());

        return config;
    }

    fn default_config() Config {
        const result = Config{
            .seed = common.get_seed_from_env(),
            .mode = .full,
            .iterations = Mode.full.default_iterations(),
            .duration_seconds = null,
        };

        std.debug.assert(result.is_valid());

        return result;
    }
};

fn parse_arguments(args: anytype, config: *Config) void {
    var arg_count: u32 = 0;

    while (args.next()) |arg| {
        std.debug.assert(arg_count < arg_max);

        parse_argument(arg, config);

        arg_count += 1;

        if (arg_count >= arg_max) {
            break;
        }
    }

    std.debug.assert(arg_count <= arg_max);
}

fn parse_argument(arg: []const u8, config: *Config) void {
    std.debug.assert(arg.len > 0);

    if (std.mem.startsWith(u8, arg, "--seed=")) {
        config.seed = parse_argument_seed(arg);
    } else if (std.mem.startsWith(u8, arg, "--iterations=")) {
        config.iterations = parse_argument_iterations(arg);
    } else if (std.mem.startsWith(u8, arg, "--duration=")) {
        config.duration_seconds = parse_argument_duration(arg);
    } else if (std.mem.eql(u8, arg, "--smoke")) {
        config.mode = .smoke;
        config.iterations = Mode.smoke.default_iterations();
    } else if (std.mem.eql(u8, arg, "--stress")) {
        config.mode = .stress;
        config.iterations = Mode.stress.default_iterations();
    }
}

fn parse_argument_seed(arg: []const u8) u64 {
    std.debug.assert(arg.len > seed_prefix_len);

    const result = common.parse_seed(arg[seed_prefix_len..]);

    return result;
}

fn parse_argument_iterations(arg: []const u8) u32 {
    std.debug.assert(arg.len > iterations_prefix_len);

    const result = std.fmt.parseUnsigned(u32, arg[iterations_prefix_len..], 10) catch Mode.full.default_iterations();

    std.debug.assert(result > 0 or result == 0);

    return result;
}

fn parse_argument_duration(arg: []const u8) ?u64 {
    std.debug.assert(arg.len > duration_prefix_len);

    const result = std.fmt.parseUnsigned(u64, arg[duration_prefix_len..], 10) catch null;

    return result;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    const config = Config.parse(init.minimal.args, allocator);

    std.debug.assert(config.is_valid());

    print_header(&config);

    const start_ms: i64 = @intCast(w32.GetTickCount64());
    var prng = std.Random.DefaultPrng.init(config.seed);
    var sim = Simulator.init(config.seed);

    const result = run_fuzzer(&config, &prng, &sim, start_ms);

    print_footer(&result, start_ms);

    if (result.sim_failures > 0) {
        std.process.exit(1);
    }
}

const FuzzerResult = struct {
    iterations: u32,
    sim_failures: u32,
};

fn print_header(config: *const Config) void {
    std.debug.assert(config.is_valid());

    std.debug.print("Fuzzer: Starting...\n", .{});
    std.debug.print("Seed: {d}\n", .{config.seed});
    std.debug.print("Mode: {s}\n", .{@tagName(config.mode)});
    std.debug.print("Iteration(s): {d}\n", .{config.iterations});
    std.debug.print("\n", .{});
}

fn print_footer(result: *const FuzzerResult, start_ms: i64) void {
    const now_ms: i64 = @intCast(w32.GetTickCount64());
    const elapsed_ms: i64 = now_ms - start_ms;

    std.debug.print("\nFuzzer: Completed\n", .{});
    std.debug.print("Iteration(s): {d}\n", .{result.iterations});
    std.debug.print("Simulation Failure(s): {d}\n", .{result.sim_failures});
    std.debug.print("Elapsed: {d} ms\n", .{elapsed_ms});

    if (elapsed_ms > 0) {
        const rate = result.iterations * 1000 / @as(u32, @intCast(elapsed_ms));

        std.debug.print("Rate: {d} iter/s\n", .{rate});
    }
}

fn run_fuzzer(config: *const Config, prng: *std.Random.DefaultPrng, sim: *Simulator, start_ms: i64) FuzzerResult {
    std.debug.assert(config.is_valid());

    var iteration: u32 = 0;
    var sim_failures: u32 = 0;

    while (iteration < config.iterations) : (iteration += 1) {
        const iter_seed = prng.random().int(u64);

        sim.reseed(iter_seed);

        if (sim.run(config.mode.sim_steps())) |failure| {
            std.debug.print("\nFailure at iteration {d}:\n", .{iteration});
            std.debug.print("{f}\n", .{failure});
            sim_failures += 1;
        }

        run_legacy_tests(iter_seed, config.mode) catch {};

        if (iteration > 0 and iteration % progress_interval == 0) {
            const elapsed_ms: i64 = @as(i64, @intCast(w32.GetTickCount64())) - start_ms;

            std.debug.print("Progress: {d} iterations in {d} ms\n", .{ iteration, elapsed_ms });
        }
    }

    std.debug.assert(iteration == config.iterations);

    const result = FuzzerResult{
        .iterations = iteration,
        .sim_failures = sim_failures,
    };

    return result;
}

fn run_legacy_tests(seed: u64, mode: Mode) !void {
    std.debug.assert(mode.is_valid());

    var prng = std.Random.DefaultPrng.init(seed);
    var random = prng.random();

    const batch_size = mode.batch_size();

    std.debug.assert(batch_size > 0);

    try input_test.fuzz_binding(&random, batch_size);
    try input_test.fuzz_keyboard(&random, batch_size);
    try registry_fuzz.fuzz_key_registry(seed, batch_size);
    try registry_fuzz.fuzz_binding_matching(seed, batch_size);

    if (mode != .smoke) {
        try properties.property_keyboard_keydown_is_down();
        try properties.property_modifier_set_flags();
        try properties.property_binding_match_self();
    }
}

const testing = std.testing;

test "Fuzzer smoke" {
    const config = Config{
        .seed = 42,
        .mode = .smoke,
        .iterations = 10,
        .duration_seconds = null,
    };

    std.debug.assert(config.is_valid());

    var prng = std.Random.DefaultPrng.init(config.seed);
    var sim = Simulator.init(config.seed);
    var iteration: u32 = 0;

    while (iteration < config.iterations) : (iteration += 1) {
        const iter_seed = prng.random().int(u64);

        sim.reseed(iter_seed);

        const failure = sim.run(config.mode.sim_steps());

        try testing.expect(failure == null);

        try run_legacy_tests(iter_seed, config.mode);
    }

    std.debug.assert(iteration == config.iterations);
}
