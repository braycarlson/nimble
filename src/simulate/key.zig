const std = @import("std");

const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const platform = @import("../platform.zig");

const backend = platform.backend.simulate.key;

const Keycode = keycode.Keycode;
const Modifier = modifier.Set;

pub fn combination(modifiers: Modifier, value: Keycode) bool {
    return backend.combination(&modifiers, value);
}

pub fn down(value: Keycode) bool {
    return backend.key_down(value);
}

pub fn press(value: Keycode) bool {
    return backend.press(value);
}

pub fn up(value: Keycode) bool {
    return backend.key_up(value);
}

const testing = std.testing;

const record = platform.mock.record;

test combination {
    platform.mock.reset();

    try testing.expect(combination(Modifier.from(.{ .ctrl = true }), .c));

    const entry = record.last() orelse return error.EntryMissing;

    try testing.expectEqual(record.Kind.key_combination, entry.kind);
    try testing.expectEqual(Keycode.c, entry.code);
    try testing.expect(entry.modifiers.ctrl());
}

test down {
    platform.mock.reset();

    try testing.expect(down(.shift_left));
    try testing.expect(record.contains(.key_down, .shift_left));
}

test press {
    platform.mock.reset();

    try testing.expect(press(.enter));
    try testing.expect(record.contains(.key_press, .enter));
}

test up {
    platform.mock.reset();

    try testing.expect(up(.shift_left));
    try testing.expect(record.contains(.key_up, .shift_left));
}
