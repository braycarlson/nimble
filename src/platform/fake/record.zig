const std = @import("std");

const keycode = @import("../../keycode.zig");
const modifier = @import("../../modifier.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;

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

pub const text_bytes_max: u16 = 256;

comptime {
    assert(text_bytes_max > 0);
}

pub fn RecordType(comptime capacity: u16) type {
    comptime assert(capacity > 0);

    return struct {
        entries: [capacity]Entry = undefined,
        count: u16 = 0,
        overflowed: bool = false,

        const Record = @This();

        pub fn push(record: *Record, entry: Entry) void {
            assert(record.count <= capacity);

            if (record.count == capacity) {
                record.overflowed = true;

                return;
            }

            record.entries[record.count] = entry;
            record.count += 1;

            assert(record.count <= capacity);
        }

        pub fn push_text(record: *Record, kind: Kind, text: []const u8) void {
            var entry = Entry{ .kind = kind };
            const length = @min(text.len, text_bytes_max);

            @memcpy(entry.text[0..length], text[0..length]);

            entry.text_len = @intCast(length);

            record.push(entry);
        }

        pub fn len(record: *const Record) u16 {
            assert(record.count <= capacity);

            return record.count;
        }

        pub fn at(record: *const Record, index: u16) Entry {
            assert(index < record.count);

            return record.entries[index];
        }

        pub fn last(record: *const Record) ?Entry {
            if (record.count == 0) {
                return null;
            }

            assert(record.count >= 1);

            return record.entries[record.count - 1];
        }

        pub fn is_overflowed(record: *const Record) bool {
            return record.overflowed;
        }

        pub fn count_of(record: *const Record, kind: Kind) u16 {
            assert(record.count <= capacity);

            var total: u16 = 0;

            for (record.entries[0..record.count]) |*entry| {
                if (entry.kind == kind) {
                    total += 1;
                }
            }

            assert(total <= record.count);

            return total;
        }

        pub fn contains(record: *const Record, kind: Kind, code: Keycode) bool {
            assert(record.count <= capacity);

            for (record.entries[0..record.count]) |*entry| {
                if (entry.kind == kind) {
                    if (entry.code == code) return true;
                }
            }

            return false;
        }
    };
}

const testing = std.testing;

test RecordType {
    const Small = RecordType(2);

    var record: Small = .{};

    try testing.expect(record.last() == null);

    record.push(.{ .kind = .key_press, .code = .a });
    record.push_text(.text_send, "nimble");
    record.push(.{ .kind = .key_dummy });

    try testing.expectEqual(@as(u16, 2), record.len());
    try testing.expect(record.is_overflowed());
    try testing.expect(record.contains(.key_press, .a));
    try testing.expectEqual(@as(u16, 1), record.count_of(.text_send));
    try testing.expectEqualStrings("nimble", record.last().?.body());
}
