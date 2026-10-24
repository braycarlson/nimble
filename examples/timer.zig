const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{
    .binding_count_max = 5,
    .timer_count_max = 2,
});

const Key = nimble.Key;
const Response = nimble.Response;

fn report(label: []const u8, err: anyerror) void {
    std.debug.print("{s} failed: {s}\n", .{ label, @errorName(err) });
}

const App = struct {
    keyboard: *Keyboard,
    counter: Keyboard.Timer = undefined,
    reminder: Keyboard.Timer = undefined,
    counter_value: u32 = 0,

    fn init(kb: *Keyboard) App {
        return App{
            .keyboard = kb,
        };
    }

    fn setup(self: *App) !void {
        self.counter = try self.keyboard.timer(1000).on(App, self, on_counter_tick);
        self.reminder = try self.keyboard.timer(5000).once().on(App, self, on_reminder);
    }

    fn on_counter_tick(self: *App) void {
        self.counter_value += 1;

        std.debug.print("Counter: {d}\n", .{self.counter_value});
    }

    fn on_reminder(_: *App) void {
        std.debug.print("Reminder: 5 seconds have passed!\n", .{});
    }

    fn on_start_counter(self: *App, _: *const Key) Response {
        self.keyboard.start_timer(self.counter) catch |err| report("start", err);

        std.debug.print("Counter started\n", .{});

        return .consume;
    }

    fn on_stop_counter(self: *App, _: *const Key) Response {
        self.keyboard.stop_timer(self.counter) catch |err| report("stop", err);

        std.debug.print("Counter stopped\n", .{});

        return .consume;
    }

    fn on_reset_counter(self: *App, _: *const Key) Response {
        self.counter_value = 0;

        self.keyboard.stop_timer(self.counter) catch |err| switch (err) {
            error.TimerStopped => {},
            else => report("stop", err),
        };

        self.keyboard.start_timer(self.counter) catch |err| report("start", err);

        std.debug.print("Counter reset to 0\n", .{});

        return .consume;
    }

    fn on_start_reminder(self: *App, _: *const Key) Response {
        self.keyboard.start_timer(self.reminder) catch |err| report("start", err);

        std.debug.print("Reminder started (fires in 5 seconds)\n", .{});

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

    _ = try keyboard.bind("Ctrl+1").on(App, &app, App.on_start_counter);
    _ = try keyboard.bind("Ctrl+2").on(App, &app, App.on_stop_counter);
    _ = try keyboard.bind("Ctrl+3").on(App, &app, App.on_reset_counter);
    _ = try keyboard.bind("Ctrl+4").on(App, &app, App.on_start_reminder);
    _ = try keyboard.bind("Alt+Q").on(App, &app, App.on_exit);

    std.debug.print("Timer Example\n", .{});
    std.debug.print("=============\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("Controls:\n", .{});
    std.debug.print("  Ctrl+1: Start counter (1 second interval)\n", .{});
    std.debug.print("  Ctrl+2: Stop counter\n", .{});
    std.debug.print("  Ctrl+3: Reset counter\n", .{});
    std.debug.print("  Ctrl+4: Start reminder (5 second one-shot)\n", .{});
    std.debug.print("  Alt+Q: Exit\n", .{});
    std.debug.print("\n", .{});

    try keyboard.start();

    nimble.loop.run();
}
