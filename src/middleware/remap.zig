const std = @import("std");

const base = @import("base.zig");
const key_event = @import("../event/key.zig");
const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const response = @import("../response.zig");

const Mutex = @import("../sync.zig").Mutex;
const assert = std.debug.assert;
const Keycode = keycode.Keycode;
const Key = key_event.Key;
const Response = response.Response;
const Next = base.Next;

pub const Mapping = struct {
    from_key: Keycode,
    from_modifiers: modifier.Set,
    to_key: Keycode,
    to_modifiers: modifier.Set,
};

pub fn RemapMiddlewareType(comptime capacity: u32) type {
    return struct {
        const Instance = @This();

        mappings: [capacity]?Mapping = [_]?Mapping{null} ** capacity,
        count: u32 = 0,
        mutex: Mutex = .{},

        pub fn init() Instance {
            const result = Instance{};

            assert(result.count == 0);
            assert(capacity > 0);

            return result;
        }

        pub fn add(instance: *Instance, mapping: Mapping) !u32 {
            assert(mapping.from_modifiers.flags <= modifier.flag_all);
            assert(mapping.to_modifiers.flags <= modifier.flag_all);

            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            if (instance.count >= capacity) {
                return error.RemapFull;
            }

            const slot = instance.find_empty_slot() orelse return error.RemapFull;

            assert(slot < capacity);

            instance.mappings[slot] = mapping;
            instance.count += 1;

            assert(instance.count <= capacity);
            assert(instance.mappings[slot] != null);

            return slot;
        }

        pub fn remove(instance: *Instance, slot: u32) !void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            if (slot >= capacity) {
                return error.InvalidSlot;
            }

            assert(slot < capacity);

            if (instance.mappings[slot] == null) {
                return error.NotFound;
            }

            instance.mappings[slot] = null;
            instance.count -= 1;

            assert(instance.count <= capacity);
        }

        pub fn process(instance: *Instance, key: *const Key, next: *const Next) Response {
            assert(key.is_valid());

            const found = instance.find_mapping(key);

            if (found) |mapping| {
                var remapped = key.*;

                remapped.value = mapping.to_key;
                remapped.modifiers = mapping.to_modifiers;

                assert(remapped.is_valid());

                return next.invoke(&remapped);
            }

            return next.invoke(key);
        }

        fn find_mapping(instance: *Instance, key: *const Key) ?Mapping {
            assert(key.is_valid());

            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                if (instance.mappings[i]) |mapping| {
                    if (instance.matches(key, &mapping)) {
                        return mapping;
                    }
                }
            }

            assert(i == capacity);

            return null;
        }

        fn matches(_: *Instance, key: *const Key, mapping: *const Mapping) bool {
            assert(key.is_valid());
            assert(mapping.from_modifiers.flags <= modifier.flag_all);

            if (key.value != mapping.from_key) {
                return false;
            }

            return key.modifiers.eql(&mapping.from_modifiers);
        }

        fn find_empty_slot(instance: *const Instance) ?u32 {
            assert(instance.count <= capacity);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                if (instance.mappings[i] == null) {
                    return i;
                }
            }

            assert(i == capacity);

            return null;
        }

        pub fn clear(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                instance.mappings[i] = null;
            }

            instance.count = 0;

            assert(instance.count == 0);
            assert(i == capacity);
        }
    };
}

const testing = std.testing;

fn make_key(value: Keycode, mods: modifier.Set) Key {
    return Key{
        .value = value,
        .down = true,
        .injected = false,
        .modifiers = mods,
    };
}

const Capture = struct {
    value: Keycode = .silent,
    flags: u4 = 0,

    fn call(context: *anyopaque, key: *const Key) Response {
        const typed: *Capture = @ptrCast(@alignCast(context));

        typed.value = key.value;
        typed.flags = key.modifiers.to_bits();

        return .pass;
    }
};

test "a remap accepts a valid mapping" {
    var remap = RemapMiddlewareType(4).init();

    const slot = try remap.add(.{
        .from_key = .a,
        .from_modifiers = .{},
        .to_key = .b,
        .to_modifiers = .{},
    });

    try testing.expectEqual(@as(u32, 0), slot);
    try testing.expectEqual(@as(u32, 1), remap.count);
}

test "a matching key is remapped" {
    var remap = RemapMiddlewareType(4).init();

    _ = try remap.add(.{
        .from_key = .a,
        .from_modifiers = .{},
        .to_key = .b,
        .to_modifiers = modifier.Set.from(.{ .ctrl = true }),
    });

    var capture = Capture{};

    const next = Next{
        .context = &capture,
        .call = Capture.call,
    };

    const key = make_key(.a, .{});
    const result = remap.process(&key, &next);

    try testing.expectEqual(Response.pass, result);
    try testing.expectEqual(.b, capture.value);
    try testing.expectEqual(modifier.flag_ctrl, capture.flags);
}

test "an unmatched key passes through" {
    var remap = RemapMiddlewareType(4).init();

    _ = try remap.add(.{
        .from_key = .a,
        .from_modifiers = .{},
        .to_key = .b,
        .to_modifiers = .{},
    });

    var capture = Capture{};

    const next = Next{
        .context = &capture,
        .call = Capture.call,
    };

    const key = make_key(.c, .{});
    const result = remap.process(&key, &next);

    try testing.expectEqual(Response.pass, result);
    try testing.expectEqual(.c, capture.value);
}

test "removing a mapping leaves the other slots stable" {
    var remap = RemapMiddlewareType(4).init();

    const first_slot = try remap.add(.{
        .from_key = .a,
        .from_modifiers = .{},
        .to_key = .b,
        .to_modifiers = .{},
    });

    const second_slot = try remap.add(.{
        .from_key = .c,
        .from_modifiers = .{},
        .to_key = .d,
        .to_modifiers = .{},
    });

    try remap.remove(first_slot);
    try remap.remove(second_slot);

    try testing.expectEqual(@as(u32, 0), remap.count);
    try testing.expectError(error.NotFound, remap.remove(second_slot));
}
