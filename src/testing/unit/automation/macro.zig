const std = @import("std");
const input = @import("input");

const macro_mod = input.automation.macro;
const modifier = input.modifier;

const ActionKind = macro_mod.ActionKind;
const Action = macro_mod.Action;

const testing = std.testing;

test "ActionKind.is_valid key_down" {
    try testing.expect(ActionKind.key_down.is_valid());
}

test "ActionKind.is_valid key_up" {
    try testing.expect(ActionKind.key_up.is_valid());
}

test "ActionKind.is_valid key_press" {
    try testing.expect(ActionKind.key_press.is_valid());
}

test "ActionKind.is_valid mouse_move" {
    try testing.expect(ActionKind.mouse_move.is_valid());
}

test "ActionKind.is_valid mouse_click" {
    try testing.expect(ActionKind.mouse_click.is_valid());
}

test "ActionKind.is_valid mouse_down" {
    try testing.expect(ActionKind.mouse_down.is_valid());
}

test "ActionKind.is_valid mouse_up" {
    try testing.expect(ActionKind.mouse_up.is_valid());
}

test "ActionKind.is_valid mouse_scroll" {
    try testing.expect(ActionKind.mouse_scroll.is_valid());
}

test "ActionKind.is_valid delay" {
    try testing.expect(ActionKind.delay.is_valid());
}

test "ActionKind.is_valid text" {
    try testing.expect(ActionKind.text.is_valid());
}

test "ActionKind enum values" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(ActionKind.key_down));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(ActionKind.key_up));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(ActionKind.key_press));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(ActionKind.mouse_move));
    try testing.expectEqual(@as(u8, 4), @intFromEnum(ActionKind.mouse_click));
    try testing.expectEqual(@as(u8, 5), @intFromEnum(ActionKind.mouse_down));
    try testing.expectEqual(@as(u8, 6), @intFromEnum(ActionKind.mouse_up));
    try testing.expectEqual(@as(u8, 7), @intFromEnum(ActionKind.mouse_scroll));
    try testing.expectEqual(@as(u8, 8), @intFromEnum(ActionKind.delay));
    try testing.expectEqual(@as(u8, 9), @intFromEnum(ActionKind.text));
}

test "Action default" {
    const action = Action{};

    try testing.expectEqual(ActionKind.key_press, action.kind);
    try testing.expectEqual(@as(u8, 0), action.key);
    try testing.expect(action.modifiers.none());
}

test "Action.key_down" {
    const action = Action.key_down('A');

    try testing.expect(action.is_valid());
    try testing.expectEqual(ActionKind.key_down, action.kind);
    try testing.expectEqual(@as(u8, 'A'), action.key);
}

test "Action.key_up" {
    const action = Action.key_up('B');

    try testing.expect(action.is_valid());
    try testing.expectEqual(ActionKind.key_up, action.kind);
    try testing.expectEqual(@as(u8, 'B'), action.key);
}

test "Action.key_press" {
    const action = Action.key_press('C');

    try testing.expect(action.is_valid());
    try testing.expectEqual(ActionKind.key_press, action.kind);
    try testing.expectEqual(@as(u8, 'C'), action.key);
}

test "Action.mouse_move" {
    const action = Action.mouse_move(100, 200);

    try testing.expect(action.is_valid());
    try testing.expectEqual(ActionKind.mouse_move, action.kind);
    try testing.expectEqual(@as(i32, 100), action.x);
    try testing.expectEqual(@as(i32, 200), action.y);
}

test "Action.mouse_scroll" {
    const action = Action.mouse_scroll(120);

    try testing.expect(action.is_valid());
    try testing.expectEqual(ActionKind.mouse_scroll, action.kind);
    try testing.expectEqual(@as(i32, 120), action.scroll_amount);
}

test "Action.mouse_scroll negative" {
    const action = Action.mouse_scroll(-120);

    try testing.expect(action.is_valid());
    try testing.expectEqual(@as(i32, -120), action.scroll_amount);
}

test "Action.delay" {
    const action = Action.delay(500);

    try testing.expect(action.is_valid());
    try testing.expectEqual(ActionKind.delay, action.kind);
    try testing.expectEqual(@as(u32, 500), action.delay_ms);
}

test "Action text" {
    const action = Action{
        .kind = .text,
        .text_start = 0,
        .text_len = 10,
    };

    try testing.expect(action.is_valid());
}

test "Action with modifiers" {
    const action = Action{
        .kind = .key_press,
        .key = 'S',
        .modifiers = modifier.Set.from(.{ .ctrl = true }),
    };

    try testing.expect(action.is_valid());
    try testing.expect(action.modifiers.ctrl());
}

test "macro constants" {
    try testing.expect(macro_mod.action_max >= 1);
    try testing.expect(macro_mod.capacity_max >= 1);
    try testing.expect(macro_mod.name_max >= 1);
    try testing.expect(macro_mod.text_buffer_max >= 1);
    try testing.expect(macro_mod.delay_default_ms > 0);
    try testing.expect(macro_mod.delay_max_ms >= macro_mod.delay_default_ms);
    try testing.expect(macro_mod.repeat_max >= 1);
}
