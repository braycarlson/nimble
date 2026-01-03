const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const win32 = b.dependency("zigwin32", .{}).module("win32");

    const input_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    input_module.addImport("win32", win32);

    const fuzz_module = b.createModule(.{
        .root_source_file = b.path("src/testing/fuzz/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    fuzz_module.addImport("win32", win32);
    fuzz_module.addImport("input", input_module);

    const property_module = b.createModule(.{
        .root_source_file = b.path("src/testing/property/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    property_module.addImport("win32", win32);
    property_module.addImport("input", input_module);

    const common_module = b.createModule(.{
        .root_source_file = b.path("src/testing/dst/common/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const dst_module = b.createModule(.{
        .root_source_file = b.path("src/testing/dst/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    dst_module.addImport("win32", win32);
    dst_module.addImport("input", input_module);
    dst_module.addImport("fuzz", fuzz_module);
    dst_module.addImport("common", common_module);

    const nimble = b.addModule("nimble", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    nimble.addImport("win32", win32);

    add_tests(b, target, optimize, win32, input_module, fuzz_module, property_module, dst_module);
    add_fuzzer(b, target, optimize, win32, input_module, fuzz_module, property_module);
    add_input(b, target, optimize, win32, input_module, fuzz_module, dst_module, common_module);
    add_hook(b, target, optimize, win32, input_module, fuzz_module, dst_module, common_module);
    add_stress(b, target, optimize, win32, input_module, fuzz_module, dst_module, common_module);
    add_examples(b, target, optimize, nimble, win32);
    add_visualizer(b, target, optimize);
    add_wasm(b, input_module, common_module);
}

fn add_tests(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    win32: *std.Build.Module,
    input_module: *std.Build.Module,
    fuzz_module: *std.Build.Module,
    property_module: *std.Build.Module,
    dst_module: *std.Build.Module,
) void {
    const step = b.step("test", "Run unit tests");

    const test_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    test_module.addImport("win32", win32);

    const unit_test = b.addTest(.{ .root_module = test_module });
    step.dependOn(&b.addRunArtifact(unit_test).step);

    const unit_step = b.step("unit", "Run unit tests from src/testing/unit/");

    const unit_module = b.createModule(.{
        .root_source_file = b.path("src/testing/unit/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    unit_module.addImport("win32", win32);
    unit_module.addImport("input", input_module);

    const unit_tests = b.addTest(.{ .root_module = unit_module });
    unit_step.dependOn(&b.addRunArtifact(unit_tests).step);

    const fuzz_step = b.step("fuzz", "Run fuzz tests");

    const testing_module = b.createModule(.{
        .root_source_file = b.path("src/testing/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    testing_module.addImport("win32", win32);
    testing_module.addImport("input", input_module);
    testing_module.addImport("fuzz", fuzz_module);
    testing_module.addImport("property", property_module);
    testing_module.addImport("dst", dst_module);

    const fuzz_test = b.addTest(.{ .root_module = testing_module });
    fuzz_step.dependOn(&b.addRunArtifact(fuzz_test).step);
}

fn add_fuzzer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    win32: *std.Build.Module,
    input_module: *std.Build.Module,
    fuzz_module: *std.Build.Module,
    property_module: *std.Build.Module,
) void {
    const step = b.step("fuzzer", "Run the fuzzer");

    const module = b.createModule(.{
        .root_source_file = b.path("src/testing/fuzz/runner.zig"),
        .target = target,
        .optimize = optimize,
    });

    module.addImport("win32", win32);
    module.addImport("input", input_module);
    module.addImport("fuzz", fuzz_module);
    module.addImport("property", property_module);

    const exe = b.addExecutable(.{ .name = "fuzzer", .root_module = module });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    step.dependOn(&run.step);
}

fn add_input(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    win32: *std.Build.Module,
    input_module: *std.Build.Module,
    fuzz_module: *std.Build.Module,
    dst_module: *std.Build.Module,
    common_module: *std.Build.Module,
) void {
    const step = b.step("input", "Run input VOPR simulation");

    const module = b.createModule(.{
        .root_source_file = b.path("src/testing/dst/input/runner.zig"),
        .target = target,
        .optimize = optimize,
    });

    module.addImport("win32", win32);
    module.addImport("input", input_module);
    module.addImport("fuzz", fuzz_module);
    module.addImport("dst", dst_module);
    module.addImport("common", common_module);

    const exe = b.addExecutable(.{ .name = "input", .root_module = module });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    step.dependOn(&run.step);
}

fn add_hook(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    win32: *std.Build.Module,
    input_module: *std.Build.Module,
    fuzz_module: *std.Build.Module,
    dst_module: *std.Build.Module,
    common_module: *std.Build.Module,
) void {
    const step = b.step("hook", "Run hook lifecycle simulation");

    const module = b.createModule(.{
        .root_source_file = b.path("src/testing/dst/hook/runner.zig"),
        .target = target,
        .optimize = optimize,
    });

    module.addImport("win32", win32);
    module.addImport("input", input_module);
    module.addImport("fuzz", fuzz_module);
    module.addImport("dst", dst_module);
    module.addImport("common", common_module);

    const exe = b.addExecutable(.{ .name = "hook", .root_module = module });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    step.dependOn(&run.step);
}

fn add_visualizer(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const step = b.step("visualizer", "Build native DST visualizer (requires raylib)");

    const raylib_dep = b.lazyDependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });

    if (raylib_dep == null) {
        return;
    }

    const module = b.createModule(.{
        .root_source_file = b.path("src/testing/dst/visualizer/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{ .name = "visualizer", .root_module = module });
    exe.linkLibrary(raylib_dep.?.artifact("raylib"));

    const install = b.addInstallArtifact(exe, .{});
    step.dependOn(&install.step);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(&install.step);
    if (b.args) |args| run.addArgs(args);
    step.dependOn(&run.step);
}

fn add_stress(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    win32: *std.Build.Module,
    input_module: *std.Build.Module,
    fuzz_module: *std.Build.Module,
    dst_module: *std.Build.Module,
    common_module: *std.Build.Module,
) void {
    const step = b.step("stress", "Run stress tests");

    const module = b.createModule(.{
        .root_source_file = b.path("src/testing/dst/stress/runner.zig"),
        .target = target,
        .optimize = optimize,
    });

    module.addImport("win32", win32);
    module.addImport("input", input_module);
    module.addImport("fuzz", fuzz_module);
    module.addImport("dst", dst_module);
    module.addImport("common", common_module);

    const exe = b.addExecutable(.{ .name = "stress", .root_module = module });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    if (b.args) |args| run.addArgs(args);
    step.dependOn(&run.step);
}

fn add_examples(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    nimble: *std.Build.Module,
    win32: *std.Build.Module,
) void {
    const step = b.step("examples", "Build all examples");

    var dir = std.fs.cwd().openDir("examples", .{ .iterate = true }) catch return;
    defer dir.close();

    var iter = dir.iterate();

    while (iter.next() catch null) |entry| {
        if (entry.kind != .file) {
            continue;
        }

        if (!std.mem.endsWith(u8, entry.name, ".zig")) {
            continue;
        }

        const name = entry.name[0 .. entry.name.len - 4];

        var path_buf: [256]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buf, "examples/{s}", .{entry.name}) catch continue;

        const module = b.createModule(.{
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        });

        module.addImport("nimble", nimble);
        module.addImport("win32", win32);

        const exe = b.addExecutable(.{ .name = name, .root_module = module });
        exe.linkLibC();
        exe.linkSystemLibrary("user32");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("shell32");

        const install = b.addInstallArtifact(exe, .{});
        step.dependOn(&install.step);

        var run_buf: [256]u8 = undefined;
        const run_name = std.fmt.bufPrint(&run_buf, "run-{s}", .{name}) catch continue;

        var desc_buf: [256]u8 = undefined;
        const run_desc = std.fmt.bufPrint(&desc_buf, "Run {s} example", .{name}) catch continue;

        const run = b.addRunArtifact(exe);
        run.step.dependOn(b.getInstallStep());
        b.step(run_name, run_desc).dependOn(&run.step);
    }
}

fn add_wasm(b: *std.Build, input_module: *std.Build.Module, common_module: *std.Build.Module) void {
    const step = b.step("wasm", "Build WASM visualizers");

    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .os_tag = .freestanding,
    });

    const wasm_common_module = b.createModule(.{
        .root_source_file = b.path("src/testing/dst/common/visualizer.zig"),
        .target = wasm_target,
        .optimize = .ReleaseSmall,
    });

    const visualizers = [_]struct {
        name: []const u8,
        path: []const u8,
        needs_input: bool,
    }{
        .{ .name = "input_visualizer", .path = "src/testing/dst/input/visualizer.zig", .needs_input = true },
        .{ .name = "stress_visualizer", .path = "src/testing/dst/stress/visualizer.zig", .needs_input = false },
        .{ .name = "hook_visualizer", .path = "src/testing/dst/hook/visualizer.zig", .needs_input = false },
    };

    for (visualizers) |viz| {
        const module = b.createModule(.{
            .root_source_file = b.path(viz.path),
            .target = wasm_target,
            .optimize = .ReleaseSmall,
        });
        module.addImport("common", wasm_common_module);
        if (viz.needs_input) {
            module.addImport("input", input_module);
        }

        const exe = b.addExecutable(.{ .name = viz.name, .root_module = module });
        exe.entry = .disabled;
        exe.rdynamic = true;

        step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    }

    _ = common_module;
}
