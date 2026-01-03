const std = @import("std");
const input = @import("input");

const event = input.event;
const keycode = input.keycode;
const modifier = input.modifier;

const Key = event.Key;
const Mouse = event.Mouse;
const MouseKind = event.MouseKind;

const testing = std.testing;

fn make_key(value: u8, down: bool, modifiers: modifier.Set) Key {
    return Key{
        .value = value,
        .scan = 0,
        .down = down,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = modifiers,
    };
}

test "Key.is_valid alpha" {
    const key = make_key('A', true, .{});
    try testing.expect(key.is_valid());
}

test "Key.is_valid digit" {
    const key = make_key('5', true, .{});
    try testing.expect(key.is_valid());
}

test "Key.is_valid special" {
    const key = make_key(keycode.space, true, .{});
    try testing.expect(key.is_valid());
}

test "Key.is_valid modifier key" {
    const key = make_key(keycode.lctrl, true, .{});
    try testing.expect(key.is_valid());
}

test "Key.is_modifier ctrl" {
    const key = make_key(keycode.lctrl, true, .{});
    try testing.expect(key.is_modifier());
}

test "Key.is_modifier rctrl" {
    const key = make_key(keycode.rctrl, true, .{});
    try testing.expect(key.is_modifier());
}

test "Key.is_modifier alt" {
    const key = make_key(keycode.lmenu, true, .{});
    try testing.expect(key.is_modifier());
}

test "Key.is_modifier shift" {
    const key = make_key(keycode.lshift, true, .{});
    try testing.expect(key.is_modifier());
}

test "Key.is_modifier win" {
    const key = make_key(keycode.lwin, true, .{});
    try testing.expect(key.is_modifier());
}

test "Key.is_modifier false for alpha" {
    const key = make_key('A', true, .{});
    try testing.expect(!key.is_modifier());
}

test "Key.is_modifier false for space" {
    const key = make_key(keycode.space, true, .{});
    try testing.expect(!key.is_modifier());
}

test "Key.is_ctrl_down" {
    const key = make_key('A', true, modifier.Set.from(.{ .ctrl = true }));
    try testing.expect(key.is_ctrl_down());
    try testing.expect(!key.is_alt_down());
    try testing.expect(!key.is_shift_down());
    try testing.expect(!key.is_win_down());
}

test "Key.is_alt_down" {
    const key = make_key('A', true, modifier.Set.from(.{ .alt = true }));
    try testing.expect(key.is_alt_down());
    try testing.expect(!key.is_ctrl_down());
}

test "Key.is_shift_down" {
    const key = make_key('A', true, modifier.Set.from(.{ .shift = true }));
    try testing.expect(key.is_shift_down());
    try testing.expect(!key.is_ctrl_down());
}

test "Key.is_win_down" {
    const key = make_key('A', true, modifier.Set.from(.{ .win = true }));
    try testing.expect(key.is_win_down());
    try testing.expect(!key.is_ctrl_down());
}

test "Key.is_ctrl_down false" {
    const key = make_key('A', true, .{});
    try testing.expect(!key.is_ctrl_down());
}

test "Key.with_modifiers" {
    const key = make_key('A', true, .{});
    const modifiers = modifier.Set.from(.{ .ctrl = true, .shift = true });
    const result = key.with_modifiers(modifiers);

    try testing.expectEqual(@as(u8, 'A'), result.value);
    try testing.expect(result.is_ctrl_down());
    try testing.expect(result.is_shift_down());
    try testing.expect(!result.is_alt_down());
    try testing.expect(!result.is_win_down());
}

test "Key.with_modifiers preserves other fields" {
    const key = Key{
        .value = 'B',
        .scan = 123,
        .down = true,
        .injected = true,
        .extended = true,
        .extra = 456,
        .modifiers = .{},
    };
    const modifiers = modifier.Set.from(.{ .alt = true });
    const result = key.with_modifiers(modifiers);

    try testing.expectEqual(@as(u8, 'B'), result.value);
    try testing.expectEqual(@as(u16, 123), result.scan);
    try testing.expect(result.down);
    try testing.expect(result.injected);
    try testing.expect(result.extended);
    try testing.expectEqual(@as(u64, 456), result.extra);
    try testing.expect(result.is_alt_down());
}

test "Key multiple modifiers" {
    const key = make_key('X', true, modifier.Set.from(.{ .ctrl = true, .alt = true, .shift = true, .win = true }));

    try testing.expect(key.is_ctrl_down());
    try testing.expect(key.is_alt_down());
    try testing.expect(key.is_shift_down());
    try testing.expect(key.is_win_down());
}

