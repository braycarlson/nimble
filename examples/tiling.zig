const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{ .binding_count_max = 8 });

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

pub fn main() !void {
    try nimble.runtime.open(.{ .mode = .grab });
    defer nimble.runtime.close();

    var keyboard: Keyboard = undefined;

    try keyboard.init(.{});
    defer keyboard.deinit();

    var tiler = Tiler{};

    _ = try keyboard.bind("Win+Left").on(Tiler, &tiler, Tiler.on_tile_left);
    _ = try keyboard.bind("Win+Right").on(Tiler, &tiler, Tiler.on_tile_right);
    _ = try keyboard.bind("Win+Down").on(Tiler, &tiler, Tiler.on_focus_down);
    _ = try keyboard.bind("Win+Up").on(Tiler, &tiler, Tiler.on_focus_up);
    _ = try keyboard.bind("Win+F").on(Tiler, &tiler, Tiler.on_toggle_fullscreen);
    _ = try keyboard.bind("Win+Shift+Q").on(Tiler, &tiler, Tiler.on_close_window);
    _ = try keyboard.bind("Win+Shift+R").on(Tiler, &tiler, Tiler.on_reload);
    _ = try keyboard.bind("Alt+Q").on(Tiler, &tiler, Tiler.on_exit);

    std.debug.print("Tiling Window Manager Example\n", .{});
    std.debug.print("=============================\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  Win+Left: Tile left\n", .{});
    std.debug.print("  Win+Right: Tile right\n", .{});
    std.debug.print("  Win+Down: Focus down\n", .{});
    std.debug.print("  Win+Up: Focus up\n", .{});
    std.debug.print("  Win+F: Toggle fullscreen\n", .{});
    std.debug.print("  Win+Shift+Q: Close window\n", .{});
    std.debug.print("  Win+Shift+R: Reload\n", .{});
    std.debug.print("  Alt+Q: Exit\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();

    nimble.loop.run();
}
