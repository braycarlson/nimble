const std = @import("std");

const device = @import("platform/linux/device.zig");
const nimble = @import("root.zig");

const assert = std.debug.assert;

const Keyboard = nimble.KeyboardType(.{});

const Drill = enum {
    probe,
    scan,
    synthesis,
    observe,
    grab,
};

const observe_iterations: u32 = 500;
const grab_iterations: u32 = 1000;
const poll_timeout_ms: u32 = 20;

const usage =
    \\usage: drill <probe|scan|synthesis|observe|grab>
    \\
    \\  probe      report which Linux input permissions are missing
    \\  scan       list and classify readable /dev/input devices
    \\  synthesis  open synthesis, then prove a rescan skips nimble's own devices
    \\  observe    run the event loop without grabbing, printing nothing it swallows
    \\  grab       grab every device, then release on both Shift keys held
    \\
;

var hook: Keyboard = undefined;

comptime {
    assert(observe_iterations > 0);
    assert(grab_iterations > observe_iterations);
}

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const arguments = try init.minimal.args.toSlice(arena);

    if (arguments.len != 2) {
        std.debug.print(usage, .{});

        return error.BadUsage;
    }

    const drill = std.meta.stringToEnum(Drill, arguments[1]) orelse {
        std.debug.print(usage, .{});

        return error.UnknownDrill;
    };

    switch (drill) {
        .probe => run_probe(),
        .scan => run_scan(),
        .synthesis => try run_synthesis(),
        .observe => try run_loop(.observe, observe_iterations),
        .grab => try run_loop(.grab, grab_iterations),
    }
}

fn run_probe() void {
    device.probe_permissions() catch |err| {
        std.debug.print("permissions: {t}\n", .{err});
        std.debug.print("see the Linux setup section of README.md\n", .{});

        return;
    };

    std.debug.print("permissions: ok\n", .{});
}

fn run_scan() void {
    var list = device.List{};

    device.scan(&list) catch |err| {
        std.debug.print("scan failed: {t}\n", .{err});

        return;
    };

    defer list.close_all();

    std.debug.print("devices: {d}\n", .{list.count});
    std.debug.print("  keyboards: {d}\n", .{list.count_of(.keyboard)});
    std.debug.print("  mice:      {d}\n", .{list.count_of(.mouse)});

    var index: u8 = 0;

    while (index < list.count) : (index += 1) {
        const entry = list.devices[index];

        std.debug.print("  {s} -> {t}\n", .{ entry.name(), entry.kind });
    }
}

fn run_synthesis() !void {
    nimble.runtime.open(.{ .mode = .observe, .synthesis = true }) catch |err| {
        std.debug.print("runtime.open failed: {t}\n", .{err});
        std.debug.print("see the Linux setup section of README.md\n", .{});

        return;
    };

    defer nimble.runtime.close();

    var list = device.List{};

    device.scan(&list) catch |err| {
        std.debug.print("scan failed: {t}\n", .{err});

        return error.ScanFailed;
    };

    defer list.close_all();

    var index: u8 = 0;
    var own: u8 = 0;

    while (index < list.count) : (index += 1) {
        if (device.origin_of(list.devices[index].fd) == .own) {
            own += 1;

            std.debug.print("  leaked own device: {s}\n", .{list.devices[index].name()});
        }
    }

    std.debug.print("synthesis open, rescan saw {d} devices, {d} of them ours\n", .{
        list.count,
        own,
    });

    if (own != 0) {
        return error.SelfCapture;
    }

    std.debug.print("scan excludes nimble's own devices\n", .{});
}

fn run_loop(mode: nimble.Mode, iterations: u32) !void {
    nimble.runtime.open(.{ .mode = mode }) catch |err| {
        std.debug.print("runtime.open failed: {t}\n", .{err});
        std.debug.print("see the Linux setup section of README.md\n", .{});

        return;
    };

    defer nimble.runtime.close();

    hook = Keyboard.init();
    defer hook.deinit();

    try hook.start();

    std.debug.print("loop running, mode={t}\n", .{nimble.runtime.mode()});

    if (mode == .grab) {
        std.debug.print("hold both Shift keys for two seconds to release\n", .{});
    }

    var iteration: u32 = 0;

    while (iteration < iterations) : (iteration += 1) {
        if (!nimble.loop.poll(poll_timeout_ms)) {
            break;
        }

        if (mode == .grab and nimble.runtime.mode() == .observe) {
            std.debug.print("rescue fired, devices released\n", .{});

            break;
        }
    }

    std.debug.print("loop finished after {d} polls\n", .{iteration});
}
