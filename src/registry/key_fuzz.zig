const std = @import("std");

const event_key = @import("../event/key.zig");
const fuzz = @import("../testing/fuzz.zig");
const key_registry = @import("key.zig");
const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const response = @import("../response.zig");

const Keycode = keycode.Keycode;
const Allocator = std.mem.Allocator;
const Key = event_key.Key;
const Response = response.Response;
const assert = std.debug.assert;

const Operation = enum {
    register,
    register_duplicate,
    unregister,
    unregister_arbitrary,
    process,
    process_registered,
    process_blocked,
    find,
    set_paused,
    clear,
};

const capacity: u32 = 16;
const id_arbitrary_max: u32 = 1024;
const keys = [_]Keycode{ .a, .b, .c, .d, .e, .f, .g, .h };
const modifier_sets = [_]u4{
    modifier.flag_none,
    modifier.flag_ctrl,
    modifier.flag_ctrl | modifier.flag_shift,
    modifier.flag_all,
};

const KeyRegistry = key_registry.KeyRegistryType(capacity);

comptime {
    assert(capacity >= 1);
    assert(capacity <= key_registry.capacity_max);
    assert(keys.len * modifier_sets.len > capacity);
}

const Context = struct {
    invocations: u32 = 0,
    value_last: Keycode = .silent,
    modifiers_last: modifier.Set = .{},
    response_next: Response = .pass,
};

const Binding = struct {
    id: u32,
    value: Keycode,
    modifiers: modifier.Set,
    block_exempt: bool,
    pause_exempt: bool,
};

const ModelType = struct {
    bindings: [capacity]Binding = undefined,
    count: u32 = 0,
    paused: bool = false,

    fn find_binding(model: *const ModelType, value: Keycode, modifiers: modifier.Set) ?u32 {
        assert(model.count <= capacity);

        var index: u32 = 0;

        while (index < model.count) : (index += 1) {
            assert(index < capacity);

            const binding = model.bindings[index];

            if (binding.value == value and binding.modifiers.flags == modifiers.flags) {
                return index;
            }
        }

        assert(index == model.count);

        return null;
    }

    fn find_id(model: *const ModelType, id: u32) ?u32 {
        assert(model.count <= capacity);

        var index: u32 = 0;

        while (index < model.count) : (index += 1) {
            assert(index < capacity);

            if (model.bindings[index].id == id) return index;
        }

        assert(index == model.count);

        return null;
    }

    fn add(model: *ModelType, binding: Binding) void {
        assert(model.count < capacity);
        assert(binding.id >= 1);
        assert(model.find_binding(binding.value, binding.modifiers) == null);
        assert(model.find_id(binding.id) == null);

        model.bindings[model.count] = binding;
        model.count += 1;

        assert(model.count <= capacity);
    }

    fn remove(model: *ModelType, index: u32) void {
        assert(index < model.count);
        assert(model.count >= 1);

        model.count -= 1;

        if (index < model.count) {
            model.bindings[index] = model.bindings[model.count];
        }

        assert(model.count < capacity);
    }

    fn clear(model: *ModelType) void {
        assert(model.count <= capacity);

        model.count = 0;

        assert(model.count == 0);
    }
};

pub fn main(gpa: Allocator, args: fuzz.FuzzArgs) !void {
    assert(args.events_max >= 1);

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();
    const weights = fuzz.random_enum_weights(random, Operation);

    const registry = try gpa.create(KeyRegistry);
    defer gpa.destroy(registry);

    registry.* = KeyRegistry.init();

    var context = Context{};
    var model = ModelType{};

    verify(registry, &model);

    var event: u32 = 0;

    while (event < args.events_max) : (event += 1) {
        const operation = fuzz.random_enum_weighted(random, Operation, weights);

        apply(random, registry, &model, &context, operation);
        verify(registry, &model);
    }

    assert(event == args.events_max);
}

