const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{});

const Key = nimble.Key;
const Response = nimble.Response;
const WindowFilter = nimble.WindowFilter;

const App = struct {
    fn on_notepad_only(_: *App, _: *const Key) Response {
        std.debug.print("Ctrl+1: Notepad only!\n", .{});

        return .consume;
    }

    fn on_exclude_notepad(_: *App, _: *const Key) Response {
        std.debug.print("Ctrl+2: Everywhere except Notepad!\n", .{});

        return .consume;
    }

    fn on_title_match(_: *App, _: *const Key) Response {
        std.debug.print("Ctrl+3: Window title contains 'Untitled'!\n", .{});

        return .consume;
    }

    fn on_global(_: *App, _: *const Key) Response {
        std.debug.print("Ctrl+4: Global (no filter)!\n", .{});

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

    const notepad = WindowFilter.for_class("Notepad");
    const other = WindowFilter.exclude_class("Notepad");
    const untitled = WindowFilter.for_title("Untitled");

    _ = try keyboard.bind("Ctrl+1").with_filter(notepad).on(&app, App.on_notepad_only);
    _ = try keyboard.bind("Ctrl+2").with_filter(other).on(&app, App.on_exclude_notepad);
    _ = try keyboard.bind("Ctrl+3").with_filter(untitled).on(&app, App.on_title_match);
    _ = try keyboard.bind("Ctrl+4").on(&app, App.on_global);
    _ = try keyboard.bind("Alt+Q").on(&app, App.on_exit);

    std.debug.print("App Filter Example\n", .{});
    std.debug.print("==================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Open Notepad and try these:\n", .{});
    std.debug.print("  Ctrl+1: Only works in Notepad\n", .{});
    std.debug.print("  Ctrl+2: Works everywhere EXCEPT Notepad\n", .{});
    std.debug.print("  Ctrl+3: Only works if title contains 'Untitled'\n", .{});
    std.debug.print("  Ctrl+4: Works everywhere (no filter)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Alt+Q: Exit\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();

    nimble.loop.run();
}
