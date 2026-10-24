const std = @import("std");

const key = @import("key.zig");
const keycode = @import("../../../keycode.zig");
const loop = @import("../loop.zig");
const win32 = @import("../win32.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

pub const text_max: u32 = 4096;
const delay_ms_max: u32 = 1000;

pub const Error = error{
    DelayInvalid,
    SendFailed,
    TextInvalid,
    TextTooLong,
};

const Stroke = union(enum) {
    skip,
    press: Keycode,
    character: u21,
};

fn stroke_of(previous: u21, codepoint: u21) Stroke {
    assert(codepoint <= 0x10FFFF);

    return switch (codepoint) {
        '\n' => if (previous == '\r') .skip else .{ .press = .enter },
        '\r' => .{ .press = .enter },
        '\t' => .{ .press = .tab },
        0x00...0x08, 0x0B...0x0C, 0x0E...0x1F, 0x7F => .skip,
        else => .{ .character = codepoint },
    };
}

fn send_codepoints(text: []const u8, delay_ms: u32) Error!u32 {
    if (delay_ms > delay_ms_max) {
        return Error.DelayInvalid;
    }

    assert(delay_ms <= delay_ms_max);

    if (text.len == 0) {
        return 0;
    }

    if (text.len > text_max) {
        return Error.TextTooLong;
    }

    const view = std.unicode.Utf8View.init(text) catch return Error.TextInvalid;
    const paced = delay_ms > 0 and !loop.is_loop_thread();

    if (!key.release_modifiers()) {
        return Error.SendFailed;
    }

    var sent: u32 = 0;
    var previous: u21 = 0;
    var iterator = view.iterator();

    while (iterator.nextCodepoint()) |codepoint| {
        assert(sent <= text_max);

        const stroke = stroke_of(previous, codepoint);

        previous = codepoint;

        const ok = switch (stroke) {
            .skip => continue,
            .press => |value| key.press(value),
            .character => |character| key.unicode(character),
        };

        if (!ok) {
            return Error.SendFailed;
        }

        sent += 1;

        assert(sent <= text_max);

        if (paced) {
            win32.Sleep(delay_ms);
        }
    }

    return sent;
}

pub fn send(text: []const u8) Error!u32 {
    return send_codepoints(text, 0);
}

pub fn send_with_delay(text: []const u8, delay_ms: u32) Error!u32 {
    if (delay_ms > delay_ms_max) {
        return Error.DelayInvalid;
    }

    assert(delay_ms <= delay_ms_max);

    return send_codepoints(text, delay_ms);
}

const testing = std.testing;

test "sending empty text sends nothing" {
    const sent = try send("");

    try testing.expectEqual(@as(u32, 0), sent);
}

test "sending oversized text is rejected" {
    var buffer: [text_max + 1]u8 = undefined;

    @memset(&buffer, 'a');

    try testing.expectError(Error.TextTooLong, send(&buffer));
}

test "sending text that is not valid utf8 is rejected" {
    const bad = [_]u8{ 0xC0, 0x20 };

    try testing.expectError(Error.TextInvalid, send(&bad));
}

test "sending with an oversized delay is rejected" {
    const delay_ms = delay_ms_max + 1;

    try testing.expectError(Error.DelayInvalid, send_with_delay("a", delay_ms));
}

test "text limits" {
    try testing.expect(text_max >= 1);
    try testing.expect(delay_ms_max >= 1);
}

test "each line ending types one enter" {
    try testing.expectEqual(Stroke{ .press = .enter }, stroke_of('a', '\n'));
    try testing.expectEqual(Stroke{ .press = .enter }, stroke_of('a', '\r'));
    try testing.expectEqual(Stroke.skip, stroke_of('\r', '\n'));
    try testing.expectEqual(Stroke{ .press = .enter }, stroke_of('\n', '\n'));
}

test "a tab types the tab key and other control characters type nothing" {
    try testing.expectEqual(Stroke{ .press = .tab }, stroke_of(0, '\t'));
    try testing.expectEqual(Stroke.skip, stroke_of(0, 0x08));
    try testing.expectEqual(Stroke.skip, stroke_of(0, 0x1B));
    try testing.expectEqual(Stroke.skip, stroke_of(0, 0x7F));
}

test "a printable codepoint types as itself" {
    try testing.expectEqual(Stroke{ .character = 'A' }, stroke_of(0, 'A'));
    try testing.expectEqual(Stroke{ .character = ' ' }, stroke_of(0, ' '));
    try testing.expectEqual(Stroke{ .character = 0x00E9 }, stroke_of(0, 0x00E9));
    try testing.expectEqual(Stroke{ .character = 0x1F600 }, stroke_of(0, 0x1F600));
}

test {
    testing.refAllDecls(@This());
}