fn apply(
    random: std.Random,
    registry: *KeyRegistry,
    model: *ModelType,
    context: *Context,
    operation: Operation,
) void {
    assert(registry.is_valid());

    switch (operation) {
        .register => {
            const value = random_value(random);
            const modifiers = random_modifiers(random);

            register(random, registry, model, context, value, modifiers);
        },
        .register_duplicate => {
            const index = random_index(random, model) orelse return;
            const existing = model.bindings[index];

            register(random, registry, model, context, existing.value, existing.modifiers);
        },
        .unregister => {
            const index = random_index(random, model) orelse return;

            unregister(registry, model, model.bindings[index].id);
        },
        .unregister_arbitrary => {
            const id = random.intRangeAtMost(u32, 1, id_arbitrary_max);

            unregister(registry, model, id);
        },
        .process => {
            const value = random_value(random);
            const modifiers = random_modifiers(random);

            process(random, registry, model, context, value, modifiers);
        },
        .process_registered => {
            const index = random_index(random, model) orelse return;
            const existing = model.bindings[index];

            process(random, registry, model, context, existing.value, existing.modifiers);
        },
        .process_blocked => process_blocked(random, registry, model, context),
        .find, .set_paused, .clear => apply_query(random, registry, model, operation),
    }
}

fn apply_query(
    random: std.Random,
    registry: *KeyRegistry,
    model: *ModelType,
    operation: Operation,
) void {
    assert(registry.is_valid());

    switch (operation) {
        .find => {
            const value = random_value(random);
            const modifiers = random_modifiers(random);
            const key = make_key(value, modifiers);

            const expected = model.find_binding(value, modifiers) != null;

            assert((registry.find(&key) != null) == expected);
        },
        .set_paused => {
            const paused = random.boolean();

            registry.set_paused(paused);
            model.paused = paused;

            assert(registry.is_paused() == paused);
        },
        .clear => {
            registry.clear();
            model.clear();

            assert(registry.base.count() == 0);
            assert(registry.is_paused() == model.paused);
        },
        else => unreachable,
    }
}

fn register(
    random: std.Random,
    registry: *KeyRegistry,
    model: *ModelType,
    context: *Context,
    value: Keycode,
    modifiers: modifier.Set,
) void {
    assert(modifiers.flags <= modifier.flag_all);

    const block_exempt = random.boolean();
    const pause_exempt = random.boolean();
    const duplicate = model.find_binding(value, modifiers) != null;
    const full = model.count == capacity;

    const outcome = registry.register(value, modifiers, callback, context, .{
        .block_exempt = block_exempt,
        .pause_exempt = pause_exempt,
    });

    const id = outcome catch |failure| switch (failure) {
        error.AlreadyRegistered => {
            assert(duplicate);

            return;
        },
        error.RegistryFull => {
            assert(!duplicate);
            assert(full);

            return;
        },
        error.NotFound, error.InvalidSlot => unreachable,
    };

    assert(!duplicate);
    assert(!full);
    assert(id >= 1);

    model.add(.{
        .id = id,
        .value = value,
        .modifiers = modifiers,
        .block_exempt = block_exempt,
        .pause_exempt = pause_exempt,
    });
}

fn unregister(registry: *KeyRegistry, model: *ModelType, id: u32) void {
    assert(id >= 1);

    const known = model.find_id(id);

    if (registry.unregister(id)) |_| {
        assert(known != null);

        model.remove(known.?);
    } else |failure| switch (failure) {
        error.NotFound => assert(known == null),
        error.RegistryFull, error.AlreadyRegistered, error.InvalidSlot => unreachable,
    }
}

fn process(
    random: std.Random,
    registry: *KeyRegistry,
    model: *const ModelType,
    context: *Context,
    value: Keycode,
    modifiers: modifier.Set,
) void {
    const key = make_key(value, modifiers);
    const index = model.find_binding(value, modifiers);

    const expected = blk: {
        const found = index orelse break :blk false;

        if (model.paused and !model.bindings[found].pause_exempt) break :blk false;

        break :blk true;
    };

    context.response_next = fuzz.random_enum_uniform(random, Response);

    const invocations_before = context.invocations;
    const result = registry.process(&key);

    check_invocation(context, result, expected, value, modifiers, invocations_before);
}

