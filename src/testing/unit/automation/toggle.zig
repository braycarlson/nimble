const std = @import("std");
const input = @import("input");

const toggle = input.automation.toggle;
const key_event = input.event.key;
const response_mod = input.response;
const filter_mod = input.filter;

const ToggleRegistry = toggle.ToggleRegistry;
const Entry = toggle.Entry;
const Options = toggle.Options;
const Key = key_event.Key;
const Response = response_mod.Response;
const WindowFilter = filter_mod.WindowFilter;

fn make_test_key(value: u8, down: bool) Key {
    return Key{
        .value = value,
        .scan = 0,
        .down = down,
        .injected = false,
        .extended = false,
        .extra = 0,
    };
}

const TestContext = struct {
    action_invoked: bool = false,
    toggle_invoked: bool = false,
    key_value: u8 = 0,
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

test "ToggleRegistry: init creates valid registry" {
    var registry = ToggleRegistry(8).init();

    try std.testing.expect(registry.is_valid());
}

test "ToggleRegistry: register with default options" {
    var registry = ToggleRegistry(8).init();
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

test "ToggleRegistry: register with toggle callback" {
    var registry = ToggleRegistry(8).init();
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

test "ToggleRegistry: register multiple entries" {
    var registry = ToggleRegistry(8).init();
    var ctx1 = TestContext{};
    var ctx2 = TestContext{};

    const id1 = try registry.register(1, 2, TestContext.action_callback, &ctx1, Options{});
    const id2 = try registry.register(3, 4, TestContext.action_callback, &ctx2, Options{});

    try std.testing.expect(id1 != id2);
    try std.testing.expect(registry.is_valid());
}

test "ToggleRegistry: registry full error" {
    var registry = ToggleRegistry(2).init();
    var ctx = TestContext{};

    _ = try registry.register(1, 2, TestContext.action_callback, &ctx, Options{});
    _ = try registry.register(3, 4, TestContext.action_callback, &ctx, Options{});

    const result = registry.register(5, 6, TestContext.action_callback, &ctx, Options{});

    try std.testing.expectError(error.RegistryFull, result);
}

test "ToggleRegistry: unregister entry" {
    var registry = ToggleRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, 2, TestContext.action_callback, &ctx, Options{});

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "ToggleRegistry: unregister not found error" {
    var registry = ToggleRegistry(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.NotFound, result);
}

test "ToggleRegistry: is_enabled returns correct state" {
    var registry = ToggleRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, 2, TestContext.action_callback, &ctx, Options{});

    try std.testing.expect(registry.is_enabled(id) != null);
    try std.testing.expect(!registry.is_enabled(id).?);
}

test "ToggleRegistry: is_enabled returns null for invalid id" {
    var registry = ToggleRegistry(8).init();

    try std.testing.expect(registry.is_enabled(999) == null);
}

test "ToggleRegistry: get_toggle_count returns correct value" {
    var registry = ToggleRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, 2, TestContext.action_callback, &ctx, Options{});

    try std.testing.expect(registry.get_toggle_count(id) != null);
    try std.testing.expectEqual(@as(u32, 0), registry.get_toggle_count(id).?);
}

test "ToggleRegistry: get_toggle_count returns null for invalid id" {
    var registry = ToggleRegistry(8).init();

    try std.testing.expect(registry.get_toggle_count(999) == null);
}

test "ToggleRegistry: clear removes all entries" {
    var registry = ToggleRegistry(8).init();
    var ctx = TestContext{};

    const id1 = try registry.register(1, 2, TestContext.action_callback, &ctx, Options{});
    const id2 = try registry.register(3, 4, TestContext.action_callback, &ctx, Options{});

    registry.clear();

    try std.testing.expect(registry.is_enabled(id1) == null);
    try std.testing.expect(registry.is_enabled(id2) == null);
    try std.testing.expect(registry.is_valid());
}

test "Options: default values" {
    const opts = Options{};

    try std.testing.expect(opts.toggle_callback == null);
}

test "Options: with toggle callback" {
    const opts = Options{
        .toggle_callback = TestContext.toggle_callback,
    };

    try std.testing.expect(opts.toggle_callback != null);
}

test "Entry: default state" {
    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.get_id());
    try std.testing.expect(entry.get_context() == null);
    try std.testing.expect(!entry.is_active());
    try std.testing.expect(entry.toggle_callback == null);
    try std.testing.expectEqual(@as(u32, 0), entry.toggle_count);
}

test "Entry: is_valid for inactive entry" {
    const entry = Entry{};

    try std.testing.expect(entry.is_valid());
}

test "Entry: is_valid checks toggle_count bounds" {
    var entry = Entry{};

    entry.toggle_count = toggle.toggle_count_max;
    try std.testing.expect(entry.is_valid());

    entry.toggle_count = toggle.toggle_count_max + 1;
    entry.base.base.active = true;
    try std.testing.expect(!entry.is_valid());
}

test "Entry: get methods with context" {
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

test "constants: valid ranges" {
    try std.testing.expect(toggle.capacity_default >= 1);
    try std.testing.expect(toggle.capacity_max >= toggle.capacity_default);
    try std.testing.expect(toggle.capacity_max <= 128);
    try std.testing.expect(toggle.toggle_count_max >= 1);
}
