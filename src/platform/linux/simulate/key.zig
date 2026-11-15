const std = @import("std");

const evdev = @import("../evdev.zig");
const keycode = @import("../../../keycode.zig");
const mapping = @import("../keycode.zig");
const modifier = @import("../../../modifier.zig");
const uinput = @import("../uinput.zig");

const assert = std.debug.assert;

const linux = std.os.linux;

const Device = uinput.Device;
const Keycode = keycode.Keycode;

const capacity_input: u8 = 16;

const modifier_codes = [_]Keycode{
    .control_left,
    .control_right,
    .alt_left,
    .alt_right,
    .shift_left,
    .shift_right,
    .super_left,
    .super_right,
};

comptime {
    assert(capacity_input >= 4);
    assert(modifier_codes.len == modifier.Set.kind_count * 2);
}

pub fn is_open(out: *const Device) bool {
    return out.is_open();
}

pub fn emit(out: *Device, code: Keycode, down: bool) bool {
    if (!out.is_open()) {
        return false;
    }

    out.key(code, down) catch return false;

    return true;
}

pub fn key_down(out: *Device, code: Keycode) bool {
    return emit(out, code, true);
}

pub fn key_up(out: *Device, code: Keycode) bool {
    return emit(out, code, false);
}

pub fn press(out: *Device, code: Keycode) bool {
    const down = emit(out, code, true);
    const up = emit(out, code, false);

    return down and up;
}

pub fn suppress(out: *Device, code: Keycode) bool {
    const dummied = dummy(out);
    const released = emit(out, code, false);

    return dummied and released;
}

pub fn release_modifiers(out: *Device) bool {
    if (!out.is_open()) {
        return false;
    }

    var released = true;
    var dummied = false;

    for (modifier_codes) |code| {
        const native = mapping.to_native(code) orelse continue;
        if (!out.is_down(native)) continue;

        if (!dummied) {
            dummied = true;
            released = dummy(out) and released;
        }

        released = emit(out, code, false) and released;
    }

    return released;
}

pub fn dummy(out: *Device) bool {
    if (!out.is_open()) {
        return false;
    }

    out.dummy() catch return false;

    return true;
}

pub fn combination(out: *Device, modifiers: *const modifier.Set, code: Keycode) bool {
    const array = modifiers.to_array();
    var index: u8 = 0;

    while (index < modifier.Set.kind_count) : (index += 1) {
        if (array[index]) |kind| {
            _ = emit(out, kind.to_keycode(), true);
        }
    }

    const pressed = press(out, code);

    var back: u8 = modifier.Set.kind_count;

    while (back > 0) : (back -= 1) {
        if (array[back - 1]) |kind| {
            _ = emit(out, kind.to_keycode(), false);
        }
    }

    assert(back == 0);

    return pressed;
}

const testing = std.testing;

const key_a: u16 = 30;
const key_leftctrl: u16 = 29;
const key_leftmeta: u16 = 125;

const Stroke = struct {
    code: u16,
    value: i32,
};

fn capture_close(out: *Device, pair: *const [2]i32) void {
    out.* = .{};

    _ = linux.close(pair[0]);
    _ = linux.close(pair[1]);
}

fn capture_open(out: *Device, pair: *[2]i32) !void {
    const status = linux.pipe2(pair, .{ .CLOEXEC = true, .NONBLOCK = true });

    try testing.expectEqual(linux.E.SUCCESS, linux.errno(status));

    out.* = .{ .fd = pair[1], .kind = .keyboard };
}

fn capture_read(read_end: i32, strokes: []Stroke) !usize {
    assert(read_end >= 0);
    assert(strokes.len > 0);

    var events: [capacity_input * 2]evdev.Event = undefined;
    const bytes = std.mem.sliceAsBytes(&events);
    const status = linux.read(read_end, bytes.ptr, bytes.len);
    if (linux.errno(status) == .AGAIN) return 0;

    try testing.expectEqual(linux.E.SUCCESS, linux.errno(status));
    try testing.expectEqual(@as(usize, 0), status % @sizeOf(evdev.Event));

    var count: usize = 0;

    for (events[0 .. status / @sizeOf(evdev.Event)]) |event| {
        if (event.type != evdev.EV_KEY) continue;

        try testing.expect(count < strokes.len);

        strokes[count] = .{ .code = event.code, .value = event.value };
        count += 1;
    }

    return count;
}

test "synthesis is inert until the runtime opens its device" {
    var out = Device{};

    try testing.expect(!is_open(&out));
    try testing.expect(!press(&out, .a));
    try testing.expect(!key_down(&out, .control_left));
    try testing.expect(!dummy(&out));
}

test "suppress taps the dummy key while the modifier is still held" {
    var out = Device{};
    var pair: [2]i32 = .{ -1, -1 };

    try capture_open(&out, &pair);
    defer capture_close(&out, &pair);

    try testing.expect(key_down(&out, .super_left));
    try testing.expect(suppress(&out, .super_left));

    var strokes: [capacity_input]Stroke = undefined;
    const count = try capture_read(pair[0], &strokes);

    const expected = [_]Stroke{
        .{ .code = key_leftmeta, .value = evdev.value_down },
        .{ .code = evdev.KEY_UNKNOWN, .value = evdev.value_down },
        .{ .code = evdev.KEY_UNKNOWN, .value = evdev.value_up },
        .{ .code = key_leftmeta, .value = evdev.value_up },
    };

    try testing.expectEqualSlices(Stroke, &expected, strokes[0..count]);
    try testing.expect(!out.is_down(key_leftmeta));
    try testing.expect(!out.is_down(evdev.KEY_UNKNOWN));
}

test "releasing modifiers taps the dummy key once before the first release" {
    var out = Device{};
    var pair: [2]i32 = .{ -1, -1 };

    try capture_open(&out, &pair);
    defer capture_close(&out, &pair);

    try testing.expect(key_down(&out, .control_left));
    try testing.expect(key_down(&out, .super_left));
    try testing.expect(release_modifiers(&out));

    var strokes: [capacity_input]Stroke = undefined;
    const count = try capture_read(pair[0], &strokes);

    const expected = [_]Stroke{
        .{ .code = key_leftctrl, .value = evdev.value_down },
        .{ .code = key_leftmeta, .value = evdev.value_down },
        .{ .code = evdev.KEY_UNKNOWN, .value = evdev.value_down },
        .{ .code = evdev.KEY_UNKNOWN, .value = evdev.value_up },
        .{ .code = key_leftctrl, .value = evdev.value_up },
        .{ .code = key_leftmeta, .value = evdev.value_up },
    };

    try testing.expectEqualSlices(Stroke, &expected, strokes[0..count]);
}

test "releasing modifiers with none held writes nothing" {
    var out = Device{};
    var pair: [2]i32 = .{ -1, -1 };

    try capture_open(&out, &pair);
    defer capture_close(&out, &pair);

    try testing.expect(press(&out, .a));
    try testing.expect(release_modifiers(&out));

    var strokes: [capacity_input]Stroke = undefined;
    const count = try capture_read(pair[0], &strokes);

    const expected = [_]Stroke{
        .{ .code = key_a, .value = evdev.value_down },
        .{ .code = key_a, .value = evdev.value_up },
    };

    try testing.expectEqualSlices(Stroke, &expected, strokes[0..count]);
}
