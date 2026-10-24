const std = @import("std");
const nimble = @import("nimble");

const assert = std.debug.assert;

const Keyboard = nimble.KeyboardType(.{ .binding_count_max = 16 });
const Mouse = nimble.MouseType(.{ .binding_count_max = 2 });

const Key = nimble.Key;
const Monitor = nimble.Monitor;
const MouseEvent = nimble.MouseEvent;
const Position = nimble.Position;
const Response = nimble.Response;

const pointer = nimble.simulate.mouse;

const App = struct {
    click_count: u32 = 0,
    active: std.atomic.Value(bool) = .init(false),
    active_thread: ?std.Thread = null,
    start_position: Position = .zero,
    rng: std.Random.DefaultPrng,
    mutex: nimble.Mutex = .{},

    fn init() App {
        const seed: u64 = @intCast(nimble.time.now_ms());

        return App{
            .rng = std.Random.DefaultPrng.init(seed),
        };
    }

    fn on_left_click(self: *App, event: *const MouseEvent) Response {
        self.click_count += 1;

        const position = event.position() orelse Position.zero;

        std.debug.print("Left click #{d} at ({d}, {d})\n", .{
            self.click_count,
            position.x,
            position.y,
        });

        return .pass;
    }

    fn on_right_click(_: *App, event: *const MouseEvent) Response {
        const position = event.position() orelse Position.zero;

        std.debug.print("Right click at ({d}, {d})\n", .{ position.x, position.y });

        return .pass;
    }

    fn on_move_center(_: *App, _: *const Key) Response {
        var monitors: Monitor.List = undefined;

        monitors.enumerate();

        const current = monitors.at(pointer.position()) orelse return .consume;

        _ = pointer.move_to(current.center());

        const position = pointer.position();

        std.debug.print("Mouse centered at ({d}, {d})\n", .{ position.x, position.y });

        return .consume;
    }

    fn on_move_relative(_: *App, _: *const Key) Response {
        _ = pointer.move_relative(.{ .x = 100, .y = 0 });

        std.debug.print("Mouse moved right by 100 pixels\n", .{});

        return .consume;
    }

    fn on_left_click_send(_: *App, _: *const Key) Response {
        _ = pointer.click(.left);

        std.debug.print("Left click sent\n", .{});

        return .consume;
    }

    fn on_scroll_up(_: *App, _: *const Key) Response {
        _ = pointer.scroll_up(3);

        std.debug.print("Scrolled up\n", .{});

        return .consume;
    }

    fn on_scroll_down(_: *App, _: *const Key) Response {
        _ = pointer.scroll_down(3);

        std.debug.print("Scrolled down\n", .{});

        return .consume;
    }

    fn on_toggle_active(self: *App, _: *const Key) Response {
        if (self.active.load(.acquire)) {
            self.stop_active();
            std.debug.print("Active mode: OFF\n", .{});
        } else {
            self.start_active();
            std.debug.print("Active mode: ON\n", .{});
        }

        return .consume;
    }

    fn start_active(self: *App) void {
        if (self.active.load(.acquire)) {
            return;
        }

        self.start_position = pointer.position();

        self.active.store(true, .release);

        self.active_thread = std.Thread.spawn(.{}, active_worker, .{self}) catch null;
    }

    fn stop_active(self: *App) void {
        if (!self.active.load(.acquire)) {
            return;
        }

        self.active.store(false, .release);

        if (self.active_thread) |thread| {
            thread.join();
            self.active_thread = null;
        }
    }

    fn active_worker(self: *App) void {
        while (self.active.load(.acquire)) {
            self.mutex.lock();

            const offset_x = self.rng.random().intRangeAtMost(i32, -5, 5);
            const offset_y = self.rng.random().intRangeAtMost(i32, -5, 5);

            self.mutex.unlock();

            assert(offset_x >= -5);
            assert(offset_x <= 5);
            assert(offset_y >= -5);
            assert(offset_y <= 5);

            _ = pointer.move_to(.{
                .x = self.start_position.x + offset_x,
                .y = self.start_position.y + offset_y,
            });

            nimble.time.sleep_ms(100);
        }
    }

    fn on_list_monitors(_: *App, _: *const Key) Response {
        var monitors: Monitor.List = undefined;

        monitors.enumerate();

        std.debug.print("Monitors ({d} total):\n", .{monitors.count});

        for (0..monitors.count) |i| {
            if (monitors.get(@intCast(i))) |m| {
                std.debug.print("  [{d}] {d}x{d} at ({d}, {d}){s}\n", .{
                    i,
                    m.width(),
                    m.height(),
                    m.left,
                    m.top,
                    if (m.primary) " (primary)" else "",
                });
            }
        }

        return .consume;
    }

    fn on_current_monitor(_: *App, _: *const Key) Response {
        var monitors: Monitor.List = undefined;

        monitors.enumerate();

        if (monitors.at(pointer.position())) |m| {
            std.debug.print("Current monitor: {d}x{d} at ({d}, {d})\n", .{
                m.width(),
                m.height(),
                m.left,
                m.top,
            });
        } else {
            std.debug.print("Mouse not on any known monitor\n", .{});
        }

        return .consume;
    }

    fn on_center_primary(_: *App, _: *const Key) Response {
        var monitors: Monitor.List = undefined;

        monitors.enumerate();

        const primary = monitors.primary() orelse return .consume;

        _ = pointer.move_to(primary.center());

        const position = pointer.position();

        std.debug.print("Centered on primary monitor at ({d}, {d})\n", .{
            position.x,
            position.y,
        });

        return .consume;
    }

    fn on_show_position(_: *App, _: *const Key) Response {
        const position = pointer.position();

        std.debug.print("Position: ({d}, {d})\n", .{ position.x, position.y });

        return .consume;
    }

    fn on_exit(_: *App, _: *const Key) Response {
        std.debug.print("Exit\n", .{});

        nimble.loop.stop();

        return .consume;
    }
};

