const Keycode = @import("../keycode.zig").Keycode;
const std = @import("std");

const key_event = @import("../event/key.zig");
const response_mod = @import("../response.zig");
const filter_mod = @import("../filter.zig");
const base = @import("../registry/base.zig");
const entry_mod = @import("../registry/entry.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Response = response_mod.Response;
const WindowFilter = filter_mod.Active;

pub const capacity_default: u32 = 32;
pub const capacity_max: u32 = 128;
pub const toggle_count_max: u32 = 1000000;

pub const Error = base.BaseError;

pub const ActionCallback = *const fn (context: *anyopaque, key: *const Key) Response;
pub const ToggleCallback = *const fn (context: *anyopaque, enabled: bool) void;

pub const Options = struct {
    filter: WindowFilter = .{},
    toggle_callback: ?ToggleCallback = null,
};

const ActionMatch = struct {
    callback: ?ActionCallback,
    context: ?*anyopaque,
};

const ToggleInvocation = struct {
    callback: ToggleCallback,
    context: *anyopaque,
    enabled: bool,
};

pub const Entry = struct {
    base: entry_mod.DualBindingFilteredEntryType(ActionCallback, WindowFilter) = .{},
    toggle_callback: ?ToggleCallback = null,
    toggle_count: u32 = 0,

    pub fn get_id(entry: *const Entry) u32 {
        return entry.base.get_id();
    }

    pub fn get_context(entry: *const Entry) ?*anyopaque {
        return entry.base.get_context();
    }

    pub fn is_active(entry: *const Entry) bool {
        return entry.base.is_active();
    }

    pub fn is_valid(entry: *const Entry) bool {
        if (!entry.is_active()) {
            return true;
        }

        const valid_base = entry.base.is_valid();
        const valid_count = entry.toggle_count <= toggle_count_max;

        return valid_base and valid_count;
    }

    pub fn matches_filter(entry: *const Entry) bool {
        return entry.base.matches_filter();
    }

    pub fn invoke_action(entry: *const Entry, key: *const Key) ?Response {
        assert(entry.is_active());
        assert(entry.get_context() != null);
        assert(key.is_valid());

        return entry.base.invoke(.{key});
    }

    pub fn invoke_toggle(entry: *Entry) void {
        assert(entry.is_active());

        if (entry.toggle_callback) |callback| {
            if (entry.base.get_context()) |context| {
                callback(context, entry.base.enabled);
            }
        }
    }
};

pub fn ToggleRegistryType(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("ToggleRegistryType capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("ToggleRegistryType capacity exceeds maximum");
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
            action_binding_id: u32,
            toggle_binding_id: u32,
            action_callback: ActionCallback,
            context: ?*anyopaque,
            options: Options,
        ) Error!u32 {
            assert(action_binding_id >= 1);
            assert(toggle_binding_id >= 1);

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
                        .callback = action_callback,
                        .context = context,
                        .active = true,
                    },
                    .action_binding_id = action_binding_id,
                    .toggle_binding_id = toggle_binding_id,
                    .filter = options.filter,
                    .enabled = false,
                },
                .toggle_callback = options.toggle_callback,
                .toggle_count = 0,
            };

            assert(instance.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(instance: *Instance, id: u32) Error!void {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            _ = instance.base.free_by_id_locked(id) catch return error.NotFound;
        }

        pub fn process(instance: *Instance, binding_id: u32, key: *const Key) ?Response {
            assert(binding_id >= 1);
            assert(key.is_valid());

            const match = blk: {
                instance.base.lock();
                defer instance.base.unlock();

                assert(instance.is_valid());

                break :blk instance.resolve_action_locked(binding_id);
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

        fn resolve_action_locked(instance: *Instance, binding_id: u32) ?ActionMatch {
            assert(binding_id >= 1);

            const entries = instance.base.entries();

            for (entries) |*e| {
                if (!e.is_active()) {
                    continue;
                }

                if (e.base.action_binding_id != binding_id) {
                    continue;
                }

                if (!e.base.enabled) {
                    continue;
                }

                if (!e.matches_filter()) {
                    continue;
                }

                assert(e.get_context() != null);

                return ActionMatch{
                    .callback = e.base.get_callback(),
                    .context = e.base.get_context(),
                };
            }

            return null;
        }

        pub fn process_toggle(instance: *Instance, binding_id: u32) void {
            assert(binding_id >= 1);

            var invocations: [capacity]ToggleInvocation = undefined;
            var invocation_count: u32 = 0;

            {
                instance.base.lock();
                defer instance.base.unlock();

                assert(instance.is_valid());

                const entries = instance.base.entries();

                for (entries) |*entry| {
                    if (!entry.is_active()) {
                        continue;
                    }

                    if (entry.base.toggle_binding_id != binding_id) {
                        continue;
                    }

                    entry.base.enabled = !entry.base.enabled;

                    if (entry.toggle_count < toggle_count_max) {
                        entry.toggle_count += 1;
                    }

                    if (entry.toggle_callback) |callback| {
                        if (entry.base.get_context()) |context| {
                            assert(invocation_count < capacity);

                            invocations[invocation_count] = ToggleInvocation{
                                .callback = callback,
                                .context = context,
                                .enabled = entry.base.enabled,
                            };

                            invocation_count += 1;
                        }
                    }
                }
            }

            assert(invocation_count <= capacity);

            for (invocations[0..invocation_count]) |inv| {
                inv.callback(inv.context, inv.enabled);
            }
        }

        pub fn is_enabled(instance: *Instance, id: u32) ?bool {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const slot = instance.base.find_by_id(id) orelse return null;

            return instance.base.slot.entries[slot].base.enabled;
        }

        pub fn get_toggle_count(instance: *Instance, id: u32) ?u32 {
            assert(id >= 1);

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const slot = instance.base.find_by_id(id) orelse return null;

            return instance.base.slot.entries[slot].toggle_count;
        }

        pub fn clear(instance: *Instance) void {
            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            instance.base.clear_locked();
        }
    };
}

const TestContext = struct {
    action_invoked: bool = false,
    toggle_invoked: bool = false,
    key_value: Keycode = .silent,
    enabled_state: bool = false,

    fn action_callback(ctx: *anyopaque, key: *const Key) Response {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.action_invoked = true;
        self.key_value = key.value;
        return .consume;
    }

    fn toggle_callback(ctx: *anyopaque, enabled: bool) void {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.toggle_invoked = true;
        self.enabled_state = enabled;
    }
};

test "a new toggle registry is valid and empty" {
    var registry = ToggleRegistryType(8).init();

    try std.testing.expect(registry.is_valid());
}

test "registering with default options stores the entry" {
    var registry = ToggleRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(
        1,
        2,
        TestContext.action_callback,
        &ctx,
        Options{},
    );

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "a registered toggle keeps its callback" {
    var registry = ToggleRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(
        1,
        2,
        TestContext.action_callback,
        &ctx,
        Options{
            .toggle_callback = TestContext.toggle_callback,
        },
    );

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "several toggles register side by side" {
    var registry = ToggleRegistryType(8).init();
    var ctx1 = TestContext{};
    var ctx2 = TestContext{};

    const id1 = try registry.register(1, 2, TestContext.action_callback, &ctx1, Options{});
    const id2 = try registry.register(3, 4, TestContext.action_callback, &ctx2, Options{});

    try std.testing.expect(id1 != id2);
    try std.testing.expect(registry.is_valid());
}

test "registering past capacity is an error" {
    var registry = ToggleRegistryType(2).init();
    var ctx = TestContext{};

    _ = try registry.register(1, 2, TestContext.action_callback, &ctx, Options{});
    _ = try registry.register(3, 4, TestContext.action_callback, &ctx, Options{});

    const result = registry.register(5, 6, TestContext.action_callback, &ctx, Options{});

    try std.testing.expectError(error.RegistryFull, result);
}

test "unregistering a toggle drops it" {
    var registry = ToggleRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, 2, TestContext.action_callback, &ctx, Options{});

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "unregistering an unknown toggle is an error" {
    var registry = ToggleRegistryType(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.NotFound, result);
}

test "is_enabled follows whether a toggle is enabled" {
    var registry = ToggleRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, 2, TestContext.action_callback, &ctx, Options{});

    try std.testing.expect(registry.is_enabled(id) != null);
    try std.testing.expect(!registry.is_enabled(id).?);
}

test "is_enabled returns null for an unknown id" {
    var registry = ToggleRegistryType(8).init();

    try std.testing.expect(registry.is_enabled(999) == null);
}

test "get_toggle_count follows how often a toggle flipped" {
    var registry = ToggleRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, 2, TestContext.action_callback, &ctx, Options{});

    try std.testing.expect(registry.get_toggle_count(id) != null);
    try std.testing.expectEqual(@as(u32, 0), registry.get_toggle_count(id).?);
}

test "get_toggle_count returns null for an unknown id" {
    var registry = ToggleRegistryType(8).init();

    try std.testing.expect(registry.get_toggle_count(999) == null);
}

test "clearing removes every toggle" {
    var registry = ToggleRegistryType(8).init();
    var ctx = TestContext{};

    const id1 = try registry.register(1, 2, TestContext.action_callback, &ctx, Options{});
    const id2 = try registry.register(3, 4, TestContext.action_callback, &ctx, Options{});

    registry.clear();

    try std.testing.expect(registry.is_enabled(id1) == null);
    try std.testing.expect(registry.is_enabled(id2) == null);
    try std.testing.expect(registry.is_valid());
}

test "toggle options start at their default values" {
    const opts = Options{};

    try std.testing.expect(opts.toggle_callback == null);
}

test "toggle options carry the callback they are built with" {
    const opts = Options{
        .toggle_callback = TestContext.toggle_callback,
    };

    try std.testing.expect(opts.toggle_callback != null);
}

test "a default toggle entry is inactive and unflipped" {
    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.get_id());
    try std.testing.expect(entry.get_context() == null);
    try std.testing.expect(!entry.is_active());
    try std.testing.expect(entry.toggle_callback == null);
    try std.testing.expectEqual(@as(u32, 0), entry.toggle_count);
}

