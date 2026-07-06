const std = @import("std");
const input = @import("input");

const testing = std.testing;

test "KeyboardHook full surface compiles" {
    const Hook = input.keyboard.KeyboardHook(.{});

    testing.refAllDecls(Hook);

    try testing.expect(@sizeOf(Hook) > 0);
}

test "KeyboardHook custom config surface compiles" {
    const Hook = input.keyboard.KeyboardHook(.{
        .capacity = 16,
        .capacity_chord = 4,
        .pass_injected = true,
    });

    testing.refAllDecls(Hook);

    try testing.expect(@sizeOf(Hook) > 0);
}

test "MouseHook full surface compiles" {
    const Hook = input.mouse.MouseHook(.{});

    testing.refAllDecls(Hook);

    try testing.expect(@sizeOf(Hook) > 0);
}

test "MouseHook custom config surface compiles" {
    const Hook = input.mouse.MouseHook(.{
        .capacity = 16,
        .pass_injected = false,
    });

    testing.refAllDecls(Hook);

    try testing.expect(@sizeOf(Hook) > 0);
}
