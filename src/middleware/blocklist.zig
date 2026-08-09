const Keycode = @import("../keycode.zig").Keycode;
const std = @import("std");

const Mutex = @import("../sync.zig").Mutex;

const key_event = @import("../event/key.zig");
const modifier = @import("../modifier.zig");
const response = @import("../response.zig");
const base = @import("base.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Response = response.Response;
const Next = base.Next;

pub const BlockedBinding = struct {
    key: Keycode,
    modifiers: modifier.Set,
};

pub fn BlockListMiddlewareType(comptime capacity: u32) type {
    return struct {
        const Instance = @This();

        blocked: [capacity]?BlockedBinding = [_]?BlockedBinding{null} ** capacity,
        count: u32 = 0,
        enabled: bool = true,
        mutex: Mutex = .{},

        pub fn init() Instance {
            const result = Instance{};

            assert(result.count == 0);
            assert(result.enabled);

            return result;
        }

        pub fn add(instance: *Instance, binding: BlockedBinding) !u32 {
            assert(binding.modifiers.flags <= modifier.flag_all);

            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            if (instance.count >= capacity) {
                return error.BlockListFull;
            }

            const slot = instance.find_empty_slot() orelse return error.BlockListFull;

            assert(slot < capacity);

            instance.blocked[slot] = binding;
            instance.count += 1;

            assert(instance.count <= capacity);
            assert(instance.blocked[slot] != null);

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

            if (instance.blocked[slot] == null) {
                return error.NotFound;
            }

            instance.blocked[slot] = null;
            instance.count -= 1;

            assert(instance.count <= capacity);
        }

        pub fn process(instance: *Instance, key: *const Key, next: *const Next) Response {
            assert(key.is_valid());

            if (instance.is_blocked(key)) {
                return .consume;
            }

            const result = next.invoke(key);

            assert(result.is_valid());

            return result;
        }

        fn is_blocked(instance: *Instance, key: *const Key) bool {
            assert(key.is_valid());

            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            if (!instance.enabled) {
                return false;
            }

            if (!key.down) {
                return false;
            }

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                if (instance.blocked[i]) |binding| {
                    if (key.value == binding.key and key.modifiers.eql(&binding.modifiers)) {
                        return true;
                    }
                }
            }

            assert(i == capacity);

            return false;
        }

        fn find_empty_slot(instance: *const Instance) ?u32 {
            assert(instance.count <= capacity);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                if (instance.blocked[i] == null) {
                    return i;
                }
            }

            assert(i == capacity);

            return null;
        }

        pub fn set_enabled(instance: *Instance, value: bool) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            instance.enabled = value;

            assert(instance.enabled == value);
        }

        pub fn is_enabled(instance: *Instance) bool {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            return instance.enabled;
        }

        pub fn clear(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                instance.blocked[i] = null;
            }

            instance.count = 0;

            assert(instance.count == 0);
            assert(i == capacity);
        }
    };
}

const testing = std.testing;

fn make_key(value: Keycode, down: bool) Key {
    return Key{
        .value = value,
        .down = down,
        .injected = false,
        .modifiers = .{},
    };
}

fn pass_call(_: *anyopaque, key: *const Key) Response {
    assert(key.is_valid());

    return .pass;
}

var next_context: u8 = 0;

fn make_next() Next {
    return Next{
        .context = &next_context,
        .call = pass_call,
    };
}

test "a blocked key is consumed" {
    var blocklist = BlockListMiddlewareType(4).init();

    _ = try blocklist.add(.{ .key = .a, .modifiers = .{} });

    const next = make_next();
    const key = make_key(.a, true);

    try testing.expectEqual(Response.consume, blocklist.process(&key, &next));
}

test "an unblocked key passes through" {
    var blocklist = BlockListMiddlewareType(4).init();

    _ = try blocklist.add(.{ .key = .a, .modifiers = .{} });

    const next = make_next();
    const key = make_key(.b, true);

    try testing.expectEqual(Response.pass, blocklist.process(&key, &next));
}

test "a key release passes through" {
    var blocklist = BlockListMiddlewareType(4).init();

    _ = try blocklist.add(.{ .key = .a, .modifiers = .{} });

    const next = make_next();
    const key = make_key(.a, false);

    try testing.expectEqual(Response.pass, blocklist.process(&key, &next));
}

test "a disabled blocklist passes everything through" {
    var blocklist = BlockListMiddlewareType(4).init();

    _ = try blocklist.add(.{ .key = .a, .modifiers = .{} });

    blocklist.set_enabled(false);

    const next = make_next();
    const key = make_key(.a, true);

    try testing.expectEqual(Response.pass, blocklist.process(&key, &next));
    try testing.expect(!blocklist.is_enabled());
}

test "removing an entry unblocks its key" {
    var blocklist = BlockListMiddlewareType(4).init();

    const slot = try blocklist.add(.{ .key = .a, .modifiers = .{} });

    try blocklist.remove(slot);

    const next = make_next();
    const key = make_key(.a, true);

    try testing.expectEqual(Response.pass, blocklist.process(&key, &next));
    try testing.expectError(error.NotFound, blocklist.remove(slot));
}
