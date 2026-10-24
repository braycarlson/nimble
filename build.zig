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

const linux_query = std.Target.Query{
    .cpu_arch = .x86_64,
    .os_tag = .linux,
    .abi = .gnu,
};

const windows_query = std.Target.Query{
    .cpu_arch = .x86_64,
    .os_tag = .windows,
    .abi = .gnu,
};

const ExampleUse = enum {
    installed,
    checked,
};

const format_paths = [_][]const u8{ "build.zig", "src", "examples" };
const example_directory_windows = "examples/windows";
const example_name_bytes_max: u32 = 256;

comptime {
    assert(format_paths.len > 0);
    assert(example_name_bytes_max >= 64);
}

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});
    const steps = create_steps(builder);
    const Backend = enum { native, mock };

    const backend = builder.option(Backend, "backend", "Backend selection: native or mock") orelse
        .native;

    const filters = builder.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &.{};

    const options = builder.addOptions();

    options.addOption([]const u8, "library", "nimble");
    options.addOption(bool, "backend_mock", backend == .mock);

    const build_options = options.createModule();
    const mock_options = builder.addOptions();

    mock_options.addOption([]const u8, "library", "nimble");
    mock_options.addOption(bool, "backend_mock", true);

    const mock_build_options = mock_options.createModule();

    const nimble = builder.addModule("nimble", .{
        .root_source_file = builder.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    nimble.addImport("build_options", build_options);

    if (target.result.os.tag == .windows) {
        nimble.linkSystemLibrary("user32", .{});
    }

    add_format(builder, &steps);
    add_daemon(builder, &steps, build_options, target, optimize);
    add_unit_tests(builder, &steps, build_options, optimize, filters);
    add_mock_tests(builder, &steps, mock_build_options, optimize, filters);
    add_linux_tests(builder, &steps, build_options, optimize, filters);
    add_drill(builder, &steps, build_options, optimize);
    add_windows_tests(builder, &steps, build_options, target, optimize, filters);
    add_fuzz(builder, &steps, mock_build_options, optimize);
    add_examples(builder, &steps, nimble, build_options, target, optimize);

    steps.ci.dependOn(steps.test_fmt);
    steps.ci.dependOn(steps.check);
    steps.ci.dependOn(steps.test_unit);
    steps.ci.dependOn(steps.test_mock);
    steps.ci.dependOn(steps.test_linux);
    steps.ci.dependOn(steps.test_windows);
    steps.ci.dependOn(steps.fuzz_smoke);

    builder.default_step.dependOn(steps.check);
}

fn create_steps(builder: *std.Build) Steps {
    return .{
        .check = builder.step("check", "Compile every artifact without running it"),
        .ci = builder.step("ci", "Run every check, test, and fuzz smoke"),
        .examples = builder.step("examples", "Build every example"),
        .fuzz = builder.step("fuzz", "Run a fuzzer: zig build fuzz -- <fuzzer> [seed] [events]"),
        .fuzz_build = builder.step("fuzz:build", "Compile the fuzzers without running them"),
        .fuzz_smoke = builder.step("fuzz:smoke", "Run every fuzzer briefly with a fixed seed"),
        .drill = builder.step(
            "drill",
            "Run a Linux verification drill: -- <probe|scan|synthesis|observe|grab>",
        ),
        .test_all = builder.step("test", "Run every test suite and the format check"),
        .test_fmt = builder.step("test:fmt", "Check that every source file is formatted"),
        .test_linux = builder.step("test:linux", "Run the Linux backend tests on a Linux host"),
        .test_mock = builder.step("test:mock", "Run the end to end tests against the mock backend"),
        .test_unit = builder.step("test:unit", "Run the unit tests and the tidy check"),
        .test_windows = builder.step(
            "test:windows",
            "Run the Windows backend tests on a Windows host",
        ),
    };
}

fn add_format(builder: *std.Build, steps: *const Steps) void {
    const fmt = builder.addFmt(.{
        .paths = builder.pathList(&format_paths),
        .check = true,
    });

    steps.test_fmt.dependOn(&fmt.step);
    steps.test_all.dependOn(&fmt.step);
}

fn add_daemon(
    builder: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
) void {
    const native = target.result.os.tag == .linux;
    const resolved = if (native) target else builder.resolveTargetQuery(linux_query);

    const module = builder.createModule(.{
        .root_source_file = builder.path("src/daemon.zig"),
        .target = resolved,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const exe = builder.addExecutable(.{ .name = "nimbled", .root_module = module });

    if (native) builder.installArtifact(exe);

    steps.check.dependOn(&exe.step);
}

fn add_unit_tests(
    builder: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    optimize: std.lang.Optimize,
    filters: []const []const u8,
) void {
    const module = builder.createModule(.{
        .root_source_file = builder.path("src/unit_tests.zig"),
        .target = builder.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const core = builder.addTest(.{
        .root_module = module,
        .filters = filters,
    });

    const run = builder.addRunArtifact(core);

    run.setCwd(builder.path("."));

    steps.test_unit.dependOn(&run.step);
    steps.test_all.dependOn(&run.step);
    steps.check.dependOn(&core.step);
}

fn add_drill(
    builder: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    optimize: std.lang.Optimize,
) void {
    const native = builder.graph.host.result.os.tag == .linux;
    const resolved = if (native) builder.graph.host else builder.resolveTargetQuery(linux_query);

    const module = builder.createModule(.{
        .root_source_file = builder.path("src/drill.zig"),
        .target = resolved,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const exe = builder.addExecutable(.{ .name = "drill", .root_module = module });

    steps.check.dependOn(&exe.step);

    if (!native) return;

    const run = builder.addRunArtifact(exe);

    run.setCwd(builder.path("."));
    run.addPassthruArgs();

    steps.drill.dependOn(&run.step);
}

fn add_linux_tests(
    builder: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    optimize: std.lang.Optimize,
    filters: []const []const u8,
) void {
    if (builder.graph.host.result.os.tag != .linux) {
        return;
    }

    const module = builder.createModule(.{
        .root_source_file = builder.path("src/linux_tests.zig"),
        .target = builder.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const suite = builder.addTest(.{
        .root_module = module,
        .filters = filters,
    });

    const run = builder.addRunArtifact(suite);

    run.setCwd(builder.path("."));

    steps.test_linux.dependOn(&run.step);
    steps.test_all.dependOn(&run.step);
    steps.check.dependOn(&suite.step);
}

fn add_mock_tests(
    builder: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    optimize: std.lang.Optimize,
    filters: []const []const u8,
) void {
    const module = builder.createModule(.{
        .root_source_file = builder.path("src/mock_tests.zig"),
        .target = builder.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const mock = builder.addTest(.{
        .root_module = module,
        .filters = filters,
    });

    const run = builder.addRunArtifact(mock);

    run.setCwd(builder.path("."));

    steps.test_mock.dependOn(&run.step);
    steps.test_all.dependOn(&run.step);
    steps.check.dependOn(&mock.step);
}

fn add_windows_tests(
    builder: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    filters: []const []const u8,
) void {
    const resolved = if (target.result.os.tag == .windows)
        target
    else
        builder.resolveTargetQuery(windows_query);

    const module = builder.createModule(.{
        .root_source_file = builder.path("src/windows_tests.zig"),
        .target = resolved,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const unit = builder.addTest(.{
        .root_module = module,
        .filters = filters,
    });

    steps.check.dependOn(&unit.step);

    if (builder.graph.host.result.os.tag != .windows) {
        return;
    }

    const run = builder.addRunArtifact(unit);

    run.setCwd(builder.path("."));

    steps.test_windows.dependOn(&run.step);
    steps.test_all.dependOn(&run.step);
}

fn add_fuzz(
    builder: *std.Build,
    steps: *const Steps,
    build_options: *std.Build.Module,
    optimize: std.lang.Optimize,
) void {
    const module = builder.createModule(.{
        .root_source_file = builder.path("src/fuzz_tests.zig"),
        .target = builder.graph.host,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    const exe = builder.addExecutable(.{
        .name = "fuzz",
        .root_module = module,
    });

    builder.installArtifact(exe);

    const run = builder.addRunArtifact(exe);

    run.setCwd(builder.path("."));
    run.addPassthruArgs();

    const smoke = builder.addRunArtifact(exe);

    smoke.setCwd(builder.path("."));
    smoke.addArg("smoke");

    steps.fuzz.dependOn(&run.step);
    steps.fuzz_build.dependOn(&exe.step);
    steps.fuzz_smoke.dependOn(&smoke.step);
    steps.check.dependOn(&exe.step);
}

fn add_examples(
    builder: *std.Build,
    steps: *const Steps,
    nimble: *std.Build.Module,
    build_options: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
) void {
    const windows = target.result.os.tag == .windows;

    add_example_directory(builder, steps, nimble, target, optimize, "examples", .installed);

    if (windows) {
        add_example_directory(
            builder,
            steps,
            nimble,
            target,
            optimize,
            example_directory_windows,
            .installed,
        );
    }

    const other = builder.resolveTargetQuery(if (windows) linux_query else windows_query);
    const library = library_module(builder, build_options, other, optimize);

    add_example_directory(builder, steps, library, other, optimize, "examples", .checked);

    if (windows) return;

    add_example_directory(
        builder,
        steps,
        library,
        other,
        optimize,
        example_directory_windows,
        .checked,
    );
}

fn library_module(
    builder: *std.Build,
    build_options: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
) *std.Build.Module {
    const module = builder.createModule(.{
        .root_source_file = builder.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "build_options", .module = build_options }},
    });

    if (target.result.os.tag == .windows) {
        module.linkSystemLibrary("user32", .{});
    }

    return module;
}

fn add_example_directory(
    builder: *std.Build,
    steps: *const Steps,
    nimble: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    comptime directory: []const u8,
    use: ExampleUse,
) void {
    const io = builder.graph.io;

    var dir = builder.root.openDir(io, directory, .{ .iterate = true }) catch return;
    defer dir.close(io);

    builder.dependOnDirectoryContents(builder.path(directory));

    var iterator = dir.iterate();

    while (iterator.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;

        const name = entry.name[0 .. entry.name.len - ".zig".len];

        var path_buffer: [example_name_bytes_max]u8 = undefined;

        const path = std.mem.print(
            &path_buffer,
            "{s}/{s}",
            .{ directory, entry.name },
        ) catch continue;

        const module = builder.createModule(.{
            .root_source_file = builder.path(path),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "nimble", .module = nimble }},
        });

        if (target.result.os.tag == .windows) {
            module.linkSystemLibrary("user32", .{});
            module.linkSystemLibrary("gdi32", .{});
            module.linkSystemLibrary("shell32", .{});
        }

        const exe = builder.addExecutable(.{
            .name = name,
            .root_module = module,
        });

        switch (use) {
            .installed => add_example_run(builder, steps, exe, name),
            .checked => steps.check.dependOn(&exe.step),
        }
    }
}

fn add_example_run(
    builder: *std.Build,
    steps: *const Steps,
    exe: *std.Build.Step.Compile,
    name: []const u8,
) void {
    const install = builder.addInstallArtifact(exe, .{});

    steps.examples.dependOn(&install.step);
    steps.check.dependOn(&exe.step);

    var run_name_buffer: [example_name_bytes_max]u8 = undefined;
    const run_name = std.mem.print(&run_name_buffer, "run-{s}", .{name}) catch return;

    var description_buffer: [example_name_bytes_max]u8 = undefined;

    const description = std.mem.print(
        &description_buffer,
        "Run the {s} example",
        .{name},
    ) catch return;

    const run = builder.addRunArtifact(exe);

    run.step.dependOn(&install.step);

    builder.step(run_name, description).dependOn(&run.step);
}
