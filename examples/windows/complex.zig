const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{});

const Key = nimble.Key;
const Response = nimble.Response;
const WindowFilter = nimble.WindowFilter;

const App = struct {
    fn on_action(_: *App, _: *const Key) Response {
        std.debug.print("Action triggered!\n", .{});

        return .consume;
    }

    fn on_quit(_: *App, _: *const Key) Response {
        std.debug.print("Exit\n", .{});

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

    var app = App{};

    const notepad = WindowFilter.for_class("Notepad");
    const chrome = WindowFilter.for_class("Chrome_WidgetWin_1");

    _ = try keyboard.bind("Ctrl+Shift+A").with_filter(notepad).on(&app, App.on_action);
    _ = try keyboard.bind("Ctrl+Shift+B").with_filter(chrome).on(&app, App.on_action);
    _ = try keyboard.bind("Alt+Q").on(&app, App.on_quit);

    std.debug.print("Complex Example\n", .{});
    std.debug.print("===============\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Window-specific bindings:\n", .{});
    std.debug.print("  Ctrl+Shift+A - Works only in Notepad\n", .{});
    std.debug.print("  Ctrl+Shift+B - Works only in Chrome\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Alt+Q: Exit (works anywhere)\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();

    nimble.loop.run();
}
