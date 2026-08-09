const std = @import("std");

const key_event = @import("../../event/key.zig");
const keycode = @import("../../keycode.zig");
const mapping = @import("keycode.zig");
const modifier = @import("../../modifier.zig");
const mouse_event = @import("../../event/mouse.zig");
const simulate_key = @import("simulate/key.zig");
const simulate_mouse = @import("simulate/mouse.zig");
const time = @import("time.zig");
const win32 = @import("win32.zig");

const assert = std.debug.assert;
const Keycode = keycode.Keycode;
const Key = key_event.Key;
const Mouse = mouse_event.Mouse;
const MouseButton = mouse_event.Button;
const MouseKind = mouse_event.Kind;
const Position = mouse_event.Position;
const Stamp = mouse_event.Stamp;

pub fn parse_key(wparam: win32.WPARAM, lparam: win32.LPARAM) ?Key {
    assert(@sizeOf(win32.WPARAM) >= 4);
    assert(@sizeOf(win32.LPARAM) >= 4);

    const data = key_data(lparam) orelse return null;

    if (is_marked(data.dwExtraInfo, simulate_key.marker_injected)) {
        return null;
    }

    if (!is_keycode_valid(data)) {
        return null;
    }

    const virtual_key: u8 = @truncate(data.vkCode);
    const code = mapping.from_native(virtual_key) orelse return null;

    const result = Key{
        .value = code,
        .down = is_key_down(wparam),
        .injected = data.flags.INJECTED == 1,
        .time_ms = time.now_ms(),
        .modifiers = .{},
    };

    assert(result.modifiers.flags == modifier.flag_none);
    assert(result.is_valid());

    return result;
}

pub fn parse_mouse(wparam: win32.WPARAM, lparam: win32.LPARAM) ?Mouse {
    assert(@sizeOf(win32.WPARAM) >= 4);
    assert(@sizeOf(win32.LPARAM) >= 4);

    const data = mouse_data(lparam) orelse return null;

    if (is_marked(data.dwExtraInfo, simulate_mouse.marker_injected)) {
        return null;
    }

    const position = Position.init(data.pt.x, data.pt.y);
    const stamp = Stamp{ .injected = is_injected(data), .time_ms = time.now_ms() };

    const result = switch (wparam) {
        win32.WM_MOUSEMOVE => Mouse.from_motion(.{ .position = position }, stamp),

        win32.WM_MOUSEWHEEL => Mouse.from_wheel(.{
            .steps_vertical = wheel_steps(data.mouseData),
            .position = position,
        }, stamp),

        win32.WM_MOUSEHWHEEL => Mouse.from_wheel(.{
            .steps_horizontal = wheel_steps(data.mouseData),
            .position = position,
        }, stamp),

        else => Mouse.from_button(.{
            .button = mouse_button(wparam, data.mouseData) orelse return null,
            .down = is_button_down(wparam),
            .position = position,
        }, stamp),
    };

    assert(result.is_valid());

    return result;
}

pub fn wheel_steps(mouse_data_word: u32) i32 {
    assert(win32.WHEEL_DELTA == 120);

    const high: i16 = @bitCast(@as(u16, @truncate(mouse_data_word >> 16)));
    const delta: i32 = high;

    return @divTrunc(delta, win32.WHEEL_DELTA);
}

pub fn mouse_button(wparam: win32.WPARAM, mouse_data_word: u32) ?MouseButton {
    return switch (wparam) {
        win32.WM_LBUTTONDOWN, win32.WM_LBUTTONUP => .left,
        win32.WM_RBUTTONDOWN, win32.WM_RBUTTONUP => .right,
        win32.WM_MBUTTONDOWN, win32.WM_MBUTTONUP => .middle,
        win32.WM_XBUTTONDOWN, win32.WM_XBUTTONUP => extra_button(mouse_data_word),
        else => null,
    };
}

fn extra_button(mouse_data_word: u32) ?MouseButton {
    const high: u16 = @truncate(mouse_data_word >> 16);

    return switch (high) {
        win32.XBUTTON1 => .x1,
        win32.XBUTTON2 => .x2,
        else => null,
    };
}

fn is_button_down(wparam: win32.WPARAM) bool {
    return switch (wparam) {
        win32.WM_LBUTTONDOWN => true,
        win32.WM_RBUTTONDOWN => true,
        win32.WM_MBUTTONDOWN => true,
        win32.WM_XBUTTONDOWN => true,
        else => false,
    };
}

fn is_injected(data: *win32.MSLLHOOKSTRUCT) bool {
    return (data.flags & win32.LLMHF_INJECTED) != 0;
}

fn is_marked(extra: usize, marker: u64) bool {
    assert(marker != 0);

    return @as(u64, extra) == marker;
}

pub fn key_data(lparam: win32.LPARAM) ?*win32.KBDLLHOOKSTRUCT {
    const size_64 = @sizeOf(win32.LPARAM) == @sizeOf(u64);
    const size_32 = @sizeOf(win32.LPARAM) == @sizeOf(u32);

    assert(size_64 or size_32);

    if (lparam == 0) {
        return null;
    }

    const address: u64 = @intCast(lparam);

    assert(address != 0);

    return @ptrFromInt(address);
}

