const Keycode = @import("../keycode.zig").Keycode;
const std = @import("std");

const key_event = @import("../event/key.zig");
const response_mod = @import("../response.zig");
const base = @import("../registry/base.zig");
const entry_mod = @import("../registry/entry.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Response = response_mod.Response;

pub const capacity_default: u32 = 32;
pub const capacity_max: u32 = 128;

pub const Error = base.BaseError;

pub const Callback = *const fn (context: *anyopaque, key: *const Key) Response;

pub const Entry = struct {
    base: entry_mod.BindingEntryType(Callback) = .{},
    fired: bool = false,

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

    pub fn is_enabled(entry: *const Entry) bool {
        return entry.base.is_enabled();
    }

    pub fn set_enabled(entry: *Entry, value: bool) void {
        entry.base.set_enabled(value);
    }

    pub fn get_binding_id(entry: *const Entry) u32 {
        return entry.base.get_binding_id();
    }

    pub fn is_valid(entry: *const Entry) bool {
        return entry.base.is_valid();
    }

    pub fn invoke(entry: *const Entry, key: *const Key) ?Response {
        assert(entry.is_active());
        assert(entry.get_callback() != null);
        assert(entry.get_context() != null);
        assert(key.is_valid());

        return entry.base.invoke(.{key});
    }
};

const Invocation = struct {
    callback: ?Callback,
    context: ?*anyopaque,
};

pub fn OneShotRegistryType(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("OneShotRegistryType capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("OneShotRegistryType capacity exceeds maximum");
    }

    return struct {
        const Instance = @This();

        const Base = base.BaseRegistryType(Entry, capacity, .{
            .has_mutex = true,
        });

        base: Base = Base.init(),

        pub fn init() Instance {
            return Instance{};
        }

        pub fn is_valid(instance: *const Instance) bool {
            return instance.base.is_valid();
        }

        pub fn register(
            instance: *Instance,
            binding_id: u32,
            callback: Callback,
            context: ?*anyopaque,
        ) Error!u32 {
            assert(binding_id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const allocation = instance.base.allocate_locked() catch return error.RegistryFull;

            assert(allocation.slot < capacity);
            assert(allocation.id >= 1);

            instance.base.slot.entries[allocation.slot] = Entry{
                .base = .{
                    .base = .{
                        .id = allocation.id,
                        .callback = callback,
                        .context = context,
                        .active = true,
                    },
                    .binding_id = binding_id,
                    .enabled = true,
                },
                .fired = false,
            };

            assert(instance.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(instance: *Instance, id: u32) Error!void {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            _ = try instance.base.free_by_id_locked(id);
        }

        pub fn process(instance: *Instance, binding_id: u32, key: *const Key) ?Response {
            assert(binding_id >= 1);
            assert(key.is_valid());

            const match = blk: {
                instance.base.lock();
                defer instance.base.unlock();

                assert(instance.is_valid());

                break :blk instance.resolve_locked(binding_id);
            };

            if (match) |m| {
                if (m.callback) |callback| {
                    if (m.context) |context| {
                        const response = callback(context, key);

                        assert(response.is_valid());

                        return response;
                    }
                }

                return .consume;
            }

            return null;
        }

        fn resolve_locked(instance: *Instance, binding_id: u32) ?Invocation {
            assert(binding_id >= 1);

            const entries = instance.base.entries();

            for (entries) |*e| {
                if (!e.is_active()) {
                    continue;
                }

                if (e.get_binding_id() != binding_id) {
                    continue;
                }

                if (!e.is_enabled() or e.fired) {
                    continue;
                }

                e.fired = true;

                assert(e.get_callback() != null);
                assert(e.get_context() != null);

                return Invocation{
                    .callback = e.get_callback(),
                    .context = e.get_context(),
                };
            }

            return null;
        }

        pub fn reset(instance: *Instance, id: u32) Error!void {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const entry = instance.base.get_by_id(id) orelse return error.NotFound;

            assert(entry.is_active());

            entry.fired = false;
            entry.set_enabled(true);
        }

        pub fn reset_all(instance: *Instance) void {
            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const entries = instance.base.entries();

            for (entries) |*e| {
                if (e.is_active()) {
                    e.fired = false;
                    e.set_enabled(true);
                }
            }
        }

        pub fn is_fired(instance: *Instance, id: u32) ?bool {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const slot = instance.base.find_by_id(id) orelse return null;

            return instance.base.slot.entries[slot].fired;
        }

        pub fn clear(instance: *Instance) void {
            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            instance.base.clear_locked();
        }
    };
}

fn make_test_key(value: Keycode, down: bool) Key {
    return Key{
        .value = value,
        .down = down,
        .injected = false,
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

test "a new oneshot registry is valid and empty" {
    var registry = OneShotRegistryType(8).init();

    try std.testing.expect(registry.is_valid());
}

test "a oneshot can be registered and dropped again" {
    var registry = OneShotRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, TestContext.callback, &ctx);

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "several oneshots register side by side" {
    var registry = OneShotRegistryType(8).init();
    var ctx1 = TestContext{};
    var ctx2 = TestContext{};
    var ctx3 = TestContext{};

    const id1 = try registry.register(1, TestContext.callback, &ctx1);
    const id2 = try registry.register(2, TestContext.callback, &ctx2);
    const id3 = try registry.register(3, TestContext.callback, &ctx3);

    try std.testing.expect(id1 != id2);
    try std.testing.expect(id2 != id3);
    try std.testing.expect(id1 != id3);
    try std.testing.expect(registry.is_valid());
}

test "registering past capacity is an error" {
    var registry = OneShotRegistryType(2).init();
    var ctx = TestContext{};

    _ = try registry.register(1, TestContext.callback, &ctx);
    _ = try registry.register(2, TestContext.callback, &ctx);

    const result = registry.register(3, TestContext.callback, &ctx);

    try std.testing.expectError(error.RegistryFull, result);
}

test "unregistering an unknown oneshot is an error" {
    var registry = OneShotRegistryType(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.NotFound, result);
}

test "processing a oneshot invokes its callback" {
    var registry = OneShotRegistryType(8).init();
    var ctx = TestContext{};

    _ = try registry.register(1, TestContext.callback, &ctx);

    const key = make_test_key(.a, true);
    const response = registry.process(1, &key);

    try std.testing.expect(ctx.invoked);
    try std.testing.expectEqual(.a, ctx.key_value);
    try std.testing.expect(ctx.key_down);
    try std.testing.expect(response != null);
    try std.testing.expectEqual(Response.consume, response.?);
}

test "processing an unknown binding returns null" {
    var registry = OneShotRegistryType(8).init();

    const key = make_test_key(.a, true);
    const response = registry.process(999, &key);

    try std.testing.expect(response == null);
}

test "is_fired follows whether a oneshot has fired" {
    var registry = OneShotRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, TestContext.callback, &ctx);

    try std.testing.expect(registry.is_fired(id) != null);
    try std.testing.expect(!registry.is_fired(id).?);

    const key = make_test_key(.a, true);
    _ = registry.process(1, &key);

    try std.testing.expect(registry.is_fired(id).?);
}

test "is_fired returns null for an unknown id" {
    var registry = OneShotRegistryType(8).init();

    try std.testing.expect(registry.is_fired(999) == null);
}

test "clearing removes every oneshot" {
    var registry = OneShotRegistryType(8).init();
    var ctx = TestContext{};

    const id1 = try registry.register(1, TestContext.callback, &ctx);
    const id2 = try registry.register(2, TestContext.callback, &ctx);

    registry.clear();

    try std.testing.expect(registry.is_fired(id1) == null);
    try std.testing.expect(registry.is_fired(id2) == null);
    try std.testing.expect(registry.is_valid());
}

test "a oneshot fires only once" {
    var registry = OneShotRegistryType(8).init();
    var ctx = TestContext{};

    _ = try registry.register(1, TestContext.callback, &ctx);

    const key = make_test_key(.a, true);

    const first = registry.process(1, &key);

    try std.testing.expect(first != null);
    try std.testing.expect(ctx.invoked);

    ctx.invoked = false;
    const second = registry.process(1, &key);

    try std.testing.expect(second == null);
    try std.testing.expect(!ctx.invoked);
}

test "resetting a oneshot lets it fire again" {
    var registry = OneShotRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, TestContext.callback, &ctx);

    const key = make_test_key(.a, true);
    _ = registry.process(1, &key);

    try std.testing.expect(registry.is_fired(id).?);

    try registry.reset(id);

    try std.testing.expect(!registry.is_fired(id).?);
}

test "resetting all lets every oneshot fire again" {
    var registry = OneShotRegistryType(8).init();
    var ctx = TestContext{};

    const id1 = try registry.register(1, TestContext.callback, &ctx);
    const id2 = try registry.register(2, TestContext.callback, &ctx);

    const key = make_test_key(.a, true);
    _ = registry.process(1, &key);
    _ = registry.process(2, &key);

    registry.reset_all();

    try std.testing.expect(!registry.is_fired(id1).?);
    try std.testing.expect(!registry.is_fired(id2).?);
}

test "a default oneshot entry is inactive and unfired" {
    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.get_id());
    try std.testing.expect(!entry.is_active());
    try std.testing.expect(!entry.fired);
}

test "a default oneshot entry is valid" {
    const entry = Entry{};

    try std.testing.expect(entry.is_valid());
}

test "constants: valid ranges" {
    try std.testing.expect(capacity_default >= 1);
    try std.testing.expect(capacity_max >= capacity_default);
    try std.testing.expect(capacity_max <= 128);
}
