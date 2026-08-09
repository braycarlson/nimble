const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{});

const Key = nimble.Key;
const Response = nimble.Response;

const LoggingMiddleware = nimble.middleware.LoggingMiddleware;

const BlockListMiddlewareType = nimble.middleware.BlockListMiddlewareType;
const RemapMiddlewareType = nimble.middleware.RemapMiddlewareType;

fn report(label: []const u8, err: anyerror) void {
    std.debug.print("{s} failed: {s}\n", .{ label, @errorName(err) });
}

fn report_id(label: []const u8, err: anyerror) u32 {
    report(label, err);

    return 0;
}

const App = struct {
    keyboard: *Keyboard,
    logging: LoggingMiddleware,
    blocklist: BlockListMiddlewareType(8),
    remap: RemapMiddlewareType(8),

    fn init(kb: *Keyboard) App {
        return App{
            .keyboard = kb,
            .logging = LoggingMiddleware.init("nimble"),
            .blocklist = BlockListMiddlewareType(8).init(),
            .remap = RemapMiddlewareType(8).init(),
        };
    }

    fn setup(self: *App) void {
        _ = self.blocklist.add(.{ .key = .x, .modifiers = .{} }) catch |err|
            report_id("blocklist.add", err);

        _ = self.remap.add(.{
            .from_key = .j,
            .from_modifiers = .{},
            .to_key = .arrow_down,
            .to_modifiers = .{},
        }) catch |err| report_id("remap.add", err);

        _ = self.remap.add(.{
            .from_key = .k,
            .from_modifiers = .{},
            .to_key = .arrow_up,
            .to_modifiers = .{},
        }) catch |err| report_id("remap.add", err);
    }

    fn on_key(_: *App, key: *const Key) Response {
        std.debug.print("Key: {t}\n", .{key.value});

        return .pass;
    }

    fn on_toggle_logging(self: *App, _: *const Key) Response {
        if (self.logging.enabled) {
            self.logging.set_enabled(false);
            std.debug.print("Logging disabled\n", .{});
        } else {
            self.logging.set_enabled(true);
            std.debug.print("Logging enabled\n", .{});
        }

        return .consume;
    }

    fn on_toggle_blocklist(self: *App, _: *const Key) Response {
        if (self.blocklist.enabled) {
            self.blocklist.set_enabled(false);
            std.debug.print("Blocklist disabled\n", .{});
        } else {
            self.blocklist.set_enabled(true);
            std.debug.print("Blocklist enabled\n", .{});
        }

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

    app.setup();

    const keys = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

    inline for (keys) |key| {
        _ = try keyboard.bind(&[_]u8{key}).on(&app, App.on_key);
    }

    _ = try keyboard.bind("Alt+L").on(&app, App.on_toggle_logging);
    _ = try keyboard.bind("Alt+B").on(&app, App.on_toggle_blocklist);
    _ = try keyboard.bind("Alt+Q").on(&app, App.on_exit);

    std.debug.print("Middleware Example\n", .{});
    std.debug.print("==================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Features:\n", .{});
    std.debug.print("  'X' is blocked\n", .{});
    std.debug.print("  'J' becomes Down arrow\n", .{});
    std.debug.print("  'K' becomes Up arrow\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  Alt+L: Toggle logging\n", .{});
    std.debug.print("  Alt+B: Toggle blocklist\n", .{});
    std.debug.print("  Alt+Q: Exit\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();

    nimble.loop.run();
}
