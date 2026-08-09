const std = @import("std");

const keycode = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const capacity: u16 = 4096;
pub const text_bytes_max: u16 = 256;

pub const Kind = enum(u8) {
    key_down,
    key_up,
    key_press,
    key_combination,
    key_dummy,
    mouse_down,
    mouse_up,
    mouse_move,
    mouse_scroll,
    text_send,
    message_key,
    message_char,
    clipboard_set,
    clipboard_clear,
};

pub const Entry = struct {
    kind: Kind,
    code: Keycode = .silent,
    modifiers: modifier.Set = .{},
    button: u8 = 0,
    x: i32 = 0,
    y: i32 = 0,
    amount: i32 = 0,
    down: bool = false,
    text: [text_bytes_max]u8 = @splat(0),
    text_len: u16 = 0,

    pub fn body(entry: *const Entry) []const u8 {
        assert(entry.text_len <= text_bytes_max);

        return entry.text[0..entry.text_len];
    }
};

var entries: [capacity]Entry = undefined;
var count: u16 = 0;
var overflowed: bool = false;

comptime {
    assert(capacity > 0);
    assert(text_bytes_max > 0);
}

pub fn reset() void {
    count = 0;
    overflowed = false;

    assert(count == 0);
    assert(!overflowed);
}

pub fn push(entry: Entry) void {
    assert(count <= capacity);

    if (count == capacity) {
        overflowed = true;

        return;
    }

    entries[count] = entry;
    count += 1;

    assert(count <= capacity);
}

pub fn push_text(kind: Kind, text: []const u8) void {
    assert(text.len <= text_bytes_max);

    var entry = Entry{ .kind = kind };
    const length = @min(text.len, text_bytes_max);

    @memcpy(entry.text[0..length], text[0..length]);

    entry.text_len = @intCast(length);

    push(entry);
}

pub fn len() u16 {
    assert(count <= capacity);

    return count;
}

pub fn at(index: u16) Entry {
    assert(index < count);

    return entries[index];
}

pub fn last() ?Entry {
    if (count == 0) {
        return null;
    }

    assert(count >= 1);

    return entries[count - 1];
}

pub fn is_overflowed() bool {
    return overflowed;
}

pub fn count_of(kind: Kind) u16 {
    assert(count <= capacity);

    var total: u16 = 0;
    var index: u16 = 0;

    while (index < count) : (index += 1) {
        if (entries[index].kind == kind) {
            total += 1;
        }
    }

    assert(total <= count);

    return total;
}

pub fn contains(kind: Kind, code: Keycode) bool {
    assert(count <= capacity);

    var index: u16 = 0;

    while (index < count) : (index += 1) {
        const entry = entries[index];

        if (entry.kind == kind and entry.code == code) {
            return true;
        }
    }

    return false;
}
