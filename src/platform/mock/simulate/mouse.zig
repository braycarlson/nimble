const std = @import("std");

const monitor = @import("../monitor.zig");
const mouse_event = @import("../../../event/mouse.zig");
const position_module = @import("../../../position.zig");
const record = @import("../record.zig");

const assert = std.debug.assert;

const Position = position_module.Position;

pub const Button = mouse_event.MouseEvent.Button;

pub const scroll_clicks_max: u32 = 32;

comptime {
    assert(scroll_clicks_max > 0);
}

pub fn button_down(button: Button) bool {
    assert(button.is_valid());

    record.push(.{ .kind = .mouse_down, .button = @backingInt(button), .down = true });

    return true;
}

pub fn button_up(button: Button) bool {
    assert(button.is_valid());

    record.push(.{ .kind = .mouse_up, .button = @backingInt(button), .down = false });

    return true;
}

pub fn click(button: Button) bool {
    const down = button_down(button);
    const up = button_up(button);

    return down and up;
}

pub fn move_to(position: Position) bool {
    monitor.set_cursor_position(position);
    record.push(.{ .kind = .mouse_move, .x = position.x, .y = position.y });

    return true;
}

pub fn move_relative(offset: Position) bool {
    const current = monitor.get_cursor_position();
    return move_to(.{ .x = current.x + offset.x, .y = current.y + offset.y });
}

pub fn scroll_up(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    record.push(.{ .kind = .mouse_scroll, .amount = @intCast(clicks) });

    return true;
}

pub fn scroll_down(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    record.push(.{ .kind = .mouse_scroll, .amount = -@as(i32, @intCast(clicks)) });

    return true;
}

pub fn scroll_left(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    record.push(.{ .kind = .mouse_scroll, .x = -@as(i32, @intCast(clicks)) });

    return true;
}

pub fn scroll_right(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    record.push(.{ .kind = .mouse_scroll, .x = @intCast(clicks) });

    return true;
}

pub fn get_position() Position {
    return monitor.get_cursor_position();
}
