const std = @import("std");

const w32 = @import("win32").everything;

const monitor_mod = @import("../monitor.zig");

pub const Monitor = monitor_mod.Monitor;
pub const MonitorList = monitor_mod.List;
pub const Position = monitor_mod.Position;
pub const Screen = monitor_mod.Screen;

pub const marker_injected: u64 = 0x102;
pub const capacity_input: u8 = 8;
pub const scroll_clicks_max: u32 = 100;
pub const monitor_max: u8 = monitor_mod.max;

const type_mouse: u32 = 0;

const flag_move: u32 = 0x0001;
const flag_leftdown: u32 = 0x0002;
const flag_leftup: u32 = 0x0004;
const flag_rightdown: u32 = 0x0008;
const flag_rightup: u32 = 0x0010;
const flag_middledown: u32 = 0x0020;
const flag_middleup: u32 = 0x0040;
const flag_xdown: u32 = 0x0080;
const flag_xup: u32 = 0x0100;
const flag_wheel: u32 = 0x0800;
const flag_hwheel: u32 = 0x1000;
const flag_absolute: u32 = 0x8000;
const flag_virtualdesk: u32 = 0x4000;

const xbutton1: u32 = 0x0001;
const xbutton2: u32 = 0x0002;

pub const wheel_delta: i32 = 120;

pub const button_count: u8 = 5;
pub const button_max: u8 = 4;

pub const Button = enum(u8) {
    left = 0,
    right = 1,
    middle = 2,
    x1 = 3,
    x2 = 4,

    pub fn is_valid(self: Button) bool {
        const value = @intFromEnum(self);
        return value <= button_max;
    }

    pub fn down_flag(self: Button) u32 {
        std.debug.assert(self.is_valid());

        return switch (self) {
            .left => flag_leftdown,
            .right => flag_rightdown,
            .middle => flag_middledown,
            .x1, .x2 => flag_xdown,
        };
    }

    pub fn up_flag(self: Button) u32 {
        std.debug.assert(self.is_valid());

        return switch (self) {
            .left => flag_leftup,
            .right => flag_rightup,
            .middle => flag_middleup,
            .x1, .x2 => flag_xup,
        };
    }

    pub fn xdata(self: Button) u32 {
        std.debug.assert(self.is_valid());

        return switch (self) {
            .x1 => xbutton1,
            .x2 => xbutton2,
            else => 0,
        };
    }
};

pub const Input = extern struct {
    type: u32,
    padding: u32 = 0,
    data: extern union {
        mouse: MouseData,
        padding: [32]u8,
    },

    const MouseData = extern struct {
        dx: i32,
        dy: i32,
        mouse_data: u32,
        flags: u32,
        time: u32,
        extra: u64,
    };

    pub fn move(dx: i32, dy: i32) Input {
        return Input{
            .type = type_mouse,
            .data = .{
                .mouse = MouseData{
                    .dx = dx,
                    .dy = dy,
                    .mouse_data = 0,
                    .flags = flag_move,
                    .time = 0,
                    .extra = marker_injected,
                },
            },
        };
    }

    pub fn move_absolute(x: i32, y: i32) Input {
        const screen = Screen.get();
        const norm_x = to_normalized(x - screen.virtual_left, screen.virtual_width);
        const norm_y = to_normalized(y - screen.virtual_top, screen.virtual_height);

        return Input{
            .type = type_mouse,
            .data = .{
                .mouse = MouseData{
                    .dx = norm_x,
                    .dy = norm_y,
                    .mouse_data = 0,
                    .flags = flag_move | flag_absolute | flag_virtualdesk,
                    .time = 0,
                    .extra = marker_injected,
                },
            },
        };
    }

    pub fn down(button: Button) Input {
        std.debug.assert(button.is_valid());

        return Input{
            .type = type_mouse,
            .data = .{
                .mouse = MouseData{
                    .dx = 0,
                    .dy = 0,
                    .mouse_data = button.xdata(),
                    .flags = button.down_flag(),
                    .time = 0,
                    .extra = marker_injected,
                },
            },
        };
    }

    pub fn up(button: Button) Input {
        std.debug.assert(button.is_valid());

        return Input{
            .type = type_mouse,
            .data = .{
                .mouse = MouseData{
                    .dx = 0,
                    .dy = 0,
                    .mouse_data = button.xdata(),
                    .flags = button.up_flag(),
                    .time = 0,
                    .extra = marker_injected,
                },
            },
        };
    }

    pub fn wheel(delta: i32) Input {
        return Input{
            .type = type_mouse,
            .data = .{
                .mouse = MouseData{
                    .dx = 0,
                    .dy = 0,
                    .mouse_data = @bitCast(delta),
                    .flags = flag_wheel,
                    .time = 0,
                    .extra = marker_injected,
                },
            },
        };
    }

    pub fn wheel_horizontal(delta: i32) Input {
        return Input{
            .type = type_mouse,
            .data = .{
                .mouse = MouseData{
                    .dx = 0,
                    .dy = 0,
                    .mouse_data = @bitCast(delta),
                    .flags = flag_hwheel,
                    .time = 0,
                    .extra = marker_injected,
                },
            },
        };
    }
};

