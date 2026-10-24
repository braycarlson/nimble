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

pub const CapacityError = error{BlocksExhausted};
pub const RequestError = error{HandleUnknown};

pub fn BlockListMiddlewareType(comptime capacity: u32) type {
    comptime assert(capacity > 0);

    return struct {
        const Instance = @This();

        blocked: [capacity]?Binding = @splat(null),
        count: u32 = 0,
        enabled: bool = true,
        mutex: Mutex = .{},

        pub const Binding = struct {
            key: Keycode,
            modifiers: modifier.Set,
        };

        pub const Entry = enum(u32) { _ };

        pub fn init() Instance {
            const result = Instance{};

            assert(result.count == 0);
            assert(result.enabled);

            return result;
        }

        pub fn add(instance: *Instance, binding: Binding) CapacityError!Entry {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            const slot = instance.find_empty_slot() orelse return error.BlocksExhausted;

            assert(slot < capacity);

            instance.blocked[slot] = binding;
            instance.count += 1;

            assert(instance.count <= capacity);
            assert(instance.blocked[slot] != null);

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

            if (instance.blocked[slot] == null) {
                return error.HandleUnknown;
            }

            instance.blocked[slot] = null;
            instance.count -= 1;

            assert(instance.count < capacity);
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

            for (instance.blocked) |maybe| {
                const binding = maybe orelse continue;
                if (key.value != binding.key) continue;

                if (key.modifiers.eql(&binding.modifiers)) {
                    return true;
                }
            }

            return false;
        }

        fn find_empty_slot(instance: *const Instance) ?u32 {
            assert(instance.count <= capacity);

            for (instance.blocked, 0..) |maybe, slot| {
                if (maybe == null) {
                    return @intCast(slot);
                }
            }

            return null;
        }

        pub fn enable(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            instance.enabled = true;
        }

        pub fn disable(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            instance.enabled = false;
        }

        pub fn is_enabled(instance: *Instance) bool {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            return instance.enabled;
        }

        pub fn clear(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            instance.blocked = @splat(null);
            instance.count = 0;

            assert(instance.count == 0);
        }
    };
}

const testing = std.testing;

const BlockList = BlockListMiddlewareType(4);

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

fn make_next(context: *u8) Next {
    return Next{
        .context = context,
        .call = pass_call,
    };
}

test BlockListMiddlewareType {
    var blocklist = BlockList.init();

    const entry = try blocklist.add(.{ .key = .x, .modifiers = .{} });

    var context: u8 = 0;
    const next = make_next(&context);
    const pressed = make_key(.x, true);

    try testing.expectEqual(Response.consume, blocklist.process(&pressed, &next));

    try blocklist.remove(entry);

    try testing.expectEqual(Response.pass, blocklist.process(&pressed, &next));
}

test "an unblocked key passes through" {
    var blocklist = BlockList.init();

    _ = try blocklist.add(.{ .key = .a, .modifiers = .{} });

    var context: u8 = 0;
    const next = make_next(&context);
    const key = make_key(.b, true);

    try testing.expectEqual(Response.pass, blocklist.process(&key, &next));
}

test "a key release passes through" {
    var blocklist = BlockList.init();

    _ = try blocklist.add(.{ .key = .a, .modifiers = .{} });

    var context: u8 = 0;
    const next = make_next(&context);
    const key = make_key(.a, false);

    try testing.expectEqual(Response.pass, blocklist.process(&key, &next));
}

test "a disabled blocklist passes everything through" {
    var blocklist = BlockList.init();

    _ = try blocklist.add(.{ .key = .a, .modifiers = .{} });

    blocklist.disable();

    var context: u8 = 0;
    const next = make_next(&context);
    const key = make_key(.a, true);

    try testing.expectEqual(Response.pass, blocklist.process(&key, &next));
    try testing.expect(!blocklist.is_enabled());

    blocklist.enable();

    try testing.expectEqual(Response.consume, blocklist.process(&key, &next));
}

test "removing an entry twice is a request error" {
    var blocklist = BlockList.init();

    const entry = try blocklist.add(.{ .key = .a, .modifiers = .{} });

    try blocklist.remove(entry);

    const repeated = blocklist.remove(entry);

    try testing.expectError(error.HandleUnknown, repeated);
}

test "a full blocklist is a capacity error" {
    var blocklist = BlockListMiddlewareType(1).init();

    _ = try blocklist.add(.{ .key = .a, .modifiers = .{} });

    const result = blocklist.add(.{ .key = .b, .modifiers = .{} });

    try testing.expectError(error.BlocksExhausted, result);
}
