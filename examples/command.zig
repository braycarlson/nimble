const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{
    .pass_injected = true,
});

const Key = nimble.Key;
const Response = nimble.Response;
const clipboard = nimble.clipboard;

fn report(label: []const u8, err: anyerror) void {
    std.debug.print("{s} failed: {s}\n", .{ label, @errorName(err) });
}

const App = struct {
    keyboard: *Keyboard,

    fn init(kb: *Keyboard) App {
        return App{
            .keyboard = kb,
        };
    }

    fn setup(self: *App) !void {
        _ = try self.keyboard.command("hello").on(self, on_hello);
        _ = try self.keyboard.command("sig").on(self, on_signature);
        _ = try self.keyboard.command("date").on(self, on_date);
        _ = try self.keyboard.command("exit").on(self, on_exit_cmd);
    }

    fn on_hello(_: *App, name: []const u8, _: []const u8) Response {
        clipboard.replace(@intCast(name.len + 1), "Hello, World!") catch |err|
            report("replace", err);

        return .consume;
    }

    fn on_signature(_: *App, name: []const u8, _: []const u8) Response {
        clipboard.replace(@intCast(name.len + 1), "Best regards,\r\nJohn Doe") catch |err|
            report("replace", err);

        return .consume;
    }

    fn on_date(_: *App, name: []const u8, _: []const u8) Response {
        clipboard.replace(@intCast(name.len + 1), "December 30, 2025") catch |err|
            report("replace", err);

        return .consume;
    }

    fn on_exit_cmd(_: *App, _: []const u8, _: []const u8) Response {
        nimble.loop.stop();

        return .consume;
    }

    fn on_quit(_: *App, _: *const Key) Response {
        nimble.loop.stop();

        return .consume;
    }
};

var keyboard: Keyboard = undefined;

pub fn main() !void {
    try nimble.runtime.open(.{ .mode = .grab });
    defer nimble.runtime.close();

    keyboard = Keyboard.init();
    defer keyboard.deinit();

    var app = App.init(&keyboard);

    try app.setup();

    _ = try keyboard.bind("Alt+Q").on(&app, App.on_quit);

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

    nimble.loop.run();
}