test "a default toggle entry is valid" {
    const entry = Entry{};

    try std.testing.expect(entry.is_valid());
}

test "a toggle entry is invalid past its count bound" {
    var entry = Entry{};

    entry.toggle_count = toggle_count_max;
    try std.testing.expect(entry.is_valid());

    entry.toggle_count = toggle_count_max + 1;
    entry.base.base.active = true;
    try std.testing.expect(!entry.is_valid());
}

test "a toggle entry reports the id, callback, and context it carries" {
    var ctx = TestContext{};

    const entry = Entry{
        .base = .{
            .base = .{
                .id = 42,
                .callback = TestContext.action_callback,
                .context = &ctx,
                .active = true,
            },
            .action_binding_id = 10,
            .toggle_binding_id = 20,
        },
        .toggle_callback = TestContext.toggle_callback,
        .toggle_count = 5,
    };

    try std.testing.expectEqual(@as(u32, 42), entry.get_id());
    try std.testing.expect(entry.get_context() != null);
    try std.testing.expect(entry.is_active());
}

test "processing a toggle flips it and counts the flip" {
    var registry = ToggleRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, 2, TestContext.action_callback, &ctx, Options{
        .toggle_callback = TestContext.toggle_callback,
    });

    registry.process_toggle(2);

    try std.testing.expect(registry.is_enabled(id).?);
    try std.testing.expectEqual(@as(u32, 1), registry.get_toggle_count(id).?);
    try std.testing.expect(ctx.toggle_invoked);
    try std.testing.expect(ctx.enabled_state);

    registry.process_toggle(2);

    try std.testing.expect(!registry.is_enabled(id).?);
    try std.testing.expectEqual(@as(u32, 2), registry.get_toggle_count(id).?);
    try std.testing.expect(!ctx.enabled_state);
}

test "the toggle count saturates at its maximum" {
    var registry = ToggleRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, 2, TestContext.action_callback, &ctx, Options{});

    const slot = registry.base.find_by_id(id).?;
    registry.base.slot.entries[slot].toggle_count = toggle_count_max;

    registry.process_toggle(2);

    try std.testing.expectEqual(toggle_count_max, registry.get_toggle_count(id).?);
    try std.testing.expect(registry.is_valid());
}

test "constants: valid ranges" {
    try std.testing.expect(capacity_default >= 1);
    try std.testing.expect(capacity_max >= capacity_default);
    try std.testing.expect(capacity_max <= 128);
    try std.testing.expect(toggle_count_max >= 1);
}