test "MouseKind.is_valid" {
    try testing.expect(MouseKind.left_down.is_valid());
    try testing.expect(MouseKind.left_up.is_valid());
    try testing.expect(MouseKind.right_down.is_valid());
    try testing.expect(MouseKind.right_up.is_valid());
    try testing.expect(MouseKind.middle_down.is_valid());
    try testing.expect(MouseKind.middle_up.is_valid());
    try testing.expect(MouseKind.x_down.is_valid());
    try testing.expect(MouseKind.x_up.is_valid());
    try testing.expect(MouseKind.wheel.is_valid());
    try testing.expect(MouseKind.move.is_valid());
    try testing.expect(MouseKind.other.is_valid());
}

test "MouseKind.is_button" {
    try testing.expect(MouseKind.left_down.is_button());
    try testing.expect(MouseKind.left_up.is_button());
    try testing.expect(MouseKind.right_down.is_button());
    try testing.expect(MouseKind.right_up.is_button());
    try testing.expect(MouseKind.middle_down.is_button());
    try testing.expect(MouseKind.middle_up.is_button());
    try testing.expect(MouseKind.x_down.is_button());
    try testing.expect(MouseKind.x_up.is_button());
}

test "MouseKind.is_button false" {
    try testing.expect(!MouseKind.wheel.is_button());
    try testing.expect(!MouseKind.move.is_button());
    try testing.expect(!MouseKind.other.is_button());
}

test "MouseKind.is_down" {
    try testing.expect(MouseKind.left_down.is_down());
    try testing.expect(MouseKind.right_down.is_down());
    try testing.expect(MouseKind.middle_down.is_down());
    try testing.expect(MouseKind.x_down.is_down());
}

test "MouseKind.is_down false" {
    try testing.expect(!MouseKind.left_up.is_down());
    try testing.expect(!MouseKind.right_up.is_down());
    try testing.expect(!MouseKind.wheel.is_down());
    try testing.expect(!MouseKind.move.is_down());
}

test "MouseKind.is_up" {
    try testing.expect(MouseKind.left_up.is_up());
    try testing.expect(MouseKind.right_up.is_up());
    try testing.expect(MouseKind.middle_up.is_up());
    try testing.expect(MouseKind.x_up.is_up());
}

test "MouseKind.is_up false" {
    try testing.expect(!MouseKind.left_down.is_up());
    try testing.expect(!MouseKind.right_down.is_up());
    try testing.expect(!MouseKind.wheel.is_up());
    try testing.expect(!MouseKind.move.is_up());
}

test "MouseKind enum values" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(MouseKind.left_down));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(MouseKind.left_up));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(MouseKind.right_down));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(MouseKind.right_up));
    try testing.expectEqual(@as(u8, 4), @intFromEnum(MouseKind.middle_down));
    try testing.expectEqual(@as(u8, 5), @intFromEnum(MouseKind.middle_up));
    try testing.expectEqual(@as(u8, 6), @intFromEnum(MouseKind.x_down));
    try testing.expectEqual(@as(u8, 7), @intFromEnum(MouseKind.x_up));
    try testing.expectEqual(@as(u8, 8), @intFromEnum(MouseKind.wheel));
    try testing.expectEqual(@as(u8, 9), @intFromEnum(MouseKind.move));
    try testing.expectEqual(@as(u8, 10), @intFromEnum(MouseKind.other));
}

fn make_mouse(kind: MouseKind, x: i32, y: i32) Mouse {
    return Mouse{
        .kind = kind,
        .x = x,
        .y = y,
        .extra = 0,
    };
}

test "Mouse.is_valid" {
    const mouse = make_mouse(.left_down, 100, 200);
    try testing.expect(mouse.is_valid());
}

test "Mouse.is_button" {
    const button = make_mouse(.left_down, 0, 0);
    const non_button = make_mouse(.move, 0, 0);

    try testing.expect(button.is_button());
    try testing.expect(!non_button.is_button());
}

test "Mouse.is_down" {
    const down = make_mouse(.left_down, 0, 0);
    const up = make_mouse(.left_up, 0, 0);

    try testing.expect(down.is_down());
    try testing.expect(!up.is_down());
}

test "Mouse.is_up" {
    const up = make_mouse(.right_up, 0, 0);
    const down = make_mouse(.right_down, 0, 0);

    try testing.expect(up.is_up());
    try testing.expect(!down.is_up());
}

test "Mouse coordinates" {
    const mouse = make_mouse(.move, -500, 1000);

    try testing.expectEqual(@as(i32, -500), mouse.x);
    try testing.expectEqual(@as(i32, 1000), mouse.y);
}

test "Mouse all button types" {
    const left = make_mouse(.left_down, 0, 0);
    const right = make_mouse(.right_down, 0, 0);
    const middle = make_mouse(.middle_down, 0, 0);
    const x = make_mouse(.x_down, 0, 0);

    try testing.expect(left.is_button());
    try testing.expect(right.is_button());
    try testing.expect(middle.is_button());
    try testing.expect(x.is_button());
}
