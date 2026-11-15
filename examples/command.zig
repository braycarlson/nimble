const std = @import("std");
const nimble = @import("nimble");

const assert = std.debug.assert;
const Keyboard = nimble.KeyboardType(.{ .binding_count_max = 1, .command_count_max = 4 });
const Key = nimble.Key;
const Response = nimble.Response;

fn report(label: []const u8, err: anyerror) void {
    std.debug.print("{s} failed: {s}\n", .{ label, @errorName(err) });
}

const App = struct {
    runtime: *nimble.Runtime,
    keyboard: *Keyboard,

    fn init(runtime: *nimble.Runtime, kb: *Keyboard) App {
        return App{ .runtime = runtime, .keyboard = kb };
    }

    fn setup(self: *App) !void {
        _ = try self.keyboard.command("hello").on(App, self, on_hello);
        _ = try self.keyboard.command("sig").on(App, self, on_signature);
        _ = try self.keyboard.command("date").on(App, self, on_date);
        _ = try self.keyboard.command("exit").on(App, self, on_exit_cmd);
    }

    fn on_hello(app: *App, name: []const u8, _: []const u8) Response {
        assert(name.len > 0);

        app.runtime.clipboard_replace(@intCast(name.len + 1), "Hello, World!") catch |err|
            report("replace", err);

        return .consume;
    }

    fn on_signature(app: *App, name: []const u8, _: []const u8) Response {
        assert(name.len > 0);

        const signature = "Best regards,\r\nJohn Doe";

        app.runtime.clipboard_replace(@intCast(name.len + 1), signature) catch |err|
            report("replace", err);

        return .consume;
    }

    fn on_date(app: *App, name: []const u8, _: []const u8) Response {
        assert(name.len > 0);

        app.runtime.clipboard_replace(@intCast(name.len + 1), "December 30, 2025") catch |err|
            report("replace", err);

        return .consume;
    }

    fn on_exit_cmd(app: *App, _: []const u8, _: []const u8) Response {
        app.runtime.stop();

        return .consume;
    }

    fn on_quit(app: *App, _: *const Key) Response {
        app.runtime.stop();

        return .consume;
    }
};

pub fn main(init: std.process.Init) !void {
    var runtime: nimble.Runtime = undefined;

    try runtime.init(.{
        .mode = .grab,
        .wayland_display = init.environ_map.get("WAYLAND_DISPLAY"),
        .xdg_runtime_dir = init.environ_map.get("XDG_RUNTIME_DIR"),
    });

    defer runtime.deinit();

    var keyboard: Keyboard = undefined;

    try keyboard.init(&runtime, .{ .pass_injected = true });
    defer keyboard.deinit();

    var app = App.init(&runtime, &keyboard);

    try app.setup();

    _ = try keyboard.bind("Alt+Q").on(App, &app, App.on_quit);

    std.debug.print("Text Expansion Example\n", .{});
    std.debug.print("======================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Type in any text field:\n", .{});
    std.debug.print("  :hello   - Expands to 'Hello, World!'\n", .{});
    std.debug.print("  :sig     - Expands to signature\n", .{});
    std.debug.print("  :date    - Expands to current date\n", .{});
    std.debug.print("  :exit    - Exit the application\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Alt+Q: Exit\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();

    runtime.run();
}
