const std = @import("std");

const platform = @import("platform.zig");

const assert = std.debug.assert;

const backend = platform.backend.clipboard;

pub const text_bytes_max: u32 = backend.text_bytes_max;

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

comptime {
    assert(text_bytes_max > 0);
}

pub fn paste() bool {
    return backend.paste();
}

pub fn replace(
    select_count: u32,
    text: []const u8,
) (CapacityError || PlatformError || RequestError)!void {
    assert(select_count >= 1);
    assert(text.len >= 1);

    if (text.len > text_bytes_max) {
        return error.TextTooLong;
    }

    return backend.replace(select_count, text);
}

pub fn set(text: []const u8) (CapacityError || PlatformError || RequestError)!void {
    assert(text.len >= 1);

    if (text.len > text_bytes_max) {
        return error.TextTooLong;
    }

    return backend.set(text);
}

const testing = std.testing;

const record = platform.mock.record;

test paste {
    platform.mock.reset();

    try testing.expect(paste());

    const entry = record.last() orelse return error.EntryMissing;

    try testing.expectEqual(record.Kind.key_combination, entry.kind);
    try testing.expect(entry.modifiers.ctrl());
}

test replace {
    platform.mock.reset();

    try replace(6, "hello");

    try testing.expectEqual(@as(u16, 1), record.count_of(.clipboard_set));
    try testing.expectEqual(@as(u16, 6), record.count_of(.key_press));
}

test set {
    platform.mock.reset();

    try set("signature");

    const entry = record.last() orelse return error.EntryMissing;

    try testing.expectEqualStrings("signature", entry.body());

    const long: [text_bytes_max + 1]u8 = @splat('a');
    const refused = set(&long);

    try testing.expectError(error.TextTooLong, refused);
}
