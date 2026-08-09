const std = @import("std");

const fuzz = @import("../testing/fuzz.zig");
const keycode = @import("../keycode.zig");
const windows = @import("windows/keycode.zig");
const linux = @import("linux/keycode.zig");

const Allocator = std.mem.Allocator;
const Keycode = keycode.Keycode;
const assert = std.debug.assert;

const Operation = enum {
    windows_forward,
    windows_reverse,
    linux_forward,
    linux_reverse,
    unmapped_windows,
    unmapped_linux,
};

const code_count: u16 = @typeInfo(Keycode).@"enum".fields.len;

comptime {
    assert(code_count > 0);
    assert(code_count <= 256);
}

pub fn main(gpa: Allocator, args: fuzz.FuzzArgs) !void {
    _ = gpa;

    assert(args.events_max >= 1);

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();
    const weights = fuzz.random_enum_weights(random, Operation);

    check_exhaustive();

    var event: u32 = 0;

    while (event < args.events_max) : (event += 1) {
        const operation = fuzz.random_enum_weighted(random, Operation, weights);

        switch (operation) {
            .windows_forward => check_windows_forward(random_code(random)),
            .windows_reverse => check_windows_reverse(random.int(u8)),
            .linux_forward => check_linux_forward(random_code(random)),
            .linux_reverse => check_linux_reverse(random.int(u8)),
            .unmapped_windows => check_unmapped_windows(random.int(u8)),
            .unmapped_linux => check_unmapped_linux(random.int(u8)),
        }
    }

    assert(event == args.events_max);
}

fn random_code(random: std.Random) Keycode {
    const index = random.uintLessThan(u16, code_count);

    assert(index < code_count);

    const fields = @typeInfo(Keycode).@"enum".fields;

    inline for (fields, 0..) |field, position| {
        if (position == index) {
            return @enumFromInt(field.value);
        }
    }

    unreachable;
}

fn check_windows_forward(code: Keycode) void {
    const virtual_key = windows.to_native(code) orelse return;

    assert(virtual_key >= windows.value_min);
    assert(virtual_key <= windows.value_max);
    assert(windows.from_native(virtual_key) == code);
}

fn check_windows_reverse(virtual_key: u8) void {
    const mapped = windows.from_native(virtual_key) orelse return;

    assert(windows.to_native(mapped) == virtual_key);
}

fn check_linux_forward(code: Keycode) void {
    const key_code = linux.to_native(code) orelse return;

    assert(key_code >= linux.value_min);
    assert(key_code <= linux.value_max);

    const back = linux.from_native(key_code) orelse unreachable;

    assert(linux.to_native(back) == key_code);
}

fn check_linux_reverse(key_code: u8) void {
    const mapped = linux.from_native(key_code) orelse return;
    const back = linux.to_native(mapped) orelse unreachable;

    assert(back == key_code);
}

fn check_unmapped_windows(virtual_key: u8) void {
    if (windows.from_native(virtual_key) != null) {
        return;
    }

    assert(windows.from_native(virtual_key) == null);
}

fn check_unmapped_linux(key_code: u8) void {
    if (linux.from_native(key_code) != null) {
        return;
    }

    assert(linux.from_native(key_code) == null);
}

fn check_exhaustive() void {
    var virtual_key: u16 = 0;

    while (virtual_key <= 0xFF) : (virtual_key += 1) {
        check_windows_reverse(@intCast(virtual_key));
        check_linux_reverse(@intCast(virtual_key));
    }

    assert(virtual_key == 0x100);

    inline for (@typeInfo(Keycode).@"enum".fields) |field| {
        const code: Keycode = @enumFromInt(field.value);

        check_windows_forward(code);
        check_linux_forward(code);
    }
}

const testing = std.testing;

test "fuzz: keycode tables round trip on both platforms" {
    try main(testing.allocator, .{ .seed = 456, .events_max = 4096 });
}

test "keycode tables round trip exhaustively" {
    check_exhaustive();
}

test "generic modifiers are the only non-injective Linux reverse entries" {
    const generic = [_]Keycode{ .shift, .control, .alt };
    const sided = [_]Keycode{ .shift_left, .control_left, .alt_left };

    for (generic, sided) |g, s| {
        const key_code = linux.to_native(g) orelse return error.MissingMapping;

        try testing.expectEqual(linux.to_native(s), linux.to_native(g));
        try testing.expectEqual(s, linux.from_native(key_code).?);
    }
}
