const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{
    .pass_injected = true,
});

const Mouse = nimble.MouseType(.{});

const Key = nimble.Key;
const MouseEvent = nimble.MouseEvent;
const Response = nimble.Response;

fn report(label: []const u8, err: anyerror) void {
    std.debug.print("{s} failed: {s}\n", .{ label, @errorName(err) });
}

fn report_id(label: []const u8, err: anyerror) u32 {
    report(label, err);

    return 0;
}

const App = struct {
    keyboard: *Keyboard,
    mouse: *Mouse,
    click_count: u32 = 0,

    fn on_ctrl_a(_: *App, _: *const Key) Response {
        std.debug.print("Ctrl+A\n", .{});

        return .consume;
    }

    fn on_ctrl_shift_b(_: *App, _: *const Key) Response {
        std.debug.print("Ctrl+Shift+B\n", .{});

        return .consume;
    }

    fn on_type_hello(self: *App, _: *const Key) Response {
        _ = nimble.simulate.text.send("Hello, World!") catch |err| report_id("send", err);

        _ = self;

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
        _ = nimble.simulate.text.send("Hello from command!") catch |err| report_id("send", err);

        return .consume;
    }

    fn on_left_click(self: *App, event: *const MouseEvent) Response {
        self.click_count += 1;

        const position = event.position() orelse nimble.MousePosition.init(0, 0);

        std.debug.print("Left click #{d} at ({d}, {d})\n", .{
            self.click_count,
            position.x,
            position.y,
        });

        return .pass;
    }

    fn on_right_click(_: *App, event: *const MouseEvent) Response {
        const position = event.position() orelse nimble.MousePosition.init(0, 0);

        std.debug.print("Right click at ({d}, {d})\n", .{ position.x, position.y });

        return .pass;
    }

    fn on_center_mouse(self: *App, _: *const Key) Response {
        _ = self.mouse.center();

        std.debug.print("Mouse centered\n", .{});

        return .consume;
    }

    fn on_exit(_: *App, _: *const Key) Response {
        std.debug.print("Exit\n", .{});

        nimble.loop.stop();

        return .consume;
    }
};

var keyboard: Keyboard = undefined;
var mouse: Mouse = undefined;

pub fn main() !void {
    try nimble.runtime.open(.{ .mode = .grab });
    defer nimble.runtime.close();

    keyboard = Keyboard.init();
    mouse = Mouse.init();
    defer keyboard.deinit();
    defer mouse.deinit();

    var app = App{
        .keyboard = &keyboard,
        .mouse = &mouse,
    };

    _ = try keyboard.bind("Ctrl+A").on(&app, App.on_ctrl_a);
    _ = try keyboard.bind("Ctrl+Shift+B").on(&app, App.on_ctrl_shift_b);
    _ = try keyboard.bind("Ctrl+1").on(&app, App.on_type_hello);
    _ = try keyboard.bind("Ctrl+2").on(&app, App.on_paste_signature);
    _ = try keyboard.bind("Ctrl+M").on(&app, App.on_center_mouse);

    _ = try keyboard.chord("ABC").on(&app, App.on_chord_abc);
    _ = try keyboard.command("hello").on(&app, App.on_command_hello);

    _ = try mouse.bind(.left_down).on(&app, App.on_left_click);
    _ = try mouse.bind(.right_down).on(&app, App.on_right_click);

    _ = try keyboard.bind("Alt+Q").on(&app, App.on_exit);

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