fn to_normalized(value: i32, screen_size: i32) i32 {
    std.debug.assert(screen_size >= 1);

    const normalized: i64 = @divTrunc(@as(i64, value) * 65536, @as(i64, screen_size));

    return @intCast(normalized);
}

pub fn send(input: []Input) u32 {
    std.debug.assert(input.len >= 1);
    std.debug.assert(input.len <= capacity_input);

    const count: u32 = @intCast(input.len);
    const size: i32 = @sizeOf(Input);

    const result = w32.SendInput(count, @ptrCast(input.ptr), size);

    std.debug.assert(result <= count);

    return result;
}

pub fn get_position() Position {
    return monitor_mod.get_cursor_position();
}

pub fn get_monitors() MonitorList {
    return monitor_mod.get_all();
}

pub fn get_monitor(index: u8) ?Monitor {
    return monitor_mod.get(index);
}

pub fn get_primary_monitor() ?Monitor {
    return monitor_mod.get_primary();
}

pub fn get_current_monitor() ?Monitor {
    return monitor_mod.get_current();
}

pub fn get_monitor_at(x: i32, y: i32) ?Monitor {
    return monitor_mod.get_at(x, y);
}

pub fn get_monitor_count() u8 {
    return monitor_mod.get_count();
}

pub fn move_relative(dx: i32, dy: i32) bool {
    var input = [1]Input{Input.move(dx, dy)};

    const sent = send(&input);

    std.debug.assert(sent <= 1);

    return sent == 1;
}

pub fn move_to(x: i32, y: i32) bool {
    var input = [1]Input{Input.move_absolute(x, y)};

    const sent = send(&input);

    std.debug.assert(sent <= 1);

    return sent == 1;
}

pub fn move_to_position(position: Position) bool {
    return move_to(position.x, position.y);
}

pub fn move_to_monitor(index: u8, x: i32, y: i32) bool {
    const monitor = get_monitor(index) orelse return false;
    const pos = monitor.to_absolute(x, y);

    return move_to(pos.x, pos.y);
}

pub fn move_to_monitor_center(index: u8) bool {
    const monitor = get_monitor(index) orelse return false;
    const pos = monitor.center();

    return move_to(pos.x, pos.y);
}

pub fn move_to_primary_monitor(x: i32, y: i32) bool {
    const monitor = get_primary_monitor() orelse return false;
    const pos = monitor.to_absolute(x, y);

    return move_to(pos.x, pos.y);
}

pub fn move_to_primary_center() bool {
    const monitor = get_primary_monitor() orelse return false;
    const pos = monitor.center();

    return move_to(pos.x, pos.y);
}

pub fn click(button: Button) bool {
    std.debug.assert(button.is_valid());

    var input = [2]Input{
        Input.down(button),
        Input.up(button),
    };

    const sent = send(&input);

    std.debug.assert(sent <= 2);

    return sent == 2;
}

