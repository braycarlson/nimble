const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{
    .pass_injected = true,
});

const Key = nimble.Key;
const Response = nimble.Response;

const text = nimble.simulate.text;
const clipboard = nimble.clipboard;

fn report(label: []const u8, err: anyerror) void {
    std.debug.print("{s} failed: {s}\n", .{ label, @errorName(err) });
}

fn report_id(label: []const u8, err: anyerror) u32 {
    report(label, err);

    return 0;
}

const App = struct {
    keyboard: *Keyboard,

    fn init(kb: *Keyboard) App {
        return App{
            .keyboard = kb,
        };
    }

    fn on_paste_hello(_: *App, _: *const Key) Response {
        std.debug.print("Pasting: Hello, World!\n", .{});

        clipboard.set("Hello, World!") catch |err| report("set", err);
        _ = clipboard.paste();

        return .consume;
    }

    fn on_paste_email(_: *App, _: *const Key) Response {
        std.debug.print("Pasting: email template\n", .{});

        const email = "Dear Sir/Madam,\r\n\r\nThank you for your inquiry.\r\n\r\nBest regards,";

        clipboard.set(email) catch |err| report("set", err);
        _ = clipboard.paste();

        return .consume;
    }

    fn on_paste_code(_: *App, _: *const Key) Response {
        std.debug.print("Pasting: code snippet\n", .{});

        const snippet = "fn main() void {\r\n    std.debug.print(\"Hello!\");\r\n}";

        clipboard.set(snippet) catch |err| report("set", err);
        _ = clipboard.paste();

        return .consume;
    }

    fn on_type_hello(_: *App, _: *const Key) Response {
        std.debug.print("Typing: Hello, World!\n", .{});

        _ = text.send("Hello, World!") catch |err| report_id("send", err);

        return .consume;
    }

    fn on_type_email(_: *App, _: *const Key) Response {
        std.debug.print("Typing: email template\n", .{});

        const email = "Dear Sir/Madam,\n\nThank you for your inquiry.\n\nBest regards,";

        _ = text.send(email) catch |err| report_id("send", err);

        return .consume;
    }

    fn on_type_slow(_: *App, _: *const Key) Response {
        std.debug.print("Typing slowly...\n", .{});

        const greeting = "Hello, World!";

        _ = text.send_with_delay(greeting, 100) catch |err| report_id("send_with_delay", err);

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

    var app = App.init(&keyboard);

    _ = try keyboard.bind("Ctrl+1").on(&app, App.on_paste_hello);
    _ = try keyboard.bind("Ctrl+2").on(&app, App.on_paste_email);
    _ = try keyboard.bind("Ctrl+3").on(&app, App.on_paste_code);

    _ = try keyboard.bind("Ctrl+Shift+1").on(&app, App.on_type_hello);
    _ = try keyboard.bind("Ctrl+Shift+2").on(&app, App.on_type_email);
    _ = try keyboard.bind("Ctrl+Shift+3").on(&app, App.on_type_slow);

    _ = try keyboard.bind("Alt+Q").on(&app, App.on_exit);

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

    nimble.loop.run();
}