fn mouse_data(lparam: win32.LPARAM) ?*win32.MSLLHOOKSTRUCT {
    assert(@sizeOf(win32.LPARAM) >= 4);

    if (lparam == 0) {
        return null;
    }

    const address: u64 = @intCast(lparam);

    assert(address != 0);

    return @ptrFromInt(address);
}

fn is_keycode_valid(data: *win32.KBDLLHOOKSTRUCT) bool {
    const above = data.vkCode >= mapping.value_min;
    const below = data.vkCode <= mapping.value_max;

    return above and below;
}

fn is_key_down(wparam: win32.WPARAM) bool {
    assert(wparam != 0);

    const is_keydown = wparam == win32.WM_KEYDOWN;
    const is_syskeydown = wparam == win32.WM_SYSKEYDOWN;

    return is_keydown or is_syskeydown;
}

const testing = std.testing;

test "wheel_steps recovers signed detents from the high word" {
    try testing.expectEqual(@as(i32, 1), wheel_steps(120 << 16));
    try testing.expectEqual(@as(i32, 3), wheel_steps(360 << 16));
    try testing.expectEqual(@as(i32, -1), wheel_steps(@as(u32, 0xFF88) << 16));
    try testing.expectEqual(@as(i32, 0), wheel_steps(0));
}

test "wheel_steps ignores the low word" {
    try testing.expectEqual(@as(i32, 1), wheel_steps((120 << 16) | 0xFFFF));
}

test "mouse_button maps every button message" {
    try testing.expectEqual(MouseButton.left, mouse_button(win32.WM_LBUTTONDOWN, 0).?);
    try testing.expectEqual(MouseButton.left, mouse_button(win32.WM_LBUTTONUP, 0).?);
    try testing.expectEqual(MouseButton.right, mouse_button(win32.WM_RBUTTONDOWN, 0).?);
    try testing.expectEqual(MouseButton.middle, mouse_button(win32.WM_MBUTTONUP, 0).?);
    try testing.expect(mouse_button(win32.WM_MOUSEMOVE, 0) == null);
}

test "mouse_button separates the two side buttons" {
    const first: u32 = @as(u32, win32.XBUTTON1) << 16;
    const second: u32 = @as(u32, win32.XBUTTON2) << 16;

    try testing.expectEqual(MouseButton.x1, mouse_button(win32.WM_XBUTTONDOWN, first).?);
    try testing.expectEqual(MouseButton.x2, mouse_button(win32.WM_XBUTTONUP, second).?);
    try testing.expect(mouse_button(win32.WM_XBUTTONDOWN, 0) == null);
}

test "button messages carry their direction" {
    try testing.expect(is_button_down(win32.WM_LBUTTONDOWN));
    try testing.expect(is_button_down(win32.WM_XBUTTONDOWN));
    try testing.expect(!is_button_down(win32.WM_LBUTTONUP));
    try testing.expect(!is_button_down(win32.WM_MOUSEMOVE));
}

test "every neutral kind is reachable from a mouse message" {
    try testing.expectEqual(MouseKind.left_down, MouseKind.from_button(.left, true));
    try testing.expectEqual(MouseKind.x_up, MouseKind.from_button(.x2, false));
}

fn hook_mouse(x: i32, y: i32, mouse_data_word: u32) win32.MSLLHOOKSTRUCT {
    return win32.MSLLHOOKSTRUCT{
        .pt = .{ .x = x, .y = y },
        .mouseData = mouse_data_word,
        .flags = 0,
        .time = 0,
        .dwExtraInfo = 0,
    };
}

fn hook_mouse_tagged(flags: u32, extra: usize) win32.MSLLHOOKSTRUCT {
    return win32.MSLLHOOKSTRUCT{
        .pt = .{ .x = 0, .y = 0 },
        .mouseData = 0,
        .flags = flags,
        .time = 0,
        .dwExtraInfo = extra,
    };
}

fn hook_key(
    virtual_key: u32,
    flags: win32.KBDLLHOOKSTRUCT_FLAGS,
    extra: usize,
) win32.KBDLLHOOKSTRUCT {
    return win32.KBDLLHOOKSTRUCT{
        .vkCode = virtual_key,
        .scanCode = 0,
        .flags = flags,
        .time = 0,
        .dwExtraInfo = extra,
    };
}

test "a key down message parses into a neutral key with no modifiers" {
    var data = hook_key(0x41, .{}, 0);

    const parsed = parse_key(win32.WM_KEYDOWN, @intCast(@intFromPtr(&data))).?;

    try testing.expectEqual(Keycode.a, parsed.value);
    try testing.expect(parsed.down);
    try testing.expect(!parsed.injected);
    try testing.expectEqual(modifier.flag_none, parsed.modifiers.flags);
}

test "a key up message parses with its direction reversed" {
    var data = hook_key(0x41, .{ .UP = 1 }, 0);

    const parsed = parse_key(win32.WM_KEYUP, @intCast(@intFromPtr(&data))).?;

    try testing.expectEqual(Keycode.a, parsed.value);
    try testing.expect(!parsed.down);
}

