const std = @import("std");

const nimble = @import("root.zig");
const server_mod = @import("platform/linux/remote/server.zig");

const Keyboard = nimble.KeyboardType(.{});
const Mouse = nimble.MouseType(.{ .pass_injected = false });
const Server = server_mod.ServerType(Keyboard, Mouse);

var keyboard: Keyboard = undefined;
var mouse: Mouse = undefined;
var server: Server = undefined;

pub fn main() !void {
    keyboard = Keyboard.init();
    defer keyboard.deinit();

    mouse = Mouse.init();
    defer mouse.deinit();

    try nimble.runtime.open(.{ .mode = .grab });
    defer nimble.runtime.close();

    try keyboard.start();
    defer keyboard.stop();

    try mouse.start();
    defer mouse.stop();

    server = Server.init(&keyboard, &mouse);

    server_mod.set_notify_sender(send_notify);
    defer server_mod.set_notify_sender(null);

    try server.start();
    defer server.stop();

    nimble.runtime.set_release_callback(on_released);
    defer nimble.runtime.set_release_callback(null);

    std.log.info("nimbled serving", .{});

    nimble.loop.run();
}

fn send_notify(binding: *const server_mod.Binding, key: ?*const nimble.Key) void {
    server.send_notify(binding, key);
}

fn on_released() void {
    Server.on_runtime_released();
}
