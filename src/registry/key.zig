const std = @import("std");

const key_event = @import("../event/key.zig");
const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const response = @import("../response.zig");
const filter_mod = @import("../filter.zig");
const base = @import("base.zig");
const entry_mod = @import("entry.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Keycode = keycode.Keycode;
const Response = response.Response;
const WindowFilter = filter_mod.Active;

const lookup_size: u32 = 256 * 16;
pub const capacity_max: u32 = 1024;
pub const CapacityError = error{BindingsExhausted};

pub const RequestError = error{
    BindingDuplicate,
    HandleUnknown,
};

pub const Callback = *const fn (context: *anyopaque, key: *const Key) Response;

pub const Entry = struct {
    base: entry_mod.FilteredEntryType(Callback, WindowFilter) = .{},
    key: Keycode = .silent,
    modifiers: modifier.Set = .{},
    block_exempt: bool = false,

    pub fn get_id(entry: *const Entry) u32 {
        return entry.base.get_id();
    }

    pub fn get_callback(entry: *const Entry) ?Callback {
        return entry.base.get_callback();
    }

    pub fn get_context(entry: *const Entry) ?*anyopaque {
        return entry.base.get_context();
    }

    pub fn is_active(entry: *const Entry) bool {
        return entry.base.is_active();
    }

    pub fn matches_filter(entry: *const Entry) bool {
        return entry.base.matches_filter();
    }

    pub fn is_valid(entry: *const Entry) bool {
        if (!entry.is_active()) {
            return true;
        }

        return entry.base.is_valid();
    }
};

pub const Invocation = struct {
    id: u32,
    callback: Callback,
    context: *anyopaque,
};

pub const Options = struct {
    filter: WindowFilter = .{},
    block_exempt: bool = false,
};

pub fn KeyRegistryType(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("KeyRegistryType capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("KeyRegistryType capacity exceeds maximum");
    }

    return struct {
        const Instance = @This();
        const Base = base.BaseRegistryType(Entry, capacity, .{ .has_mutex = true });

        base: Base = Base.init(),
        lookup: [lookup_size]?u32 = @splat(null),

        pub fn init() Instance {
            return Instance{};
        }

        pub fn is_valid(instance: *const Instance) bool {
            return instance.base.is_valid();
        }

        pub fn clear(instance: *Instance) void {
            instance.base.lock();
            defer instance.base.unlock();

            instance.base.clear_locked();

            for (&instance.lookup) |*slot| {
                slot.* = null;
            }
        }

        pub fn resolve(instance: *Instance, key: *const Key) ?Invocation {
            assert(key.is_valid());

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            return instance.resolve_locked(key);
        }

        pub fn process(instance: *Instance, key: *const Key) ?Response {
            assert(key.is_valid());

            const invocation = instance.resolve(key) orelse return null;

            assert(invocation.id >= 1);

            return invocation.callback(invocation.context, key);
        }

        pub fn process_blocked(instance: *Instance, key: *const Key) ?Response {
            assert(key.is_valid());

            const invocation = blk: {
                instance.base.lock();
                defer instance.base.unlock();

                assert(instance.is_valid());

                break :blk instance.resolve_block_exempt_locked(key);
            };

            if (invocation) |inv| {
                return inv.callback(inv.context, key);
            }

            return null;
        }

        fn resolve_locked(instance: *Instance, key: *const Key) ?Invocation {
            assert(key.is_valid());

            const index = pack_lookup(key.value, key.modifiers);

            assert(index < lookup_size);

            const slot = instance.lookup[index] orelse return null;

            assert(slot < capacity);

            const entry = &instance.base.slot.entries[slot];

            if (!entry.is_active()) {
                return null;
            }

            if (!entry.matches_filter()) {
                return null;
            }

            const callback = entry.get_callback() orelse return null;
            const context = entry.get_context() orelse return null;

            return Invocation{
                .id = entry.get_id(),
                .callback = callback,
                .context = context,
            };
        }

        fn resolve_block_exempt_locked(instance: *Instance, key: *const Key) ?Invocation {
            assert(instance.is_valid());
            assert(key.is_valid());

            const index = pack_lookup(key.value, key.modifiers);

            assert(index < lookup_size);

            const slot = instance.lookup[index] orelse return null;

            assert(slot < capacity);

            const entry = &instance.base.slot.entries[slot];

            if (!entry.is_active()) {
                return null;
            }

            if (!entry.block_exempt) {
                return null;
            }

            if (!entry.matches_filter()) {
                return null;
            }

            const callback = entry.get_callback() orelse return null;
            const context = entry.get_context() orelse return null;

            return Invocation{
                .id = entry.get_id(),
                .callback = callback,
                .context = context,
            };
        }

        pub fn find(instance: *Instance, key: *const Key) ?*Entry {
            assert(key.is_valid());

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const index = pack_lookup(key.value, key.modifiers);

            assert(index < lookup_size);

            const slot = instance.lookup[index] orelse return null;

            assert(slot < capacity);

            return &instance.base.slot.entries[slot];
        }

        pub fn register(
            instance: *Instance,
            key: Keycode,
            modifiers: modifier.Set,
            callback: Callback,
            context: ?*anyopaque,
            options: Options,
        ) (CapacityError || RequestError)!u32 {
            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const index = pack_lookup(key, modifiers);

            assert(index < lookup_size);

            if (instance.lookup[index] != null) {
                return error.BindingDuplicate;
            }

            const allocation = instance.base.allocate_locked() orelse {
                return error.BindingsExhausted;
            };

            assert(allocation.slot < capacity);
            assert(allocation.id >= 1);

            instance.base.slot.entries[allocation.slot] = Entry{
                .base = .{
                    .base = .{
                        .id = allocation.id,
                        .callback = callback,
                        .context = @ptrCast(@alignCast(context)),
                        .active = true,
                    },
                    .filter = options.filter,
                },
                .key = key,
                .modifiers = modifiers,
                .block_exempt = options.block_exempt,
            };

            instance.lookup[index] = allocation.slot;

            assert(instance.base.slot.entries[allocation.slot].is_valid());
            assert(instance.lookup[index] != null);

            return allocation.id;
        }

        pub fn unregister(instance: *Instance, id: u32) RequestError!void {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const slot = instance.base.find_by_id(id) orelse return error.HandleUnknown;

            assert(slot < capacity);

            const entry = &instance.base.slot.entries[slot];
            const index = pack_lookup(entry.key, entry.modifiers);

            assert(index < lookup_size);
            assert(instance.lookup[index] == slot);

            instance.lookup[index] = null;

            const freed = instance.base.free_by_id_locked(id);

            assert(freed == slot);
        }

        fn pack_lookup(key: Keycode, modifiers: modifier.Set) u32 {
            const bits: u4 = modifiers.to_bits();
            const result = (@as(u32, @backingInt(key)) << 4) | bits;

            assert(result < lookup_size);

            return result;
        }
    };
}

fn make_test_key(value: Keycode, down: bool, mods: modifier.Set) Key {
    return Key{
        .value = value,
        .down = down,
        .injected = false,
        .modifiers = mods,
    };
}

const TestContext = struct {
    invoked: bool = false,
    key_value: Keycode = .silent,
    key_down: bool = false,

    fn callback(ctx: *anyopaque, key: *const Key) Response {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.invoked = true;
        self.key_value = key.value;
        self.key_down = key.down;

        return .consume;
    }
};

test "a new key registry is valid and empty" {
    var registry = KeyRegistryType(8).init();

    try std.testing.expect(registry.is_valid());
}

test "registering a key binding stores it" {
    var registry = KeyRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(
        .a,
        modifier.Set{},
        TestContext.callback,
        &ctx,
        Options{},
    );

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "several key bindings register side by side" {
    var registry = KeyRegistryType(8).init();
    var ctx1 = TestContext{};
    var ctx2 = TestContext{};
    var ctx3 = TestContext{};

    const id1 = try registry.register(.a, modifier.Set{}, TestContext.callback, &ctx1, Options{});
    const id2 = try registry.register(.b, modifier.Set{}, TestContext.callback, &ctx2, Options{});
    const id3 = try registry.register(.c, modifier.Set{}, TestContext.callback, &ctx3, Options{});

    try std.testing.expect(id1 != id2);
    try std.testing.expect(id2 != id3);
    try std.testing.expect(id1 != id3);
    try std.testing.expect(registry.is_valid());
}

test "a registered binding keeps its modifiers" {
    var registry = KeyRegistryType(8).init();
    var ctx = TestContext{};

    const mods = modifier.Set.from(.{ .ctrl = true, .shift = true });
    const id = try registry.register(.a, mods, TestContext.callback, &ctx, Options{});

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "registering past capacity is an error" {
    var registry = KeyRegistryType(2).init();
    var ctx = TestContext{};

    _ = try registry.register(.a, modifier.Set{}, TestContext.callback, &ctx, Options{});
    _ = try registry.register(.b, modifier.Set{}, TestContext.callback, &ctx, Options{});

    const result = registry.register(.c, modifier.Set{}, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.BindingsExhausted, result);
}

test "registering the same binding twice is an error" {
    var registry = KeyRegistryType(8).init();
    var ctx = TestContext{};

    _ = try registry.register(.a, modifier.Set{}, TestContext.callback, &ctx, Options{});

    const result = registry.register(.a, modifier.Set{}, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.BindingDuplicate, result);
}

test "unregistering a key binding drops it" {
    var registry = KeyRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(.a, modifier.Set{}, TestContext.callback, &ctx, Options{});

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "unregistering an unknown key binding is an error" {
    var registry = KeyRegistryType(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.HandleUnknown, result);
}

test "find returns the entry for a matching key" {
    var registry = KeyRegistryType(8).init();
    var ctx = TestContext{};

    _ = try registry.register(.a, modifier.Set{}, TestContext.callback, &ctx, Options{});

    var key = make_test_key(.a, true, modifier.Set{});
    const entry = registry.find(&key);

    try std.testing.expect(entry != null);
    try std.testing.expectEqual(.a, entry.?.key);
}

test "find returns null for a key nothing binds" {
    var registry = KeyRegistryType(8).init();
    var ctx = TestContext{};

    _ = try registry.register(.a, modifier.Set{}, TestContext.callback, &ctx, Options{});

    var key = make_test_key(.b, true, modifier.Set{});
    const entry = registry.find(&key);

    try std.testing.expect(entry == null);
}

test "clearing removes every key binding" {
    var registry = KeyRegistryType(8).init();
    var ctx = TestContext{};

    _ = try registry.register(.a, modifier.Set{}, TestContext.callback, &ctx, Options{});
    _ = try registry.register(.b, modifier.Set{}, TestContext.callback, &ctx, Options{});

    registry.clear();

    try std.testing.expect(registry.is_valid());

    var key = make_test_key(.a, true, modifier.Set{});
    const entry = registry.find(&key);

    try std.testing.expect(entry == null);
}

test "key options start at their default values" {
    const opts = Options{};

    try std.testing.expect(!opts.block_exempt);
}

test "key options carry the block_exempt flag they are built with" {
    const opts = Options{
        .block_exempt = true,
    };

    try std.testing.expect(opts.block_exempt);
}

test "a default key entry is inactive" {
    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.get_id());
    try std.testing.expect(!entry.is_active());
    try std.testing.expectEqual(Keycode.silent, entry.key);
}

test "a default key entry is valid" {
    const entry = Entry{};

    try std.testing.expect(entry.is_valid());
}
