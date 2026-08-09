const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{});

const Key = nimble.Key;
const Response = nimble.Response;
const WindowFilter = nimble.WindowFilter;

const App = struct {
    fn on_notepad_save(_: *App, _: *const Key) Response {
        std.debug.print("Notepad: Save\n", .{});

        return .consume;
    }

    fn on_notepad_open(_: *App, _: *const Key) Response {
        std.debug.print("Notepad: Open\n", .{});

        return .consume;
    }

    fn on_notepad_new(_: *App, _: *const Key) Response {
        std.debug.print("Notepad: New\n", .{});

        return .consume;
    }

    fn on_windowed_action(_: *App, _: *const Key) Response {
        std.debug.print("Windowed: Action (disabled in fullscreen)\n", .{});

        return .consume;
    }

    fn on_fullscreen_exit(_: *App, _: *const Key) Response {
        std.debug.print("Fullscreen: Exit fullscreen action\n", .{});

        return .consume;
    }

    fn on_global(_: *App, _: *const Key) Response {
        std.debug.print("Global: Works everywhere\n", .{});

        return .consume;
    }

    fn on_exit(_: *App, _: *const Key) Response {
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

    var notepad = keyboard.group().with_filter(WindowFilter.for_class("Notepad"));

    _ = try notepad.bind("Ctrl+S").on(&app, App.on_notepad_save);
    _ = try notepad.bind("Ctrl+O").on(&app, App.on_notepad_open);
    _ = try notepad.bind("Ctrl+N").on(&app, App.on_notepad_new);

    var windowed = keyboard.group().with_filter(WindowFilter.init().windowed());

    _ = try windowed.bind("Ctrl+1").on(&app, App.on_windowed_action);
    _ = try windowed.bind("Ctrl+2").on(&app, App.on_windowed_action);
    _ = try windowed.bind("Ctrl+3").on(&app, App.on_windowed_action);

    var fullscreen = keyboard.group().with_filter(WindowFilter.init().fullscreen());

    _ = try fullscreen.bind("Ctrl+Escape").on(&app, App.on_fullscreen_exit);

    _ = try keyboard.bind("Ctrl+G").on(&app, App.on_global);
    _ = try keyboard.bind("Alt+Q").on(&app, App.on_exit);

    std.debug.print("Group Builder Example\n", .{});
    std.debug.print("=====================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Notepad only:\n", .{});
    std.debug.print("  Ctrl+S, Ctrl+O, Ctrl+N\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Windowed only (disabled in fullscreen):\n", .{});
    std.debug.print("  Ctrl+1, Ctrl+2, Ctrl+3\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Fullscreen only:\n", .{});
    std.debug.print("  Ctrl+Escape\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Global:\n", .{});
    std.debug.print("  Ctrl+G: Works everywhere\n", .{});
    std.debug.print("  Alt+Q: Exit\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();

    nimble.loop.run();
}
