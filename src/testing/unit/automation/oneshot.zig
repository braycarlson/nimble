const std = @import("std");
const input = @import("input");

const oneshot = input.automation.oneshot;
const key_event = input.event.key;
const response_mod = input.response;

const OneShotRegistry = oneshot.OneShotRegistry;
const Key = key_event.Key;
const Response = response_mod.Response;

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
    invoked: bool = false,
    key_value: u8 = 0,
    key_down: bool = false,

    fn callback(ctx: *anyopaque, key: *const Key) Response {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.invoked = true;
        self.key_value = key.value;
        self.key_down = key.down;
        return .consume;
    }

    fn pass_callback(ctx: *anyopaque, key: *const Key) Response {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.invoked = true;
        self.key_value = key.value;
        self.key_down = key.down;
        return .pass;
    }
};

test "OneShotRegistry: init creates valid registry" {
    var registry = OneShotRegistry(8).init();

    try std.testing.expect(registry.is_valid());
}

test "OneShotRegistry: register and unregister" {
    var registry = OneShotRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, TestContext.callback, &ctx);

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "OneShotRegistry: register multiple entries" {
    var registry = OneShotRegistry(8).init();
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

test "OneShotRegistry: registry full error" {
    var registry = OneShotRegistry(2).init();
    var ctx = TestContext{};

    _ = try registry.register(1, TestContext.callback, &ctx);
    _ = try registry.register(2, TestContext.callback, &ctx);

    const result = registry.register(3, TestContext.callback, &ctx);

    try std.testing.expectError(error.RegistryFull, result);
}

test "OneShotRegistry: unregister not found error" {
    var registry = OneShotRegistry(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.NotFound, result);
}

test "OneShotRegistry: process invokes callback" {
    var registry = OneShotRegistry(8).init();
    var ctx = TestContext{};

    _ = try registry.register(1, TestContext.callback, &ctx);

    const key = make_test_key('A', true);
    const response = registry.process(1, &key);

    try std.testing.expect(ctx.invoked);
    try std.testing.expectEqual('A', ctx.key_value);
    try std.testing.expect(ctx.key_down);
    try std.testing.expect(response != null);
    try std.testing.expectEqual(Response.consume, response.?);
}

test "OneShotRegistry: process returns null for non-existent binding" {
    var registry = OneShotRegistry(8).init();

    const key = make_test_key('A', true);
    const response = registry.process(999, &key);

    try std.testing.expect(response == null);
}

test "OneShotRegistry: is_fired returns correct state" {
    var registry = OneShotRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, TestContext.callback, &ctx);

    try std.testing.expect(registry.is_fired(id) != null);
    try std.testing.expect(!registry.is_fired(id).?);

    const key = make_test_key('A', true);
    _ = registry.process(1, &key);

    try std.testing.expect(registry.is_fired(id).?);
}

test "OneShotRegistry: is_fired returns null for invalid id" {
    var registry = OneShotRegistry(8).init();

    try std.testing.expect(registry.is_fired(999) == null);
}

test "OneShotRegistry: clear removes all entries" {
    var registry = OneShotRegistry(8).init();
    var ctx = TestContext{};

    const id1 = try registry.register(1, TestContext.callback, &ctx);
    const id2 = try registry.register(2, TestContext.callback, &ctx);

    registry.clear();

    try std.testing.expect(registry.is_fired(id1) == null);
    try std.testing.expect(registry.is_fired(id2) == null);
    try std.testing.expect(registry.is_valid());
}

test "OneShotRegistry: oneshot fires only once" {
    var registry = OneShotRegistry(8).init();
    var ctx = TestContext{};

    _ = try registry.register(1, TestContext.callback, &ctx);

    const key = make_test_key('A', true);

    const first = registry.process(1, &key);
    try std.testing.expect(first != null);
    try std.testing.expect(ctx.invoked);

    ctx.invoked = false;
    const second = registry.process(1, &key);

    try std.testing.expect(second == null);
    try std.testing.expect(!ctx.invoked);
}

test "OneShotRegistry: reset restores fired state" {
    var registry = OneShotRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(1, TestContext.callback, &ctx);

    const key = make_test_key('A', true);
    _ = registry.process(1, &key);

    try std.testing.expect(registry.is_fired(id).?);

    try registry.reset(id);

    try std.testing.expect(!registry.is_fired(id).?);
}

test "OneShotRegistry: reset_all restores all" {
    var registry = OneShotRegistry(8).init();
    var ctx = TestContext{};

    const id1 = try registry.register(1, TestContext.callback, &ctx);
    const id2 = try registry.register(2, TestContext.callback, &ctx);

    const key = make_test_key('A', true);
    _ = registry.process(1, &key);
    _ = registry.process(2, &key);

    registry.reset_all();

    try std.testing.expect(!registry.is_fired(id1).?);
    try std.testing.expect(!registry.is_fired(id2).?);
}

test "Entry: default state" {
    const Entry = oneshot.Entry;

    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.get_id());
    try std.testing.expect(!entry.is_active());
    try std.testing.expect(!entry.fired);
}

test "Entry: is_valid for inactive entry" {
    const Entry = oneshot.Entry;

    const entry = Entry{};
    try std.testing.expect(entry.is_valid());
}

test "constants: valid ranges" {
    try std.testing.expect(oneshot.capacity_default >= 1);
    try std.testing.expect(oneshot.capacity_max >= oneshot.capacity_default);
    try std.testing.expect(oneshot.capacity_max <= 128);
}
