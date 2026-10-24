const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{
    .binding_count_max = 32,
    .middleware_count_max = 3,
});

const Key = nimble.Key;
const Response = nimble.Response;

const LoggingMiddleware = nimble.middleware.LoggingMiddleware;

const BlockList = nimble.middleware.BlockListMiddlewareType(8);
const Remap = nimble.middleware.RemapMiddlewareType(8);

fn report(label: []const u8, err: anyerror) void {
    std.debug.print("{s} failed: {s}\n", .{ label, @errorName(err) });
}

const App = struct {
    keyboard: *Keyboard,
    logging: LoggingMiddleware,
    blocklist: BlockList,
    remap: Remap,

    fn init(kb: *Keyboard) App {
        return App{
            .keyboard = kb,
            .logging = LoggingMiddleware.init("nimble"),
            .blocklist = BlockList.init(),
            .remap = Remap.init(),
        };
    }

    fn setup(self: *App) !void {
        _ = self.blocklist.add(.{ .key = .x, .modifiers = .{} }) catch |err|
            report("blocklist.add", err);

        _ = self.remap.add(.{
            .from_key = .j,
            .from_modifiers = .{},
            .to_key = .arrow_down,
            .to_modifiers = .{},
        }) catch |err| report("remap.add", err);

        _ = self.remap.add(.{
            .from_key = .k,
            .from_modifiers = .{},
            .to_key = .arrow_up,
            .to_modifiers = .{},
        }) catch |err| report("remap.add", err);

        _ = try self.keyboard.add_middleware(LoggingMiddleware, &self.logging);
        _ = try self.keyboard.add_middleware(BlockList, &self.blocklist);
        _ = try self.keyboard.add_middleware(Remap, &self.remap);
    }

    fn on_key(_: *App, key: *const Key) Response {
        std.debug.print("Key: {t}\n", .{key.value});

        return .pass;
    }

    fn on_toggle_logging(self: *App, _: *const Key) Response {
        if (self.logging.is_enabled()) {
            self.logging.disable();
            std.debug.print("Logging disabled\n", .{});
        } else {
            self.logging.enable();
            std.debug.print("Logging enabled\n", .{});
        }

        return .consume;
    }

    fn on_toggle_blocklist(self: *App, _: *const Key) Response {
        if (self.blocklist.is_enabled()) {
            self.blocklist.disable();
            std.debug.print("Blocklist disabled\n", .{});
        } else {
            self.blocklist.enable();
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

pub fn main() !void {
    try nimble.runtime.open(.{ .mode = .grab });
    defer nimble.runtime.close();

    var keyboard: Keyboard = undefined;

    try keyboard.init(.{});
    defer keyboard.deinit();

    var app = App.init(&keyboard);

    try app.setup();

    const keys = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";

    inline for (keys) |key| {
        _ = try keyboard.bind(&[_]u8{key}).on(App, &app, App.on_key);
    }

    _ = try keyboard.bind("Down").on(App, &app, App.on_key);
    _ = try keyboard.bind("Up").on(App, &app, App.on_key);
    _ = try keyboard.bind("Alt+L").on(App, &app, App.on_toggle_logging);
    _ = try keyboard.bind("Alt+B").on(App, &app, App.on_toggle_blocklist);
    _ = try keyboard.bind("Alt+Q").on(App, &app, App.on_exit);

    std.debug.print("Middleware Example\n", .{});
    std.debug.print("==================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Features:\n", .{});
    std.debug.print("  'X' is blocked\n", .{});
    std.debug.print("  'J' reaches the bindings as Down\n", .{});
    std.debug.print("  'K' reaches the bindings as Up\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  Alt+L: Toggle logging\n", .{});
    std.debug.print("  Alt+B: Toggle blocklist\n", .{});
    std.debug.print("  Alt+Q: Exit\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();

    nimble.loop.run();
}
