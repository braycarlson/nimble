const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{ .binding_count_max = 3 });

const Key = nimble.Key;
const Response = nimble.Response;
const WindowFilter = nimble.WindowFilter;

const App = struct {
    runtime: *nimble.Runtime,

    fn on_action(_: *App, _: *const Key) Response {
        std.debug.print("Action triggered!\n", .{});

        return .consume;
    }

    fn on_quit(app: *App, _: *const Key) Response {
        std.debug.print("Exit\n", .{});

        app.runtime.stop();

        return .consume;
    }
};

pub fn main() !void {
    var runtime: nimble.Runtime = undefined;

    try runtime.init(.{ .mode = .grab });
    defer runtime.deinit();

    var keyboard: Keyboard = undefined;

    try keyboard.init(&runtime, .{});
    defer keyboard.deinit();

    var app = App{ .runtime = &runtime };

    const notepad = WindowFilter.for_class("Notepad");
    const chrome = WindowFilter.for_class("Chrome_WidgetWin_1");

    _ = try keyboard.bind("Ctrl+Shift+A").with_filter(notepad).on(App, &app, App.on_action);
    _ = try keyboard.bind("Ctrl+Shift+B").with_filter(chrome).on(App, &app, App.on_action);
    _ = try keyboard.bind("Alt+Q").on(App, &app, App.on_quit);

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

    runtime.run();
}