test "a system key down counts as a key down" {
    var data = hook_key(0x41, .{}, 0);

    const parsed = parse_key(win32.WM_SYSKEYDOWN, @intCast(@intFromPtr(&data))).?;

    try testing.expect(parsed.down);
}

test "a foreign injected key keeps the injected flag Windows set" {
    var data = hook_key(0x41, .{ .INJECTED = 1 }, 0);

    const parsed = parse_key(win32.WM_KEYDOWN, @intCast(@intFromPtr(&data))).?;

    try testing.expect(parsed.injected);
}

test "a key nimble injected itself is invisible to the hook" {
    var data = hook_key(0x41, .{ .INJECTED = 1 }, simulate_key.marker_injected);

    try testing.expect(parse_key(win32.WM_KEYDOWN, @intCast(@intFromPtr(&data))) == null);
}

test "an out of range virtual key produces no neutral key" {
    var below = hook_key(0, .{}, 0);
    var above = hook_key(mapping.value_dummy, .{}, 0);

    try testing.expect(parse_key(win32.WM_KEYDOWN, @intCast(@intFromPtr(&below))) == null);
    try testing.expect(parse_key(win32.WM_KEYDOWN, @intCast(@intFromPtr(&above))) == null);
}

test "an unmapped virtual key produces no neutral key" {
    var data = hook_key(0x07, .{}, 0);

    try testing.expect(parse_key(win32.WM_KEYDOWN, @intCast(@intFromPtr(&data))) == null);
}

test "a hook message without a payload produces no neutral event" {
    try testing.expect(parse_key(win32.WM_KEYDOWN, 0) == null);
    try testing.expect(parse_mouse(win32.WM_MOUSEMOVE, 0) == null);
}

test "a foreign injected mouse event keeps the injected flag Windows set" {
    var data = hook_mouse_tagged(win32.LLMHF_INJECTED, 0);

    const parsed = parse_mouse(win32.WM_LBUTTONDOWN, @intCast(@intFromPtr(&data))).?;

    try testing.expect(parsed.injected);
}

test "a mouse event nimble injected itself is invisible to the hook" {
    var data = hook_mouse_tagged(win32.LLMHF_INJECTED, simulate_mouse.marker_injected);

    try testing.expect(parse_mouse(win32.WM_LBUTTONDOWN, @intCast(@intFromPtr(&data))) == null);
}

test "an unflagged mouse event is not reported as injected" {
    var data = hook_mouse_tagged(0, 0);

    const parsed = parse_mouse(win32.WM_LBUTTONDOWN, @intCast(@intFromPtr(&data))).?;

    try testing.expect(!parsed.injected);
}

test "the key and mouse markers never collide" {
    try testing.expect(simulate_key.marker_injected != simulate_mouse.marker_injected);
}

test "a wheel message parses into one signed neutral step" {
    var data = hook_mouse(4, 5, 120 << 16);

    const parsed = parse_mouse(win32.WM_MOUSEWHEEL, @intCast(@intFromPtr(&data))).?;

    try testing.expectEqual(MouseKind.wheel, parsed.kind);
    try testing.expectEqual(@as(i32, 1), parsed.payload.wheel.steps_vertical);
    try testing.expectEqual(@as(i32, 0), parsed.payload.wheel.steps_horizontal);
    try testing.expect(parsed.position().?.eql(Position.init(4, 5)));
}

test "a horizontal wheel message lands on the horizontal axis" {
    var data = hook_mouse(0, 0, @as(u32, 0xFF88) << 16);

    const parsed = parse_mouse(win32.WM_MOUSEHWHEEL, @intCast(@intFromPtr(&data))).?;

    try testing.expectEqual(MouseKind.wheel, parsed.kind);
    try testing.expectEqual(@as(i32, 0), parsed.payload.wheel.steps_vertical);
    try testing.expectEqual(@as(i32, -1), parsed.payload.wheel.steps_horizontal);
}

test "a button message parses into a button payload carrying its position" {
    var data = hook_mouse(11, 22, 0);

    const parsed = parse_mouse(win32.WM_LBUTTONDOWN, @intCast(@intFromPtr(&data))).?;

    try testing.expectEqual(MouseKind.left_down, parsed.kind);
    try testing.expectEqual(MouseButton.left, parsed.button().?);
    try testing.expect(parsed.is_down());
    try testing.expect(parsed.position().?.eql(Position.init(11, 22)));
}

test "a move message parses into a motion payload with an absolute position" {
    var data = hook_mouse(-3, 9, 0);

    const parsed = parse_mouse(win32.WM_MOUSEMOVE, @intCast(@intFromPtr(&data))).?;

    try testing.expectEqual(MouseKind.move, parsed.kind);
    try testing.expect(parsed.position().?.eql(Position.init(-3, 9)));
}

test "an unrecognised mouse message produces no neutral event" {
    var data = hook_mouse(0, 0, 0);

    try testing.expect(parse_mouse(0x0FFF, @intCast(@intFromPtr(&data))) == null);
}
