const std = @import("std");

const platform = @import("platform.zig");

const assert = std.debug.assert;

pub const CapacityError = error{TextTooLong};

pub const PlatformError = error{
    ClipboardUnavailable,
    SendFailed,
    TransferFailed,
};

pub const RequestError = error{
    CountInvalid,
    TextInvalid,
};

pub fn paste(comptime Platform: type, backend: *Platform) bool {
    comptime assert(Platform.capabilities.clipboard);

    return backend.clipboard_paste();
}

pub fn replace(
    comptime Platform: type,
    backend: *Platform,
    select_count: u32,
    text: []const u8,
) (CapacityError || PlatformError || RequestError)!void {
    comptime assert(Platform.clipboard_text_bytes_max > 0);

    assert(select_count >= 1);
    assert(text.len >= 1);

    if (text.len > Platform.clipboard_text_bytes_max) {
        return error.TextTooLong;
    }

    return backend.clipboard_replace(select_count, text);
}

pub fn set(
    comptime Platform: type,
    backend: *Platform,
    text: []const u8,
) (CapacityError || PlatformError || RequestError)!void {
    comptime assert(Platform.clipboard_text_bytes_max > 0);

    assert(text.len >= 1);

    if (text.len > Platform.clipboard_text_bytes_max) {
        return error.TextTooLong;
    }

    return backend.clipboard_set(text);
}

const testing = std.testing;

const Fake = platform.Fake;

test paste {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    try testing.expect(paste(Fake, fake));

    const entry = fake.record.last() orelse return error.EntryMissing;

    try testing.expect(entry.kind == .key_combination);
    try testing.expect(entry.modifiers.ctrl());
}

test replace {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    try replace(Fake, fake, 6, "hello");

    try testing.expectEqual(@as(u16, 1), fake.record.count_of(.clipboard_set));
    try testing.expectEqual(@as(u16, 6), fake.record.count_of(.key_press));
}

test set {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    try set(Fake, fake, "signature");

    const entry = fake.record.last() orelse return error.EntryMissing;

    try testing.expectEqualStrings("signature", entry.body());

    const long: [Fake.clipboard_text_bytes_max + 1]u8 = @splat('a');
    const refused = set(Fake, fake, &long);

    try testing.expectError(error.TextTooLong, refused);
}
