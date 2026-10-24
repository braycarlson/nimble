const std = @import("std");

const platform = @import("../platform.zig");

const assert = std.debug.assert;

const backend = platform.backend.simulate.text;

pub const text_bytes_max: u32 = backend.text_max;
pub const delay_ms_max: u32 = 1000;
pub const CapacityError = error{TextTooLong};
pub const PlatformError = error{SendFailed};

pub const RequestError = error{
    DelayInvalid,
    TextInvalid,
};

comptime {
    assert(text_bytes_max > 0);
    assert(delay_ms_max > 0);
}

pub fn send(text: []const u8) (CapacityError || PlatformError || RequestError)!u32 {
    if (text.len > text_bytes_max) {
        return error.TextTooLong;
    }

    const sent = try backend.send(text);

    assert(sent <= text.len);

    return sent;
}

pub fn send_with_delay(
    text: []const u8,
    delay_ms: u32,
) (CapacityError || PlatformError || RequestError)!u32 {
    if (text.len > text_bytes_max) {
        return error.TextTooLong;
    }

    if (delay_ms > delay_ms_max) {
        return error.DelayInvalid;
    }

    const sent = try backend.send_with_delay(text, delay_ms);

    assert(sent <= text.len);

    return sent;
}

const testing = std.testing;

const record = platform.mock.record;

test send {
    platform.mock.reset();

    const sent = try send("hello");

    try testing.expectEqual(@as(u32, 5), sent);

    const entry = record.last() orelse return error.EntryMissing;

    try testing.expectEqualStrings("hello", entry.body());

    const long: [text_bytes_max + 1]u8 = @splat('a');

    try testing.expectError(error.TextTooLong, send(&long));
}

test send_with_delay {
    platform.mock.reset();

    const sent = try send_with_delay("slow", 50);

    try testing.expectEqual(@as(u32, 4), sent);
    try testing.expectError(error.DelayInvalid, send_with_delay("slow", delay_ms_max + 1));
}
