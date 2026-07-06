const std = @import("std");
const input = @import("input");

const mouse = input.simulate.mouse;

const testing = std.testing;

test "mouse.Input.move relative" {
    const event = mouse.Input.move(10, -5);

    try testing.expectEqual(@as(i32, 10), event.data.mouse.dx);
    try testing.expectEqual(@as(i32, -5), event.data.mouse.dy);
    try testing.expectEqual(@as(u32, 0x0001), event.data.mouse.flags);
}

test "mouse.Input.wheel encodes delta" {
    const event = mouse.Input.wheel(mouse.wheel_delta);

    try testing.expectEqual(@as(u32, 120), event.data.mouse.mouse_data);
    try testing.expectEqual(@as(u32, 0x0800), event.data.mouse.flags);
}

test "mouse.Input.wheel negative delta" {
    const event = mouse.Input.wheel(-mouse.wheel_delta);

    try testing.expectEqual(@as(u32, @bitCast(@as(i32, -120))), event.data.mouse.mouse_data);
}

test "mouse.Input.wheel_horizontal encodes delta" {
    const event = mouse.Input.wheel_horizontal(mouse.wheel_delta);

    try testing.expectEqual(@as(u32, 120), event.data.mouse.mouse_data);
    try testing.expectEqual(@as(u32, 0x1000), event.data.mouse.flags);
}

test "mouse.Input.move_absolute normalized bounds" {
    const event = mouse.Input.move_absolute(0, 0);

    try testing.expect(event.data.mouse.dx >= 0);
    try testing.expect(event.data.mouse.dx <= 65535);
    try testing.expect(event.data.mouse.dy >= 0);
    try testing.expect(event.data.mouse.dy <= 65535);
}

test "mouse.Button flags" {
    try testing.expectEqual(@as(u32, 0x0002), mouse.Button.left.down_flag());
    try testing.expectEqual(@as(u32, 0x0004), mouse.Button.left.up_flag());
    try testing.expectEqual(@as(u32, 0x0080), mouse.Button.x1.down_flag());
    try testing.expectEqual(@as(u32, 0x0001), mouse.Button.x1.xdata());
    try testing.expectEqual(@as(u32, 0x0002), mouse.Button.x2.xdata());
    try testing.expectEqual(@as(u32, 0), mouse.Button.middle.xdata());
}

test "mouse limits" {
    try testing.expect(mouse.scroll_clicks_max >= 1);
    try testing.expect(mouse.wheel_delta == 120);
}

test {
    testing.refAllDecls(mouse);
}
