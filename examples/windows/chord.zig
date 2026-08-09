const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{});

const Key = nimble.Key;
const Response = nimble.Response;
const WindowFilter = nimble.WindowFilter;

const App = struct {
    keyboard: *Keyboard,

    fn init(kb: *Keyboard) App {
        return App{
            .keyboard = kb,
        };
    }

    fn setup(self: *App) !void {
        const notepad = WindowFilter.for_class("Notepad");

        _ = try self.keyboard.chord("ABC").timeout(1000).with_filter(notepad).on(self, on_abc);
        _ = try self.keyboard.chord("QQ").timeout(500).with_filter(notepad).on(self, on_qq);
        _ = try self.keyboard.chord("JKL").timeout(1000).with_filter(notepad).on(self, on_jkl);
        _ = try self.keyboard.chord("UNLOCK")
            .timeout(2000)
            .with_filter(notepad)
            .on(self, on_unlock);
        _ = try self.keyboard.chord("ZZ").timeout(500).with_filter(notepad).on(self, on_exit_chord);
    }

    fn on_abc(_: *App) Response {
        std.debug.print("Chord: ABC triggered!\n", .{});

        return .consume;
    }

    fn on_qq(_: *App) Response {
        std.debug.print("Chord: QQ triggered!\n", .{});

        return .consume;
    }

    fn on_jkl(_: *App) Response {
        std.debug.print("Chord: JKL triggered!\n", .{});

        return .consume;
    }

    fn on_unlock(_: *App) Response {
        std.debug.print("Chord: UNLOCK triggered! Secret unlocked!\n", .{});

        return .consume;
    }

    fn on_exit_chord(_: *App) Response {
        std.debug.print("Chord: ZZ - Exiting!\n", .{});

        nimble.loop.stop();

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

    var app = App.init(&keyboard);

    try app.setup();

    _ = try keyboard.bind("Alt+Q").on(&app, App.on_quit);

    std.debug.print("Chord Example (Notepad Only)\n", .{});
    std.debug.print("============================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Chords only work in Notepad!\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Type key sequences quickly:\n", .{});
    std.debug.print("  A B C    - Triggers ABC chord (1 second timeout)\n", .{});
    std.debug.print("  Q Q      - Triggers QQ chord (500ms timeout)\n", .{});
    std.debug.print("  J K L    - Triggers JKL chord (1 second timeout)\n", .{});
    std.debug.print("  U N L O C K - Triggers UNLOCK chord (2 second timeout)\n", .{});
    std.debug.print("  Z Z      - Exit via chord\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Alt+Q: Exit (works anywhere)\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();

    nimble.loop.run();
}
