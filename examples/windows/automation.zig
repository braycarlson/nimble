const std = @import("std");
const nimble = @import("nimble");
const Keyboard = nimble.KeyboardType(.{ .binding_count_max = 4, .macro_count_max = 3 });
const Key = nimble.Key;
const Response = nimble.Response;
const WindowFilter = nimble.WindowFilter;

const App = struct {
    runtime: *nimble.Runtime,
    keyboard: *Keyboard,

    fn init(runtime: *nimble.Runtime, kb: *Keyboard) App {
        return App{ .runtime = runtime, .keyboard = kb };
    }

    fn setup(self: *App) !void {
        const notepad = WindowFilter.for_class("Notepad");

        _ = try self.keyboard.macro("signature")
            .line("Best regards,")
            .line("John Doe")
            .line("Software Engineer")
            .text("john.doe@example.com")
            .bind("Ctrl+Shift+S")
            .with_filter(notepad)
            .create();

        _ = try self.keyboard.macro("meeting")
            .text(
                \\=====================================
                \\  MEETING NOTES
                \\=====================================
                \\
                \\Date:
                \\Attendees:
                \\Agenda:
                \\
                \\Notes:
            )
            .bind("Ctrl+Shift+M")
            .with_filter(notepad)
            .create();

        _ = try self.keyboard.macro("timestamp")
            .text("[2024-12-29 10:30:00] ")
            .bind("Ctrl+Shift+I")
            .with_filter(notepad)
            .create();
    }

    fn on_exit(app: *App, _: *const Key) Response {
        app.runtime.stop();

        return .consume;
    }
};

pub fn main() !void {
    var runtime: nimble.Runtime = undefined;

    try runtime.init(.{ .mode = .grab });
    defer runtime.deinit();

    var keyboard: Keyboard = undefined;

    try keyboard.init(&runtime, .{ .pass_injected = true });
    defer keyboard.deinit();

    var app = App.init(&runtime, &keyboard);

    try app.setup();

    _ = try keyboard.bind("Alt+Q").on(App, &app, App.on_exit);

    std.debug.print("Automation Example (Notepad Only)\n", .{});
    std.debug.print("=================================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Macros:\n", .{});
    std.debug.print("  Ctrl+Shift+S  Insert email signature\n", .{});
    std.debug.print("  Ctrl+Shift+M  Insert meeting template\n", .{});
    std.debug.print("  Ctrl+Shift+I  Insert timestamp\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Alt+Q         Exit\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();

    runtime.run();
}
