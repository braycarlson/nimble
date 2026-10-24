const std = @import("std");

const keycode = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");
const record = @import("record.zig");
const simulate_key = @import("simulate/key.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const text_bytes_max: u16 = 4096;
const select_count_max: u32 = 1024;

pub const Error = error{
    CountInvalid,
    SendFailed,
    TextTooLong,
};

pub const ReadError = error{ClipboardEmpty};
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

pub fn get(buffer: []u8) ReadError![]const u8 {
    assert(buffer.len > 0);

    if (length == 0) {
        return error.ClipboardEmpty;
    }

    const size = @min(buffer.len, length);

    @memcpy(buffer[0..size], storage[0..size]);

    assert(size <= length);

    return buffer[0..size];
}

pub fn reset() void {
    length = 0;

    assert(length == 0);
}

pub fn paste() bool {
    return simulate_key.combination(&ctrl, .v);
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

fn select_left(count: u32) Error!void {
    assert(count > 0);

    if (count > select_count_max) {
        return Error.CountInvalid;
    }

    if (!simulate_key.key_down(Keycode.shift_left)) {
        return Error.SendFailed;
    }

    var index: u32 = 0;

    while (index < count) : (index += 1) {
        if (!simulate_key.press(.arrow_left)) {
            return Error.SendFailed;
        }
    }

    assert(index == count);

    if (!simulate_key.key_up(Keycode.shift_left)) {
        return Error.SendFailed;
    }
}

const testing = std.testing;

test "the mock clipboard holds what was set until it is reset" {
    reset();
    record.reset();

    var buffer: [16]u8 = undefined;

    try testing.expectError(error.ClipboardEmpty, get(&buffer));
    try set("nimble");
    try testing.expectEqualStrings("nimble", try get(&buffer));
    try testing.expectEqual(@as(u16, 1), record.count_of(.clipboard_set));

    reset();

    try testing.expectError(error.ClipboardEmpty, get(&buffer));
}

test "replacing selects the old text before pasting the new" {
    record.reset();

    try replace(3, "abc");

    try testing.expectEqual(@as(u16, 3), record.count_of(.key_press));
    try testing.expectError(Error.CountInvalid, replace(select_count_max + 1, "x"));
}
