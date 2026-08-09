const std = @import("std");

const keycode = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");
const record = @import("record.zig");
const simulate_key = @import("simulate/key.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const text_bytes_max: u16 = 4096;
pub const select_count_max: u32 = 1024;

pub const Error = error{
    ClipboardBusy,
    ClipboardEmpty,
    InvalidCount,
    OutOfMemory,
    SendFailed,
    TextTooLong,
};

const ctrl = modifier.Set.from(.{ .ctrl = true });

var storage: [text_bytes_max]u8 = @splat(0);
var length: u16 = 0;

comptime {
    assert(text_bytes_max > 0);
}

pub fn set(text: []const u8) Error!void {
    if (text.len > text_bytes_max) {
        return Error.TextTooLong;
    }

    assert(text.len <= text_bytes_max);

    @memcpy(storage[0..text.len], text);

    length = @intCast(text.len);

    record.push_text(.clipboard_set, text);

    assert(length == text.len);
}

pub fn get(buffer: []u8) Error![]const u8 {
    assert(buffer.len > 0);

    if (length == 0) {
        return Error.ClipboardEmpty;
    }

    const size = @min(buffer.len, length);

    @memcpy(buffer[0..size], storage[0..size]);

    assert(size <= length);

    return buffer[0..size];
}

pub fn clear() Error!void {
    length = 0;

    record.push(.{ .kind = .clipboard_clear });

    assert(length == 0);
}

pub fn reset() void {
    length = 0;

    assert(length == 0);
}

pub fn paste() bool {
    return simulate_key.combination(&ctrl, .v);
}

pub fn copy() bool {
    return simulate_key.combination(&ctrl, .c);
}

pub fn cut() bool {
    return simulate_key.combination(&ctrl, .x);
}

pub fn select_all() bool {
    return simulate_key.combination(&ctrl, .a);
}

pub fn select_left(count: u32) Error!void {
    return select(count, .arrow_left);
}

pub fn select_right(count: u32) Error!void {
    return select(count, .arrow_right);
}

fn select(count: u32, direction: Keycode) Error!void {
    assert(count > 0);
    assert(direction == .arrow_left or direction == .arrow_right);

    if (count > select_count_max) {
        return Error.InvalidCount;
    }

    if (!simulate_key.key_down(Keycode.shift_left)) {
        return Error.SendFailed;
    }

    var index: u32 = 0;

    while (index < count) : (index += 1) {
        if (!simulate_key.press(direction)) {
            return Error.SendFailed;
        }
    }

    assert(index == count);

    if (!simulate_key.key_up(Keycode.shift_left)) {
        return Error.SendFailed;
    }
}

pub fn replace(select_count: u32, text: []const u8) Error!void {
    assert(select_count > 0);
    assert(text.len > 0);

    try select_left(select_count);
    try set(text);

    if (!paste()) {
        return Error.SendFailed;
    }
}

pub const Clipboard = struct {
    pub fn init() Clipboard {
        return Clipboard{};
    }

    pub fn set(_: Clipboard, text: []const u8) Error!void {
        return @This().set_text(text);
    }

    pub fn set_text(text: []const u8) Error!void {
        return @import("clipboard.zig").set(text);
    }

    pub fn get(_: Clipboard, buffer: []u8) Error![]const u8 {
        return @import("clipboard.zig").get(buffer);
    }

    pub fn clear(_: Clipboard) Error!void {
        return @import("clipboard.zig").clear();
    }

    pub fn paste(_: Clipboard) bool {
        return @import("clipboard.zig").paste();
    }

    pub fn copy(_: Clipboard) bool {
        return @import("clipboard.zig").copy();
    }

    pub fn cut(_: Clipboard) bool {
        return @import("clipboard.zig").cut();
    }

    pub fn select_all(_: Clipboard) bool {
        return @import("clipboard.zig").select_all();
    }

    pub fn replace(_: Clipboard, select_count: u32, text: []const u8) Error!void {
        assert(select_count > 0);
        assert(text.len > 0);

        return @import("clipboard.zig").replace(select_count, text);
    }
};