fn process_blocked(
    random: std.Random,
    registry: *KeyRegistry,
    model: *const ModelType,
    context: *Context,
) void {
    const value = random_value(random);
    const modifiers = random_modifiers(random);
    const key = make_key(value, modifiers);
    const index = model.find_binding(value, modifiers);

    const expected = blk: {
        const found = index orelse break :blk false;

        break :blk model.bindings[found].block_exempt;
    };

    context.response_next = fuzz.random_enum_uniform(random, Response);

    const invocations_before = context.invocations;
    const result = registry.process_blocked(&key);

    check_invocation(context, result, expected, value, modifiers, invocations_before);
}

fn check_invocation(
    context: *const Context,
    result: ?Response,
    expected: bool,
    value: Keycode,
    modifiers: modifier.Set,
    invocations_before: u32,
) void {
    const expected_delta: u32 = @intFromBool(expected);

    assert(context.invocations == invocations_before + expected_delta);

    if (!expected) {
        assert(result == null);

        return;
    }

    assert(result != null);
    assert(result.? == context.response_next);
    assert(context.value_last == value);
    assert(context.modifiers_last.flags == modifiers.flags);
}

fn verify(registry: *KeyRegistry, model: *const ModelType) void {
    assert(registry.is_valid());
    assert(registry.base.count() == model.count);
    assert(registry.is_paused() == model.paused);
    assert(model.count <= capacity);

    var index: u32 = 0;

    while (index < model.count) : (index += 1) {
        assert(index < capacity);

        const binding = model.bindings[index];
        const key = make_key(binding.value, binding.modifiers);
        const entry = registry.find(&key);

        assert(entry != null);
        assert(entry.?.get_id() == binding.id);
        assert(entry.?.is_active());
        assert(entry.?.key == binding.value);
        assert(entry.?.modifiers.flags == binding.modifiers.flags);
        assert(entry.?.block_exempt == binding.block_exempt);
        assert(entry.?.pause_exempt == binding.pause_exempt);
    }

    assert(index == model.count);
}

fn callback(context: *anyopaque, key: *const Key) Response {
    const self: *Context = @ptrCast(@alignCast(context));

    assert(key.is_valid());

    self.invocations += 1;
    self.value_last = key.value;
    self.modifiers_last = key.modifiers;

    return self.response_next;
}

fn make_key(value: Keycode, modifiers: modifier.Set) Key {
    assert(modifiers.flags <= modifier.flag_all);

    const result = Key{
        .value = value,
        .down = true,
        .injected = false,
        .modifiers = modifiers,
    };

    assert(result.is_valid());

    return result;
}

fn random_value(random: std.Random) Keycode {
    return fuzz.random_from_slice(random, Keycode, &keys);
}

fn random_modifiers(random: std.Random) modifier.Set {
    const flags = fuzz.random_from_slice(random, u4, &modifier_sets);

    assert(flags <= modifier.flag_all);

    return modifier.Set{ .flags = flags };
}

fn random_index(random: std.Random, model: *const ModelType) ?u32 {
    assert(model.count <= capacity);

    if (model.count == 0) return null;

    const result = random.uintLessThan(u32, model.count);

    assert(result < model.count);

    return result;
}

const testing = std.testing;

test "fuzz: key registry tracks the reference model" {
    try main(testing.allocator, .{ .seed = 0x2b7e_1516, .events_max = 2048 });
}

test "fuzz: key registry is deterministic per seed" {
    try main(testing.allocator, .{ .seed = 31337, .events_max = 256 });
    try main(testing.allocator, .{ .seed = 31337, .events_max = 256 });
}
