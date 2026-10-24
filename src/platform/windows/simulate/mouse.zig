const std = @import("std");

const monitor = @import("../monitor.zig");
const mouse_event = @import("../../../event/mouse.zig");
const position_module = @import("../../../position.zig");
const win32 = @import("../win32.zig");

const assert = std.debug.assert;

const Position = position_module.Position;

pub const Button = mouse_event.MouseEvent.Button;

pub const marker_injected: u64 = 0x102;
const capacity_input: u8 = 8;
pub const scroll_clicks_max: u32 = 100;
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

const Desktop = struct {
    left: i32,
    top: i32,
    width: i32,
    height: i32,

    fn query() Desktop {
        const result = Desktop{
            .left = win32.GetSystemMetrics(win32.SM_XVIRTUALSCREEN),
            .top = win32.GetSystemMetrics(win32.SM_YVIRTUALSCREEN),
            .width = win32.GetSystemMetrics(win32.SM_CXVIRTUALSCREEN),
            .height = win32.GetSystemMetrics(win32.SM_CYVIRTUALSCREEN),
        };

        assert(result.width >= 0);
        assert(result.height >= 0);

        return result;
    }
};

fn flag_down_of(button: Button) u32 {
    assert(button.is_valid());

    return switch (button) {
        .left => flag_leftdown,
        .right => flag_rightdown,
        .middle => flag_middledown,
        .x1, .x2 => flag_xdown,
    };
}

fn flag_up_of(button: Button) u32 {
    assert(button.is_valid());

    return switch (button) {
        .left => flag_leftup,
        .right => flag_rightup,
        .middle => flag_middleup,
        .x1, .x2 => flag_xup,
    };
}

fn xdata_of(button: Button) u32 {
    assert(button.is_valid());

    return switch (button) {
        .x1 => xbutton1,
        .x2 => xbutton2,
        else => 0,
    };
}

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

    pub fn move_absolute(position: Position) Input {
        const desktop = Desktop.query();
        const norm_x = to_normalized(position.x - desktop.left, desktop.width);
        const norm_y = to_normalized(position.y - desktop.top, desktop.height);

        assert(norm_x >= 0);
        assert(norm_x <= 65535);
        assert(norm_y >= 0);
        assert(norm_y <= 65535);

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
        assert(button.is_valid());

        return Input{
            .type = type_mouse,
            .data = .{
                .mouse = MouseData{
                    .dx = 0,
                    .dy = 0,
                    .mouse_data = xdata_of(button),
                    .flags = flag_down_of(button),
                    .time = 0,
                    .extra = marker_injected,
                },
            },
        };
    }

    pub fn up(button: Button) Input {
        assert(button.is_valid());

        return Input{
            .type = type_mouse,
            .data = .{
                .mouse = MouseData{
                    .dx = 0,
                    .dy = 0,
                    .mouse_data = xdata_of(button),
                    .flags = flag_up_of(button),
                    .time = 0,
                    .extra = marker_injected,
                },
            },
        };
    }

    pub fn wheel(delta: i32) Input {
        assert(delta != 0);
        assert(@rem(delta, wheel_delta) == 0);
        assert(delta >= -(wheel_delta * @as(i32, scroll_clicks_max)));
        assert(delta <= wheel_delta * @as(i32, scroll_clicks_max));

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
        assert(delta != 0);
        assert(@rem(delta, wheel_delta) == 0);
        assert(delta >= -(wheel_delta * @as(i32, scroll_clicks_max)));
        assert(delta <= wheel_delta * @as(i32, scroll_clicks_max));

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
    if (screen_size < 1) {
        return 0;
    }

    const size: i64 = screen_size;
    const scaled: i64 = @as(i64, value) * 65536;
    const normalized: i64 = @divFloor(scaled + size - 1, size);
    const clamped: i64 = std.math.clamp(normalized, 0, 65535);

    assert(clamped >= 0);
    assert(clamped <= 65535);

    return @intCast(clamped);
}

pub fn send(input: []Input) u32 {
    assert(input.len >= 1);
    assert(input.len <= capacity_input);

    const count: u32 = @intCast(input.len);
    const size: i32 = @sizeOf(Input);
    const result = win32.SendInput(count, @ptrCast(input.ptr), size);

    assert(result <= count);

    return result;
}

pub fn get_position() Position {
    return monitor.get_cursor_position();
}

pub fn move_relative(offset: Position) bool {
    return move_to(offset_target(get_position(), offset));
}

fn offset_target(current: Position, offset: Position) Position {
    return Position{
        .x = current.x +| offset.x,
        .y = current.y +| offset.y,
    };
}

pub fn move_to(position: Position) bool {
    var input = [1]Input{Input.move_absolute(position)};

    const sent = send(&input);

    assert(sent <= 1);

    return sent == 1;
}

pub fn click(button: Button) bool {
    assert(button.is_valid());

    var input = [2]Input{
        Input.down(button),
        Input.up(button),
    };

    const sent = send(&input);

    assert(sent <= 2);

    return sent == 2;
}