pub fn left_click() bool {
    return click(.left);
}

pub fn right_click() bool {
    return click(.right);
}

pub fn middle_click() bool {
    return click(.middle);
}

pub fn double_click(button: Button) bool {
    std.debug.assert(button.is_valid());

    var input = [4]Input{
        Input.down(button),
        Input.up(button),
        Input.down(button),
        Input.up(button),
    };

    const sent = send(&input);

    std.debug.assert(sent <= 4);

    return sent == 4;
}

pub fn left_double_click() bool {
    return double_click(.left);
}

pub fn button_down(button: Button) bool {
    std.debug.assert(button.is_valid());

    var input = [1]Input{Input.down(button)};

    const sent = send(&input);

    std.debug.assert(sent <= 1);

    return sent == 1;
}

pub fn button_up(button: Button) bool {
    std.debug.assert(button.is_valid());

    var input = [1]Input{Input.up(button)};

    const sent = send(&input);

    std.debug.assert(sent <= 1);

    return sent == 1;
}

pub fn scroll_up(clicks: u32) bool {
    std.debug.assert(clicks >= 1);
    std.debug.assert(clicks <= scroll_clicks_max);

    const delta: i32 = @intCast(clicks * @as(u32, @intCast(wheel_delta)));

    var input = [1]Input{Input.wheel(delta)};

    const sent = send(&input);

    std.debug.assert(sent <= 1);

    return sent == 1;
}

pub fn scroll_down(clicks: u32) bool {
    std.debug.assert(clicks >= 1);
    std.debug.assert(clicks <= scroll_clicks_max);

    const delta: i32 = -@as(i32, @intCast(clicks * @as(u32, @intCast(wheel_delta))));

    var input = [1]Input{Input.wheel(delta)};

    const sent = send(&input);

    std.debug.assert(sent <= 1);

    return sent == 1;
}

pub fn scroll_left(clicks: u32) bool {
    std.debug.assert(clicks >= 1);
    std.debug.assert(clicks <= scroll_clicks_max);

    const delta: i32 = -@as(i32, @intCast(clicks * @as(u32, @intCast(wheel_delta))));

    var input = [1]Input{Input.wheel_horizontal(delta)};

    const sent = send(&input);

    std.debug.assert(sent <= 1);

    return sent == 1;
}

pub fn scroll_right(clicks: u32) bool {
    std.debug.assert(clicks >= 1);
    std.debug.assert(clicks <= scroll_clicks_max);

    const delta: i32 = @intCast(clicks * @as(u32, @intCast(wheel_delta)));

    var input = [1]Input{Input.wheel_horizontal(delta)};

    const sent = send(&input);

    std.debug.assert(sent <= 1);

    return sent == 1;
}

pub fn drag(button: Button, from: Position, to: Position) bool {
    std.debug.assert(button.is_valid());

    if (!move_to(from.x, from.y)) {
        return false;
    }

    if (!button_down(button)) {
        return false;
    }

    if (!move_to(to.x, to.y)) {
        _ = button_up(button);
        return false;
    }

    return button_up(button);
}

pub fn left_drag(from: Position, to: Position) bool {
    return drag(.left, from, to);
}

pub fn click_at(button: Button, x: i32, y: i32) bool {
    std.debug.assert(button.is_valid());

    if (!move_to(x, y)) {
        return false;
    }

    return click(button);
}

pub fn left_click_at(x: i32, y: i32) bool {
    return click_at(.left, x, y);
}

pub fn right_click_at(x: i32, y: i32) bool {
    return click_at(.right, x, y);
}

pub fn click_on_monitor(button: Button, index: u8, x: i32, y: i32) bool {
    std.debug.assert(button.is_valid());

    if (!move_to_monitor(index, x, y)) {
        return false;
    }

    return click(button);
}

pub fn left_click_on_monitor(index: u8, x: i32, y: i32) bool {
    return click_on_monitor(.left, index, x, y);
}

pub fn right_click_on_monitor(index: u8, x: i32, y: i32) bool {
    return click_on_monitor(.right, index, x, y);
}
