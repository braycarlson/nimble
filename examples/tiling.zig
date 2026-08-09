const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{});

const Key = nimble.Key;
const Response = nimble.Response;

const Tiler = struct {
    fn on_tile_left(_: *Tiler, _: *const Key) Response {
        std.debug.print("Tile left\n", .{});

        return .consume;
    }

    fn on_tile_right(_: *Tiler, _: *const Key) Response {
        std.debug.print("Tile right\n", .{});

        return .consume;
    }

    fn on_focus_down(_: *Tiler, _: *const Key) Response {
        std.debug.print("Focus down\n", .{});

        return .consume;
    }

    fn on_focus_up(_: *Tiler, _: *const Key) Response {
        std.debug.print("Focus up\n", .{});

        return .consume;
    }

    fn on_toggle_fullscreen(_: *Tiler, _: *const Key) Response {
        std.debug.print("Fullscreen\n", .{});

        return .consume;
    }

    fn on_close_window(_: *Tiler, _: *const Key) Response {
        std.debug.print("Close\n", .{});

        return .consume;
    }

    fn on_reload(_: *Tiler, _: *const Key) Response {
        std.debug.print("Reload\n", .{});

        return .consume;
    }

    fn on_exit(_: *Tiler, _: *const Key) Response {
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

    var tiler = Tiler{};

    _ = try keyboard.bind("Win+H").on(&tiler, Tiler.on_tile_left);
    _ = try keyboard.bind("Win+L").on(&tiler, Tiler.on_tile_right);
    _ = try keyboard.bind("Win+J").on(&tiler, Tiler.on_focus_down);
    _ = try keyboard.bind("Win+K").on(&tiler, Tiler.on_focus_up);
    _ = try keyboard.bind("Win+F").on(&tiler, Tiler.on_toggle_fullscreen);
    _ = try keyboard.bind("Win+Shift+Q").on(&tiler, Tiler.on_close_window);
    _ = try keyboard.bind("Win+Shift+R").on(&tiler, Tiler.on_reload);
    _ = try keyboard.bind("Alt+Q").on(&tiler, Tiler.on_exit);

    std.debug.print("Tiling Window Manager Example\n", .{});
    std.debug.print("=============================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  Win+H: Tile left\n", .{});
    std.debug.print("  Win+L: Tile right\n", .{});
    std.debug.print("  Win+J: Focus down\n", .{});
    std.debug.print("  Win+K: Focus up\n", .{});
    std.debug.print("  Win+F: Toggle fullscreen\n", .{});
    std.debug.print("  Win+Shift+Q: Close window\n", .{});
    std.debug.print("  Win+Shift+R: Reload\n", .{});
    std.debug.print("  Alt+Q: Exit\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();

    nimble.loop.run();
}