pub fn main(init: std.process.Init) !void {
    try nimble.runtime.open(.{
        .mode = .grab,
        .wayland_display = init.environ_map.get("WAYLAND_DISPLAY"),
        .xdg_runtime_dir = init.environ_map.get("XDG_RUNTIME_DIR"),
    });

    defer nimble.runtime.close();

    var keyboard: Keyboard = undefined;

    try keyboard.init(.{});
    defer keyboard.deinit();

    var mouse: Mouse = undefined;

    mouse.init(.{});
    defer mouse.deinit();

    var app = App.init();
    defer app.stop_active();

    _ = try mouse.bind(.left_down).on(App, &app, App.on_left_click);
    _ = try mouse.bind(.right_down).on(App, &app, App.on_right_click);

    _ = try keyboard.bind("Alt+C").on(App, &app, App.on_move_center);
    _ = try keyboard.bind("Alt+R").on(App, &app, App.on_move_relative);
    _ = try keyboard.bind("Alt+1").on(App, &app, App.on_left_click_send);
    _ = try keyboard.bind("Alt+PageUp").on(App, &app, App.on_scroll_up);
    _ = try keyboard.bind("Alt+PageDown").on(App, &app, App.on_scroll_down);
    _ = try keyboard.bind("Alt+A").on(App, &app, App.on_toggle_active);
    _ = try keyboard.bind("Alt+M").on(App, &app, App.on_list_monitors);
    _ = try keyboard.bind("Alt+I").on(App, &app, App.on_current_monitor);
    _ = try keyboard.bind("Alt+H").on(App, &app, App.on_center_primary);
    _ = try keyboard.bind("Alt+P").on(App, &app, App.on_show_position);
    _ = try keyboard.bind("Alt+Q").on(App, &app, App.on_exit);

    std.debug.print("Mouse Example\n", .{});
    std.debug.print("=============\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Mouse events:\n", .{});
    std.debug.print("  Left/Right click - Log position\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Keyboard controls:\n", .{});
    std.debug.print("  Alt+C: Center mouse on its current monitor\n", .{});
    std.debug.print("  Alt+R: Move mouse right 100px\n", .{});
    std.debug.print("  Alt+1: Left click\n", .{});
    std.debug.print("  Alt+PageUp/PageDown: Scroll\n", .{});
    std.debug.print("  Alt+A: Toggle active mode\n", .{});
    std.debug.print("  Alt+P: Show current position\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Multi-monitor:\n", .{});
    std.debug.print("  Alt+M: List all monitors\n", .{});
    std.debug.print("  Alt+I: Show current monitor info\n", .{});
    std.debug.print("  Alt+H: Center on primary monitor\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Alt+Q: Exit\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();
    try mouse.start();

    nimble.loop.run();
}
