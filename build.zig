const std = @import("std");

const assert = std.debug.assert;

const Steps = struct {
    check: *std.Build.Step,
    ci: *std.Build.Step,
    examples: *std.Build.Step,
    fuzz: *std.Build.Step,
    fuzz_build: *std.Build.Step,
    drill: *std.Build.Step,
    fuzz_smoke: *std.Build.Step,
    test_all: *std.Build.Step,
    test_fmt: *std.Build.Step,
    test_linux: *std.Build.Step,
    test_mock: *std.Build.Step,
    test_unit: *std.Build.Step,
    test_windows: *std.Build.Step,
};

const windows_query = std.Target.Query{
    .cpu_arch = .x86_64,
    .os_tag = .windows,
    .abi = .gnu,
};

const format_paths = [_][]const u8{ "build.zig", "src", "examples" };
const example_directory_windows = "examples/windows";
const example_name_bytes_max: u32 = 256;

comptime {
    assert(format_paths.len > 0);
    assert(example_name_bytes_max >= 64);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const steps = create_steps(b);

    const Backend = enum { native, mock };
    const backend = b.option(Backend, "backend", "Backend selection: native or mock") orelse
        .native;

    const options = b.addOptions();

    options.addOption([]const u8, "library", "nimble");
    options.addOption(bool, "backend_mock", backend == .mock);

    const build_options = options.createModule();

    const mock_options = b.addOptions();

    mock_options.addOption([]const u8, "library", "nimble");
    mock_options.addOption(bool, "backend_mock", true);

    const mock_build_options = mock_options.createModule();

    const nimble = b.addModule("nimble", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    nimble.addImport("build_options", build_options);

    if (target.result.os.tag == .windows) {
        nimble.linkSystemLibrary("user32", .{});
    }

    add_format(b, &steps);
    add_daemon(b, &steps, build_options, target, optimize);
    add_unit_tests(b, &steps, build_options, optimize);
    add_mock_tests(b, &steps, mock_build_options, optimize);
    add_linux_tests(b, &steps, build_options, optimize);
    add_drill(b, &steps, build_options, optimize);
    add_windows_tests(b, &steps, build_options, target, optimize);
    add_fuzz(b, &steps, mock_build_options, optimize);
    add_examples(b, &steps, nimble, target, optimize);

    steps.ci.dependOn(steps.test_fmt);
    steps.ci.dependOn(steps.check);
    steps.ci.dependOn(steps.test_unit);
    steps.ci.dependOn(steps.test_mock);
    steps.ci.dependOn(steps.test_linux);
    steps.ci.dependOn(steps.test_windows);
    steps.ci.dependOn(steps.fuzz_smoke);

    b.default_step.dependOn(steps.check);
}

fn create_steps(b: *std.Build) Steps {
    return .{
        .check = b.step("check", "Compile every artifact without running it"),
        .ci = b.step("ci", "Run formatting, compilation, unit tests, and fuzzer smoke"),
        .examples = b.step("examples", "Build every example"),
        .fuzz = b.step("fuzz", "Run a fuzzer: -- <fuzzer> [seed] [events]"),
        .fuzz_build = b.step("fuzz:build", "Compile the fuzzer without running it"),
        .fuzz_smoke = b.step("fuzz:smoke", "Run every fuzzer briefly with a fixed seed"),
        .drill = b.step(
            "drill",
            "Run a Linux verification drill: -- <probe|scan|synthesis|observe|grab>",
        ),
        .test_all = b.step("test", "Run unit tests and the formatting check"),
        .test_fmt = b.step("test:fmt", "Check that every source file is formatted"),
        .test_linux = b.step("test:linux", "Run the Linux backend tests on a Linux host"),
        .test_mock = b.step("test:mock", "Run the full pipeline against the mock backend"),
        .test_unit = b.step("test:unit", "Run the colocated unit tests and the tidy law"),
        .test_windows = b.step("test:windows", "Run the Windows backend tests on a Windows host"),
    };
}

fn add_format(b: *std.Build, steps: *const Steps) void {
    const fmt = b.addFmt(.{
        .paths = &format_paths,
        .check = true,
    });

    steps.test_fmt.dependOn(&fmt.step);
    steps.test_all.dependOn(&fmt.step);
}

fn add_daemon(
    b: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    if (target.result.os.tag != .linux) {
        return;
    }

    const module = b.createModule(.{
        .root_source_file = b.path("src/daemon.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const exe = b.addExecutable(.{ .name = "nimbled", .root_module = module });

    b.installArtifact(exe);

    steps.check.dependOn(&exe.step);
}

fn add_unit_tests(
    b: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    optimize: std.builtin.OptimizeMode,
) void {
    const module = b.createModule(.{
        .root_source_file = b.path("src/unit_tests.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const core = b.addTest(.{
        .root_module = module,
        .filters = b.args orelse &.{},
    });

    const run = b.addRunArtifact(core);

    run.setCwd(b.path("."));

    steps.test_unit.dependOn(&run.step);
    steps.test_all.dependOn(&run.step);
    steps.check.dependOn(&core.step);
}

fn add_drill(
    b: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    optimize: std.builtin.OptimizeMode,
) void {
    if (b.graph.host.result.os.tag != .linux) {
        return;
    }

    const module = b.createModule(.{
        .root_source_file = b.path("src/drill.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const exe = b.addExecutable(.{ .name = "drill", .root_module = module });
    const run = b.addRunArtifact(exe);

    run.setCwd(b.path("."));

    if (b.args) |args| run.addArgs(args);

    steps.drill.dependOn(&run.step);
    steps.check.dependOn(&exe.step);
}

fn add_linux_tests(
    b: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    optimize: std.builtin.OptimizeMode,
) void {
    if (b.graph.host.result.os.tag != .linux) {
        return;
    }

    const module = b.createModule(.{
        .root_source_file = b.path("src/linux_tests.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const suite = b.addTest(.{
        .root_module = module,
        .filters = b.args orelse &.{},
    });

    const run = b.addRunArtifact(suite);

    run.setCwd(b.path("."));

    steps.test_linux.dependOn(&run.step);
    steps.test_all.dependOn(&run.step);
    steps.check.dependOn(&suite.step);
}

fn add_mock_tests(
    b: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    optimize: std.builtin.OptimizeMode,
) void {
    const module = b.createModule(.{
        .root_source_file = b.path("src/mock_tests.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const mock = b.addTest(.{
        .root_module = module,
        .filters = b.args orelse &.{},
    });

    const run = b.addRunArtifact(mock);

    run.setCwd(b.path("."));

    steps.test_mock.dependOn(&run.step);
    steps.test_all.dependOn(&run.step);
    steps.check.dependOn(&mock.step);
}

fn add_windows_tests(
    b: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const resolved = if (target.result.os.tag == .windows)
        target
    else
        b.resolveTargetQuery(windows_query);

    const module = b.createModule(.{
        .root_source_file = b.path("src/windows_tests.zig"),
        .target = resolved,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const unit = b.addTest(.{
        .root_module = module,
        .filters = b.args orelse &.{},
    });

    steps.check.dependOn(&unit.step);

    if (b.graph.host.result.os.tag != .windows) {
        return;
    }

    const run = b.addRunArtifact(unit);

    run.setCwd(b.path("."));

    steps.test_windows.dependOn(&run.step);
    steps.test_all.dependOn(&run.step);
}

fn add_fuzz(
    b: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    optimize: std.builtin.OptimizeMode,
) void {
    const module = b.createModule(.{
        .root_source_file = b.path("src/fuzz_tests.zig"),
        .target = b.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const exe = b.addExecutable(.{
        .name = "fuzz",
        .root_module = module,
    });

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);

    run.setCwd(b.path("."));

    if (b.args) |args| run.addArgs(args);

    const smoke = b.addRunArtifact(exe);

    smoke.setCwd(b.path("."));
    smoke.addArg("smoke");

    steps.fuzz.dependOn(&run.step);
    steps.fuzz_build.dependOn(&exe.step);
    steps.fuzz_smoke.dependOn(&smoke.step);
    steps.check.dependOn(&exe.step);
}

fn add_examples(
    b: *std.Build,
    steps: *const Steps,
    nimble: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    add_example_directory(b, steps, nimble, target, optimize, "examples");

    if (target.result.os.tag == .windows) {
        add_example_directory(b, steps, nimble, target, optimize, example_directory_windows);
    }
}

fn add_example_directory(
    b: *std.Build,
    steps: *const Steps,
    nimble: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    comptime directory: []const u8,
) void {
    const io = b.graph.io;

    var dir = b.build_root.handle.openDir(io, directory, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var iterator = dir.iterate();

    while (iterator.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;

        const name = entry.name[0 .. entry.name.len - ".zig".len];

        var path_buffer: [example_name_bytes_max]u8 = undefined;

        const path = std.fmt.bufPrint(
            &path_buffer,
            "{s}/{s}",
            .{ directory, entry.name },
        ) catch continue;

        const module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = &.{.{ .name = "nimble", .module = nimble }},
        });

        if (target.result.os.tag == .windows) {
            module.linkSystemLibrary("user32", .{});
            module.linkSystemLibrary("gdi32", .{});
            module.linkSystemLibrary("shell32", .{});
        }

        const exe = b.addExecutable(.{
            .name = name,
            .root_module = module,
        });

        add_example_run(b, steps, exe, name);
    }
}

fn add_example_run(
    b: *std.Build,
    steps: *const Steps,
    exe: *std.Build.Step.Compile,
    name: []const u8,
) void {
    const install = b.addInstallArtifact(exe, .{});

    steps.examples.dependOn(&install.step);
    steps.check.dependOn(&exe.step);

    var run_name_buffer: [example_name_bytes_max]u8 = undefined;
    const run_name = std.fmt.bufPrint(&run_name_buffer, "run-{s}", .{name}) catch return;

    var description_buffer: [example_name_bytes_max]u8 = undefined;

    const description = std.fmt.bufPrint(
        &description_buffer,
        "Run the {s} example",
        .{name},
    ) catch return;

    const run = b.addRunArtifact(exe);

    run.step.dependOn(&install.step);

    b.step(run_name, description).dependOn(&run.step);
}
