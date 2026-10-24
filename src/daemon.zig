const std = @import("std");

const nimble = @import("root.zig");
const server_mod = @import("platform/linux/remote/server.zig");

const Keyboard = nimble.KeyboardType(.{
    .binding_count_max = server_mod.binding_count_max,
    .chord_count_max = 32,
    .sequence_count_max = 8,
});

const Mouse = nimble.MouseType(.{});
const Server = server_mod.ServerType(Keyboard, Mouse);

pub fn main() !void {
    var keyboard: Keyboard = undefined;

    try keyboard.init(.{});
    defer keyboard.deinit();

    var mouse: Mouse = undefined;

    mouse.init(.{ .pass_injected = false });
    defer mouse.deinit();

    try nimble.runtime.open(.{ .mode = .grab });
    defer nimble.runtime.close();

    try keyboard.start();
    defer keyboard.stop();

    try mouse.start();
    defer mouse.stop();

    var server = Server.init(&keyboard, &mouse);

    try server.start();
    defer server.stop();

    nimble.runtime.set_release_callback(Server.on_runtime_released);
    defer nimble.runtime.set_release_callback(null);

    std.log.info("nimbled serving", .{});

    nimble.loop.run();
}
