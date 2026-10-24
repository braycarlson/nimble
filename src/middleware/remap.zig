const std = @import("std");

const base = @import("base.zig");
const key_event = @import("../event/key.zig");
const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const response = @import("../response.zig");
const sync = @import("../sync.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Keycode = keycode.Keycode;
const Mutex = sync.Mutex;
const Next = base.Next;
const Response = response.Response;

pub const CapacityError = error{MappingsExhausted};
pub const RequestError = error{HandleUnknown};

pub fn RemapMiddlewareType(comptime capacity: u32) type {
    comptime assert(capacity > 0);

    return struct {
        const Instance = @This();

        mappings: [capacity]?Mapping = @splat(null),
        count: u32 = 0,
        mutex: Mutex = .{},

        pub const Mapping = struct {
            from_key: Keycode,
            from_modifiers: modifier.Set,
            to_key: Keycode,
            to_modifiers: modifier.Set,
        };

        pub const Entry = enum(u32) { _ };

        pub fn init() Instance {
            const result = Instance{};

            assert(result.count == 0);

            return result;
        }

        pub fn add(instance: *Instance, mapping: Mapping) CapacityError!Entry {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            const slot = instance.find_empty_slot() orelse return error.MappingsExhausted;

            assert(slot < capacity);

            instance.mappings[slot] = mapping;
            instance.count += 1;

            assert(instance.count <= capacity);
            assert(instance.mappings[slot] != null);

            return @fromBackingInt(slot);
        }

        pub fn remove(instance: *Instance, entry: Entry) RequestError!void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            const slot = @backingInt(entry);

            if (slot >= capacity) {
                return error.HandleUnknown;
            }

            if (instance.mappings[slot] == null) {
                return error.HandleUnknown;
            }

            instance.mappings[slot] = null;
            instance.count -= 1;

            assert(instance.count < capacity);
        }

        pub fn process(instance: *Instance, key: *const Key, next: *const Next) Response {
            assert(key.is_valid());

            const mapping = instance.find_mapping(key) orelse return next.invoke(key);

            var remapped = key.*;

            remapped.value = mapping.to_key;
            remapped.modifiers = mapping.to_modifiers;

            assert(remapped.is_valid());

            return next.invoke(&remapped);
        }

        pub fn clear(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            instance.mappings = @splat(null);
            instance.count = 0;

            assert(instance.count == 0);
        }

        fn find_mapping(instance: *Instance, key: *const Key) ?Mapping {
            assert(key.is_valid());

            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            for (instance.mappings) |maybe| {
                const mapping = maybe orelse continue;
                if (key.value != mapping.from_key) continue;
                if (key.modifiers.eql(&mapping.from_modifiers)) return mapping;
            }

            return null;
        }

        fn find_empty_slot(instance: *const Instance) ?u32 {
            assert(instance.count <= capacity);

            for (instance.mappings, 0..) |maybe, slot| {
                if (maybe == null) {
                    return @intCast(slot);
                }
            }

            return null;
        }
    };
}

const testing = std.testing;

const Remap = RemapMiddlewareType(4);

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

test RemapMiddlewareType {
    var remap = Remap.init();

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
    var remap = Remap.init();

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

test "removing a mapping leaves the other entries stable" {
    var remap = Remap.init();

    const first = try remap.add(.{
        .from_key = .a,
        .from_modifiers = .{},
        .to_key = .b,
        .to_modifiers = .{},
    });

    const second = try remap.add(.{
        .from_key = .c,
        .from_modifiers = .{},
        .to_key = .d,
        .to_modifiers = .{},
    });

    try remap.remove(first);

    var capture = Capture{};

    const next = Next{
        .context = &capture,
        .call = Capture.call,
    };

    const key = make_key(.c, .{});

    _ = remap.process(&key, &next);

    try testing.expectEqual(.d, capture.value);

    try remap.remove(second);

    try testing.expectEqual(@as(u32, 0), remap.count);

    const repeated = remap.remove(second);

    try testing.expectError(error.HandleUnknown, repeated);
}

test "a full remap is a capacity error" {
    var remap = RemapMiddlewareType(1).init();

    const mapping = Remap.Mapping{
        .from_key = .a,
        .from_modifiers = .{},
        .to_key = .b,
        .to_modifiers = .{},
    };

    _ = try remap.add(mapping);

    try testing.expectError(error.MappingsExhausted, remap.add(mapping));
}
