const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{
    .binding_count_max = 8,
    .chord_count_max = 1,
    .command_count_max = 1,
});

const Mouse = nimble.MouseType(.{ .binding_count_max = 2 });

const Key = nimble.Key;
const MouseEvent = nimble.MouseEvent;
const Response = nimble.Response;

fn report(label: []const u8, err: anyerror) void {
    std.debug.print("{s} failed: {s}\n", .{ label, @errorName(err) });
}

const App = struct {
    click_count: u32 = 0,

    fn on_ctrl_a(_: *App, _: *const Key) Response {
        std.debug.print("Ctrl+A\n", .{});

        return .consume;
    }

    fn on_ctrl_shift_b(_: *App, _: *const Key) Response {
        std.debug.print("Ctrl+Shift+B\n", .{});

        return .consume;
    }

    fn on_type_hello(_: *App, _: *const Key) Response {
        _ = nimble.simulate.text.send("Hello, World!") catch |err| report("send", err);

        return .consume;
    }

    fn on_paste_signature(_: *App, _: *const Key) Response {
        nimble.clipboard.set("Best regards,\r\nJohn Doe") catch |err| report("set", err);
        _ = nimble.clipboard.paste();

        return .consume;
    }

    fn on_chord_abc(_: *App) Response {
        std.debug.print("Chord: ABC triggered!\n", .{});

        return .consume;
    }

    fn on_command_hello(_: *App, _: []const u8, _: []const u8) Response {
        _ = nimble.simulate.text.send("Hello from command!") catch |err| report("send", err);

        return .consume;
    }

    fn on_left_click(app: *App, event: *const MouseEvent) Response {
        app.click_count += 1;

        const position = event.position() orelse nimble.Position.zero;

        std.debug.print("Left click #{d} at ({d}, {d})\n", .{
            app.click_count,
            position.x,
            position.y,
        });

        return .pass;
    }

    fn on_right_click(_: *App, event: *const MouseEvent) Response {
        const position = event.position() orelse nimble.Position.zero;

        std.debug.print("Right click at ({d}, {d})\n", .{ position.x, position.y });

        return .pass;
    }

    fn on_center_mouse(_: *App, _: *const Key) Response {
        var monitors: nimble.Monitor.List = undefined;

        monitors.enumerate();

        const primary = monitors.primary() orelse return .consume;

        _ = nimble.simulate.mouse.move_to(primary.center());

        std.debug.print("Mouse centered\n", .{});

        return .consume;
    }

    fn on_exit(_: *App, _: *const Key) Response {
        std.debug.print("Exit\n", .{});

        nimble.loop.stop();

        return .consume;
    }
};

pub fn main(init: std.process.Init) !void {
    try nimble.runtime.open(.{
        .mode = .grab,
        .wayland_display = init.environ_map.get("WAYLAND_DISPLAY"),
        .xdg_runtime_dir = init.environ_map.get("XDG_RUNTIME_DIR"),
    });

    defer nimble.runtime.close();

    var keyboard: Keyboard = undefined;

    try keyboard.init(.{ .pass_injected = true });
    defer keyboard.deinit();

    var mouse: Mouse = undefined;

    mouse.init(.{});
    defer mouse.deinit();

    var app = App{};

    _ = try keyboard.bind("Ctrl+A").on(App, &app, App.on_ctrl_a);
    _ = try keyboard.bind("Ctrl+Shift+B").on(App, &app, App.on_ctrl_shift_b);
    _ = try keyboard.bind("Ctrl+1").on(App, &app, App.on_type_hello);
    _ = try keyboard.bind("Ctrl+2").on(App, &app, App.on_paste_signature);
    _ = try keyboard.bind("Ctrl+M").on(App, &app, App.on_center_mouse);

    _ = try keyboard.chord(&.{ .a, .b, .c }).on(App, &app, App.on_chord_abc);
    _ = try keyboard.command("hello").on(App, &app, App.on_command_hello);

    _ = try mouse.bind(.left_down).on(App, &app, App.on_left_click);
    _ = try mouse.bind(.right_down).on(App, &app, App.on_right_click);

    _ = try keyboard.bind("Alt+Q").on(App, &app, App.on_exit);

    std.debug.print("Simple Example\n", .{});
    std.debug.print("==============\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Keyboard:\n", .{});
    std.debug.print("  Ctrl+A                - Log message\n", .{});
    std.debug.print("  Ctrl+Shift+B          - Log message\n", .{});
    std.debug.print("  Ctrl+1                - Type 'Hello, World!'\n", .{});
    std.debug.print("  Ctrl+2                - Paste signature\n", .{});
    std.debug.print("  Ctrl+M                - Center mouse\n", .{});
    std.debug.print("  ABC (chord)           - Chord trigger\n", .{});
    std.debug.print("  :hello + Enter        - Command\n", .{});
    std.debug.print("  Alt+Q                 - Exit\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Mouse:\n", .{});
    std.debug.print("  Left/Right click      - Log position\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();
    try mouse.start();

    nimble.loop.run();
}
