const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{
    .pass_injected = true,
});

const Key = nimble.Key;
const Response = nimble.Response;
const WindowFilter = nimble.WindowFilter;

fn report(label: []const u8, err: anyerror) void {
    std.debug.print("{s} failed: {s}\n", .{ label, @errorName(err) });
}

const App = struct {
    keyboard: *Keyboard,
    signature_id: u32 = 0,
    meeting_id: u32 = 0,
    timestamp_id: u32 = 0,

    fn init(kb: *Keyboard) App {
        return App{
            .keyboard = kb,
        };
    }

    fn setup(self: *App) !void {
        self.signature_id = try self.keyboard.macro_builder("signature")
            .line("Best regards,")
            .line("John Doe")
            .line("Software Engineer")
            .text("john.doe@example.com")
            .create();

        self.meeting_id = try self.keyboard.macro_builder("meeting")
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
            .create();

        self.timestamp_id = try self.keyboard.macro_builder("timestamp")
            .text("[2024-12-29 10:30:00] ")
            .create();
    }

    fn on_signature(self: *App, _: *const Key) Response {
        self.keyboard.macro_registry.play(self.signature_id) catch |err| report("play", err);

        return .consume;
    }

    fn on_meeting(self: *App, _: *const Key) Response {
        self.keyboard.macro_registry.play(self.meeting_id) catch |err| report("play", err);

        return .consume;
    }

    fn on_timestamp(self: *App, _: *const Key) Response {
        self.keyboard.macro_registry.play(self.timestamp_id) catch |err| report("play", err);

        return .consume;
    }

    fn on_exit(self: *App, _: *const Key) Response {
        self.keyboard.repeat_registry.stop_all();
        self.keyboard.macro_registry.stop();

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

    const notepad = WindowFilter.for_class("Notepad");

    _ = try keyboard.bind("Ctrl+Shift+S").with_filter(notepad).on(&app, App.on_signature);
    _ = try keyboard.bind("Ctrl+Shift+M").with_filter(notepad).on(&app, App.on_meeting);
    _ = try keyboard.bind("Ctrl+Shift+I").with_filter(notepad).on(&app, App.on_timestamp);
    _ = try keyboard.bind("Alt+Q").on(&app, App.on_exit);

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

    nimble.loop.run();
}
