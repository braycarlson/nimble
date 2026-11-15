const std = @import("std");

const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const platform = @import("../platform.zig");

const assert = std.debug.assert;

const Keycode = keycode.Keycode;
const Modifier = modifier.Set;

pub fn combination(
    comptime Platform: type,
    backend: *Platform,
    modifiers: Modifier,
    value: Keycode,
) bool {
    assert(modifiers.flags <= modifier.flag_all);

    return backend.key_combination(&modifiers, value);
}

pub fn down(comptime Platform: type, backend: *Platform, value: Keycode) bool {
    return backend.key_down(value);
}

pub fn press(comptime Platform: type, backend: *Platform, value: Keycode) bool {
    return backend.key_press(value);
}

pub fn up(comptime Platform: type, backend: *Platform, value: Keycode) bool {
    return backend.key_up(value);
}

const testing = std.testing;

const Fake = platform.Fake;

test combination {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    try testing.expect(combination(Fake, fake, Modifier.from(.{ .ctrl = true }), .c));

    const entry = fake.record.last() orelse return error.EntryMissing;

    try testing.expect(entry.kind == .key_combination);
    try testing.expectEqual(Keycode.c, entry.code);
    try testing.expect(entry.modifiers.ctrl());
}

test down {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    try testing.expect(down(Fake, fake, .shift_left));
    try testing.expect(fake.record.contains(.key_down, .shift_left));
}

test press {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    try testing.expect(press(Fake, fake, .enter));
    try testing.expect(fake.record.contains(.key_press, .enter));
}

test up {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    try testing.expect(up(Fake, fake, .shift_left));
    try testing.expect(fake.record.contains(.key_up, .shift_left));
}
