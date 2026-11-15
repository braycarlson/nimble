const std = @import("std");

const platform = @import("../platform.zig");

const assert = std.debug.assert;

pub const CapacityError = error{TextTooLong};
pub const PlatformError = error{SendFailed};

pub const RequestError = error{
    DelayInvalid,
    TextInvalid,
};

pub const delay_ms_max: u32 = 1000;

comptime {
    assert(delay_ms_max > 0);
}

pub fn send(
    comptime Platform: type,
    backend: *Platform,
    text: []const u8,
) (CapacityError || PlatformError || RequestError)!u32 {
    comptime assert(Platform.text_bytes_max > 0);

    if (text.len > Platform.text_bytes_max) {
        return error.TextTooLong;
    }

    const sent = try backend.text_send(text);

    assert(sent <= text.len);

    return sent;
}

pub fn send_with_delay(
    comptime Platform: type,
    backend: *Platform,
    text: []const u8,
    delay_ms: u32,
) (CapacityError || PlatformError || RequestError)!u32 {
    comptime assert(Platform.text_bytes_max > 0);

    if (text.len > Platform.text_bytes_max) {
        return error.TextTooLong;
    }

    if (delay_ms > delay_ms_max) {
        return error.DelayInvalid;
    }

    const sent = try backend.text_send_with_delay(text, delay_ms);

    assert(sent <= text.len);

    return sent;
}

const testing = std.testing;

const Fake = platform.Fake;

test send {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    const sent = try send(Fake, fake, "hello");

    try testing.expectEqual(@as(u32, 5), sent);

    const entry = fake.record.last() orelse return error.EntryMissing;

    try testing.expectEqualStrings("hello", entry.body());

    const long: [Fake.text_bytes_max + 1]u8 = @splat('a');

    try testing.expectError(error.TextTooLong, send(Fake, fake, &long));
}

test send_with_delay {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    const sent = try send_with_delay(Fake, fake, "slow", 50);
    const refused = send_with_delay(Fake, fake, "slow", delay_ms_max + 1);

    try testing.expectEqual(@as(u32, 4), sent);
    try testing.expectError(error.DelayInvalid, refused);
}
