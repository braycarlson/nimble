const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{ .binding_count_max = 7 });

const Key = nimble.Key;
const Response = nimble.Response;

fn report(label: []const u8, err: anyerror) void {
    std.debug.print("{s} failed: {s}\n", .{ label, @errorName(err) });
}

const App = struct {
    runtime: *nimble.Runtime,
    slow_active: std.atomic.Value(bool) = .init(false),
    slow_thread: ?std.Thread = null,

    fn on_paste_hello(app: *App, _: *const Key) Response {
        std.debug.print("Pasting: Hello, World!\n", .{});

        app.runtime.clipboard_set("Hello, World!") catch |err| report("set", err);
        _ = app.runtime.clipboard_paste();

        return .consume;
    }

    fn on_paste_email(app: *App, _: *const Key) Response {
        std.debug.print("Pasting: email template\n", .{});

        const email = "Dear Sir/Madam,\r\n\r\nThank you for your inquiry.\r\n\r\nBest regards,";

        app.runtime.clipboard_set(email) catch |err| report("set", err);
        _ = app.runtime.clipboard_paste();

        return .consume;
    }

    fn on_paste_code(app: *App, _: *const Key) Response {
        std.debug.print("Pasting: code snippet\n", .{});

        const snippet = "fn main() void {\r\n    std.debug.print(\"Hello!\");\r\n}";

        app.runtime.clipboard_set(snippet) catch |err| report("set", err);
        _ = app.runtime.clipboard_paste();

        return .consume;
    }

    fn on_type_hello(app: *App, _: *const Key) Response {
        std.debug.print("Typing: Hello, World!\n", .{});

        _ = app.runtime.text_send("Hello, World!") catch |err| report("send", err);

        return .consume;
    }

    fn on_type_email(app: *App, _: *const Key) Response {
        std.debug.print("Typing: email template\n", .{});

        const email = "Dear Sir/Madam,\n\nThank you for your inquiry.\n\nBest regards,";

        _ = app.runtime.text_send(email) catch |err| report("send", err);

        return .consume;
    }

    fn on_type_slow(app: *App, _: *const Key) Response {
        if (app.slow_active.load(.acquire)) {
            return .consume;
        }

        app.join_slow();
        app.slow_active.store(true, .release);

        app.slow_thread = std.Thread.spawn(.{}, type_slow, .{app}) catch |err| {
            app.slow_active.store(false, .release);
            report("spawn", err);

            return .consume;
        };

        std.debug.print("Typing slowly...\n", .{});

        return .consume;
    }

    fn type_slow(app: *App) void {
        defer app.slow_active.store(false, .release);

        const greeting = "Hello, World!";
        const sent = app.runtime.text_send_with_delay(greeting, 100);

        _ = sent catch |err| report("send_with_delay", err);
    }

    fn join_slow(app: *App) void {
        const thread = app.slow_thread orelse return;

        thread.join();
        app.slow_thread = null;
    }

    fn on_exit(app: *App, _: *const Key) Response {
        std.debug.print("Exit\n", .{});

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

    var app = App{ .runtime = &runtime };
    defer app.join_slow();

    _ = try keyboard.bind("Ctrl+1").on(App, &app, App.on_paste_hello);
    _ = try keyboard.bind("Ctrl+2").on(App, &app, App.on_paste_email);
    _ = try keyboard.bind("Ctrl+3").on(App, &app, App.on_paste_code);

    _ = try keyboard.bind("Ctrl+Shift+1").on(App, &app, App.on_type_hello);
    _ = try keyboard.bind("Ctrl+Shift+2").on(App, &app, App.on_type_email);
    _ = try keyboard.bind("Ctrl+Shift+3").on(App, &app, App.on_type_slow);

    _ = try keyboard.bind("Alt+Q").on(App, &app, App.on_exit);

    std.debug.print("Typer Example\n", .{});
    std.debug.print("=============\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Open a text editor and try:\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Clipboard (instant paste):\n", .{});
    std.debug.print("  Ctrl+1: Paste 'Hello, World!'\n", .{});
    std.debug.print("  Ctrl+2: Paste email template\n", .{});
    std.debug.print("  Ctrl+3: Paste code snippet\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Typer (character by character):\n", .{});
    std.debug.print("  Ctrl+Shift+1: Type 'Hello, World!'\n", .{});
    std.debug.print("  Ctrl+Shift+2: Type email template\n", .{});
    std.debug.print("  Ctrl+Shift+3: Type slowly (100ms delay)\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Alt+Q: Exit\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();

    runtime.run();
}
