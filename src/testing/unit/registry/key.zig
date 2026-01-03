const std = @import("std");
const input = @import("input");

const key_registry = input.registry.key;
const key_event = input.event.key;
const response_mod = input.response;
const modifier = input.modifier;
const filter_mod = input.filter;

const KeyRegistry = key_registry.KeyRegistry;
const Options = key_registry.Options;
const Entry = key_registry.Entry;
const Key = key_event.Key;
const Response = response_mod.Response;
const WindowFilter = filter_mod.WindowFilter;

fn make_test_key(value: u8, down: bool, mods: modifier.Set) Key {
    return Key{
        .value = value,
        .scan = 0,
        .down = down,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = mods,
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

test "KeyRegistry: init creates valid registry" {
    var registry = KeyRegistry(8).init();

    try std.testing.expect(registry.is_valid());
}

test "KeyRegistry: register binding" {
    var registry = KeyRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(
        'A',
        modifier.Set{},
        TestContext.callback,
        &ctx,
        Options{},
    );

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "KeyRegistry: register multiple bindings" {
    var registry = KeyRegistry(8).init();
    var ctx1 = TestContext{};
    var ctx2 = TestContext{};
    var ctx3 = TestContext{};

    const id1 = try registry.register('A', modifier.Set{}, TestContext.callback, &ctx1, Options{});
    const id2 = try registry.register('B', modifier.Set{}, TestContext.callback, &ctx2, Options{});
    const id3 = try registry.register('C', modifier.Set{}, TestContext.callback, &ctx3, Options{});

    try std.testing.expect(id1 != id2);
    try std.testing.expect(id2 != id3);
    try std.testing.expect(id1 != id3);
    try std.testing.expect(registry.is_valid());
}

test "KeyRegistry: register with modifiers" {
    var registry = KeyRegistry(8).init();
    var ctx = TestContext{};

    const mods = modifier.Set.from(.{ .ctrl = true, .shift = true });
    const id = try registry.register('A', mods, TestContext.callback, &ctx, Options{});

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "KeyRegistry: registry full error" {
    var registry = KeyRegistry(2).init();
    var ctx = TestContext{};

    _ = try registry.register('A', modifier.Set{}, TestContext.callback, &ctx, Options{});
    _ = try registry.register('B', modifier.Set{}, TestContext.callback, &ctx, Options{});

    const result = registry.register('C', modifier.Set{}, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.RegistryFull, result);
}

test "KeyRegistry: already registered error" {
    var registry = KeyRegistry(8).init();
    var ctx = TestContext{};

    _ = try registry.register('A', modifier.Set{}, TestContext.callback, &ctx, Options{});

    const result = registry.register('A', modifier.Set{}, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.AlreadyRegistered, result);
}

test "KeyRegistry: unregister binding" {
    var registry = KeyRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register('A', modifier.Set{}, TestContext.callback, &ctx, Options{});

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "KeyRegistry: unregister not found error" {
    var registry = KeyRegistry(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.NotFound, result);
}

test "KeyRegistry: find returns entry for matching key" {
    var registry = KeyRegistry(8).init();
    var ctx = TestContext{};

    _ = try registry.register('A', modifier.Set{}, TestContext.callback, &ctx, Options{});

    var key = make_test_key('A', true, modifier.Set{});
    const entry = registry.find(&key);

    try std.testing.expect(entry != null);
    try std.testing.expectEqual(@as(u8, 'A'), entry.?.key);
}

test "KeyRegistry: find returns null for non-matching key" {
    var registry = KeyRegistry(8).init();
    var ctx = TestContext{};

    _ = try registry.register('A', modifier.Set{}, TestContext.callback, &ctx, Options{});

    var key = make_test_key('B', true, modifier.Set{});
    const entry = registry.find(&key);

    try std.testing.expect(entry == null);
}

test "KeyRegistry: pause and unpause" {
    var registry = KeyRegistry(8).init();

    try std.testing.expect(!registry.is_paused());

    registry.set_paused(true);

    try std.testing.expect(registry.is_paused());

    registry.set_paused(false);

    try std.testing.expect(!registry.is_paused());
}

test "KeyRegistry: clear removes all bindings" {
    var registry = KeyRegistry(8).init();
    var ctx = TestContext{};

    _ = try registry.register('A', modifier.Set{}, TestContext.callback, &ctx, Options{});
    _ = try registry.register('B', modifier.Set{}, TestContext.callback, &ctx, Options{});

    registry.clear();

    try std.testing.expect(registry.is_valid());

    var key = make_test_key('A', true, modifier.Set{});
    const entry = registry.find(&key);

    try std.testing.expect(entry == null);
}

test "Options: default values" {
    const opts = Options{};

    try std.testing.expect(!opts.pause_exempt);
}

test "Options: with pause_exempt" {
    const opts = Options{
        .pause_exempt = true,
    };

    try std.testing.expect(opts.pause_exempt);
}

test "Entry: default state" {
    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.get_id());
    try std.testing.expect(!entry.is_active());
    try std.testing.expectEqual(@as(u8, 0), entry.key);
}

test "Entry: is_valid for inactive entry" {
    const entry = Entry{};

    try std.testing.expect(entry.is_valid());
}

test "constants: valid ranges" {
    try std.testing.expect(key_registry.capacity_default >= 1);
    try std.testing.expect(key_registry.capacity_max >= key_registry.capacity_default);
}
