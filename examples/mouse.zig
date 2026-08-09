const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{});
const Mouse = nimble.MouseType(.{});

const Key = nimble.Key;
const MouseEvent = nimble.MouseEvent;
const Response = nimble.Response;
const Position = nimble.Position;

const App = struct {
    keyboard: *Keyboard,
    mouse: *Mouse,
    click_count: u32 = 0,
    active: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    active_thread: ?std.Thread = null,
    start_position: Position = Position.zero(),
    rng: std.Random.DefaultPrng,
    mutex: nimble.Mutex = .{},

    fn init(kb: *Keyboard, m: *Mouse) App {
        const seed: u64 = @intCast(nimble.time.now_ms());

        return App{
            .keyboard = kb,
            .mouse = m,
            .rng = std.Random.DefaultPrng.init(seed),
        };
    }

    fn on_left_click(self: *App, event: *const MouseEvent) Response {
        self.click_count += 1;

        const position = event.position() orelse nimble.MousePosition.init(0, 0);

        std.debug.print("Left click #{d} at ({d}, {d})\n", .{
            self.click_count,
            position.x,
            position.y,
        });

        return .pass;
    }

    fn on_right_click(_: *App, event: *const MouseEvent) Response {
        const position = event.position() orelse nimble.MousePosition.init(0, 0);

        std.debug.print("Right click at ({d}, {d})\n", .{ position.x, position.y });

        return .pass;
    }

    fn on_move_center(self: *App, _: *const Key) Response {
        _ = self.mouse.center();

        const pos = self.mouse.get_position();

        std.debug.print("Mouse centered at ({d}, {d})\n", .{ pos.x, pos.y });

        return .consume;
    }

    fn on_move_relative(self: *App, _: *const Key) Response {
        _ = self.mouse.move_relative(100, 0);

        std.debug.print("Mouse moved right by 100 pixels\n", .{});

        return .consume;
    }

    fn on_left_click_send(self: *App, _: *const Key) Response {
        _ = self.mouse.left_click();

        std.debug.print("Left click sent\n", .{});

        return .consume;
    }

    fn on_scroll_up(self: *App, _: *const Key) Response {
        _ = self.mouse.scroll_up(3);

        std.debug.print("Scrolled up\n", .{});

        return .consume;
    }

    fn on_scroll_down(self: *App, _: *const Key) Response {
        _ = self.mouse.scroll_down(3);

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

        self.start_position = self.mouse.get_position();
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

            _ = self.mouse.move_to(
                self.start_position.x + offset_x,
                self.start_position.y + offset_y,
            );

            nimble.time.sleep_ms(100);
        }
    }

    fn on_list_monitors(_: *App, _: *const Key) Response {
        const list = nimble.MonitorList.enumerate();

        std.debug.print("Monitors ({d} total):\n", .{list.count});

        for (0..list.count) |i| {
            if (list.get(@intCast(i))) |m| {
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

    fn on_current_monitor(self: *App, _: *const Key) Response {
        const pos = self.mouse.get_position();
        const list = nimble.MonitorList.enumerate();

        if (list.get_at_position(pos.x, pos.y)) |m| {
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

    fn on_center_primary(self: *App, _: *const Key) Response {
        _ = self.mouse.center_on_primary();

        const pos = self.mouse.get_position();

        std.debug.print("Centered on primary monitor at ({d}, {d})\n", .{ pos.x, pos.y });

        return .consume;
    }

    fn on_show_position(self: *App, _: *const Key) Response {
        const pos = self.mouse.get_position();
        const screen = self.mouse.get_screen();

        std.debug.print("Position: ({d}, {d}) | Screen: {d}x{d}\n", .{
            pos.x,
            pos.y,
            screen.width,
            screen.height,
        });

        return .consume;
    }

    fn on_exit(_: *App, _: *const Key) Response {
        std.debug.print("Exit\n", .{});

        nimble.loop.stop();

        return .consume;
    }
};

var keyboard: Keyboard = undefined;
var mouse: Mouse = undefined;

pub fn main() !void {
    try nimble.runtime.open(.{ .mode = .grab });
    defer nimble.runtime.close();

    keyboard = Keyboard.init();
    mouse = Mouse.init();
    defer keyboard.deinit();
    defer mouse.deinit();

    var app = App.init(&keyboard, &mouse);

    _ = try mouse.bind(.left_down).on(&app, App.on_left_click);
    _ = try mouse.bind(.right_down).on(&app, App.on_right_click);

    _ = try keyboard.bind("Alt+C").on(&app, App.on_move_center);
    _ = try keyboard.bind("Alt+R").on(&app, App.on_move_relative);
    _ = try keyboard.bind("Alt+1").on(&app, App.on_left_click_send);
    _ = try keyboard.bind("Alt+PageUp").on(&app, App.on_scroll_up);
    _ = try keyboard.bind("Alt+PageDown").on(&app, App.on_scroll_down);
    _ = try keyboard.bind("Alt+A").on(&app, App.on_toggle_active);
    _ = try keyboard.bind("Alt+M").on(&app, App.on_list_monitors);
    _ = try keyboard.bind("Alt+I").on(&app, App.on_current_monitor);
    _ = try keyboard.bind("Alt+H").on(&app, App.on_center_primary);
    _ = try keyboard.bind("Alt+P").on(&app, App.on_show_position);
    _ = try keyboard.bind("Alt+Q").on(&app, App.on_exit);

    std.debug.print("Mouse Example\n", .{});
    std.debug.print("=============\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Mouse events:\n", .{});
    std.debug.print("  Left/Right click - Log position\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Keyboard controls:\n", .{});
    std.debug.print("  Alt+C: Center mouse on screen\n", .{});
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