pub fn button_down(button: Button) bool {
    assert(button.is_valid());

    var input = [1]Input{Input.down(button)};

    const sent = send(&input);

    assert(sent <= 1);

    return sent == 1;
}

pub fn button_up(button: Button) bool {
    assert(button.is_valid());

    var input = [1]Input{Input.up(button)};

    const sent = send(&input);

    assert(sent <= 1);

    return sent == 1;
}

pub fn scroll_up(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    const delta: i32 = @intCast(clicks * @as(u32, @intCast(wheel_delta)));

    var input = [1]Input{Input.wheel(delta)};

    const sent = send(&input);

    assert(sent <= 1);

    return sent == 1;
}

pub fn scroll_down(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    const delta: i32 = -@as(i32, @intCast(clicks * @as(u32, @intCast(wheel_delta))));

    var input = [1]Input{Input.wheel(delta)};

    const sent = send(&input);

    assert(sent <= 1);

    return sent == 1;
}

pub fn scroll_left(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    const delta: i32 = -@as(i32, @intCast(clicks * @as(u32, @intCast(wheel_delta))));

    var input = [1]Input{Input.wheel_horizontal(delta)};

    const sent = send(&input);

    assert(sent <= 1);

    return sent == 1;
}

pub fn scroll_right(clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    const delta: i32 = @intCast(clicks * @as(u32, @intCast(wheel_delta)));

    var input = [1]Input{Input.wheel_horizontal(delta)};

    const sent = send(&input);

    assert(sent <= 1);

    return sent == 1;
}

const testing = std.testing;

test "a relative move targets the cursor plus its offset" {
    const target = offset_target(.{ .x = 512, .y = 384 }, .{ .x = 100, .y = -50 });

    try testing.expectEqual(Position{ .x = 612, .y = 334 }, target);
}

test "a relative move saturates at the coordinate bounds" {
    const max = std.math.maxInt(i32);
    const min = std.math.minInt(i32);
    const high = offset_target(.{ .x = max - 1, .y = 0 }, .{ .x = 10, .y = 0 });
    const low = offset_target(.{ .x = 0, .y = min + 1 }, .{ .x = 0, .y = -10 });

    try testing.expectEqual(Position{ .x = max, .y = 0 }, high);
    try testing.expectEqual(Position{ .x = 0, .y = min }, low);
}

test "a wheel input encodes its delta" {
    const event = Input.wheel(wheel_delta);

    try testing.expectEqual(@as(u32, 120), event.data.mouse.mouse_data);
    try testing.expectEqual(@as(u32, 0x0800), event.data.mouse.flags);
}

test "a wheel input encodes a negative delta" {
    const event = Input.wheel(-wheel_delta);

    try testing.expectEqual(@as(u32, @bitCast(@as(i32, -120))), event.data.mouse.mouse_data);
}

test "a horizontal wheel input encodes its delta" {
    const event = Input.wheel_horizontal(wheel_delta);

    try testing.expectEqual(@as(u32, 120), event.data.mouse.mouse_data);
    try testing.expectEqual(@as(u32, 0x1000), event.data.mouse.flags);
}

test "an absolute mouse move is normalised into bounds" {
    const event = Input.move_absolute(.zero);

    try testing.expect(event.data.mouse.dx >= 0);
    try testing.expect(event.data.mouse.dx <= 65535);
    try testing.expect(event.data.mouse.dy >= 0);
    try testing.expect(event.data.mouse.dy <= 65535);
}

test "each pixel survives the trip through normalised coordinates" {
    const sizes = [_]i32{ 768, 1024, 1080, 1440, 1920, 2560, 3840, 7680 };

    for (sizes) |size| {
        var pixel: i32 = 0;

        while (pixel < size) : (pixel += 1) {
            const normalized = to_normalized(pixel, size);
            const decoded = @divFloor(@as(i64, normalized) * size, 65536);

            try testing.expectEqual(@as(i64, pixel), decoded);
        }
    }
}

test "a position outside the desktop clamps to its edge" {
    try testing.expectEqual(@as(i32, 0), to_normalized(-50, 1024));
    try testing.expectEqual(@as(i32, 65535), to_normalized(5000, 1024));
}

test "a mouse button maps to its flags" {
    try testing.expectEqual(@as(u32, 0x0002), flag_down_of(.left));
    try testing.expectEqual(@as(u32, 0x0004), flag_up_of(.left));
    try testing.expectEqual(@as(u32, 0x0080), flag_down_of(.x1));
    try testing.expectEqual(@as(u32, 0x0001), xdata_of(.x1));
    try testing.expectEqual(@as(u32, 0x0002), xdata_of(.x2));
    try testing.expectEqual(@as(u32, 0), xdata_of(.middle));
}

test "mouse limits" {
    try testing.expect(scroll_clicks_max >= 1);
    try testing.expect(wheel_delta == 120);
}

test {
    testing.refAllDecls(@This());
}
