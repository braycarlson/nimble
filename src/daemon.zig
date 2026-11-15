const std = @import("std");

const nimble = @import("root.zig");
const server_module = @import("platform/linux/remote/server.zig");

const ServerType = server_module.ServerType;

const Keyboard = nimble.KeyboardType(.{
    .binding_count_max = server_module.binding_count_max,
    .chord_count_max = 32,
    .sequence_count_max = 8,
});

const Mouse = nimble.MouseType(.{});
const Server = ServerType(Keyboard, Mouse);

pub fn main() !void {
    var runtime: nimble.Runtime = undefined;

    try runtime.init(.{ .mode = .grab });
    defer runtime.deinit();

    var keyboard: Keyboard = undefined;

    try keyboard.init(&runtime, .{});
    defer keyboard.deinit();

    var mouse: Mouse = undefined;

    mouse.init(&runtime, .{ .pass_injected = false });
    defer mouse.deinit();

    try keyboard.start();
    defer keyboard.stop();

    try mouse.start();
    defer mouse.stop();

    var server = Server.init(&keyboard, &mouse);

    try server.start();
    defer server.stop();

    runtime.set_release_callback(Server, &server, Server.on_runtime_released);
    defer runtime.clear_release_callback();

    std.log.info("nimbled serving", .{});

    runtime.run();
}
