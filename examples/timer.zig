const std = @import("std");
const nimble = @import("nimble");

const Keyboard = nimble.KeyboardType(.{});

const Key = nimble.Key;
const Response = nimble.Response;
const TimerOptions = @import("nimble").registry.timer.Options;

fn report(label: []const u8, err: anyerror) void {
    std.debug.print("{s} failed: {s}\n", .{ label, @errorName(err) });
}

const App = struct {
    keyboard: *Keyboard,
    counter_id: u32 = 0,
    reminder_id: u32 = 0,
    counter_value: u32 = 0,

    fn init(kb: *Keyboard) App {
        return App{
            .keyboard = kb,
        };
    }

    fn setup(self: *App) !void {
        self.counter_id = try self.keyboard.timer_registry.register(
            1000,
            on_counter_tick,
            self,
            TimerOptions{ .repeat = true },
        );

        self.reminder_id = try self.keyboard.timer_registry.register(
            5000,
            on_reminder,
            self,
            TimerOptions{ .repeat = false },
        );
    }

    fn on_counter_tick(ctx: *anyopaque) void {
        const self: *App = @ptrCast(@alignCast(ctx));

        self.counter_value += 1;

        std.debug.print("Counter: {d}\n", .{self.counter_value});
    }

    fn on_reminder(_: *anyopaque) void {
        std.debug.print("Reminder: 5 seconds have passed!\n", .{});
    }

    fn on_start_counter(self: *App, _: *const Key) Response {
        self.keyboard.timer_registry.start(self.counter_id) catch |err| report("start", err);

        std.debug.print("Counter started\n", .{});

        return .consume;
    }

    fn on_stop_counter(self: *App, _: *const Key) Response {
        self.keyboard.timer_registry.stop(self.counter_id) catch |err| report("stop", err);

        std.debug.print("Counter stopped\n", .{});

        return .consume;
    }

    fn on_reset_counter(self: *App, _: *const Key) Response {
        self.counter_value = 0;
        self.keyboard.timer_registry.stop(self.counter_id) catch |err| report("stop", err);
        self.keyboard.timer_registry.start(self.counter_id) catch |err| report("start", err);

        std.debug.print("Counter reset to 0\n", .{});

        return .consume;
    }

    fn on_start_reminder(self: *App, _: *const Key) Response {
        self.keyboard.timer_registry.start(self.reminder_id) catch |err| report("start", err);

        std.debug.print("Reminder started (fires in 5 seconds)\n", .{});

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

    try app.setup();

    _ = try keyboard.bind("Ctrl+1").on(&app, App.on_start_counter);
    _ = try keyboard.bind("Ctrl+2").on(&app, App.on_stop_counter);
    _ = try keyboard.bind("Ctrl+3").on(&app, App.on_reset_counter);
    _ = try keyboard.bind("Ctrl+4").on(&app, App.on_start_reminder);
    _ = try keyboard.bind("Alt+Q").on(&app, App.on_exit);

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
