const std = @import("std");
const nimble = @import("nimble");

const assert = std.debug.assert;

const Client = nimble.remote.Client;
const Key = nimble.Key;
const Response = nimble.Response;

const poll_timeout_ms: u32 = 100;

fn report(label: []const u8, err: anyerror) void {
    std.debug.print("{s} failed: {s}\n", .{ label, @errorName(err) });
}

const App = struct {
    client: *Client,
    done: std.atomic.Value(bool) = .init(false),

    fn on_nudge(app: *App, _: ?*const Key) void {
        app.client.simulate_move(.{ .x = 10, .y = 0 }) catch |err| report("simulate_move", err);

        std.debug.print("Nudged the pointer right\n", .{});
    }

    fn on_greet(app: *App, _: ?*const Key) void {
        app.client.simulate_text("Hello, World!", 0) catch |err| report("simulate_text", err);
    }

    fn on_escape(_: *App, key: *const Key) Response {
        std.debug.print("Filtered: {t}\n", .{key.value});

        return .pass;
    }

    fn on_quit(app: *App, _: ?*const Key) void {
        std.debug.print("Exit\n", .{});

        app.done.store(true, .release);
    }
};

pub fn main() !void {
    var client = Client{};

    try client.connect();
    defer client.disconnect();

    var app = App{ .client = &client };

    const patterns = [_]Client.Pattern{
        .{ .key = .escape, .modifiers_match = .at_least },
    };

    _ = try client.bind("Ctrl+Alt+N", .{}, App, &app, App.on_nudge);
    _ = try client.bind_sequence("hey", .{}, App, &app, App.on_greet);
    _ = try client.bind("Ctrl+Alt+Q", .{}, App, &app, App.on_quit);

    try client.set_filter(&patterns, App, &app, App.on_escape);

    std.debug.print("Remote Example\n", .{});
    std.debug.print("==============\n", .{});
    std.debug.print("\n", .{});
    std.debug.print("  Ctrl+Alt+N: Nudge the pointer right\n", .{});
    std.debug.print("  hey:        Type 'Hello, World!'\n", .{});
    std.debug.print("  Escape:     Logged by the filter\n", .{});
    std.debug.print("  Ctrl+Alt+Q: Exit\n", .{});
    std.debug.print("\n", .{});

    while (!app.done.load(.acquire)) {
        assert(client.is_connected());

        if (nimble.runtime.is_open()) {
            _ = nimble.loop.poll(poll_timeout_ms);
        } else {
            nimble.time.sleep_ms(poll_timeout_ms);
        }
    }
}
