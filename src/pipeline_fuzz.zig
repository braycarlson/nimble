const std = @import("std");

const fuzz = @import("testing/fuzz.zig");
const key_event = @import("event/key.zig");
const keycode = @import("keycode.zig");
const modifier = @import("modifier.zig");
const response_module = @import("response.zig");
const root = @import("root.zig");

const Allocator = std.mem.Allocator;
const Key = key_event.Key;
const Keycode = keycode.Keycode;
const Response = response_module.Response;
const assert = std.debug.assert;

const Runtime = root.RuntimeType(root.Fake);
const Keyboard = Runtime.KeyboardType(.{ .binding_count_max = 4 });

const Operation = enum {
    press_bound,
    release_bound,
    press_random,
    release_random,
    press_modifier,
    release_modifier,
    advance_time,
    toggle_block,
};

const keys_bound = [_]Keycode{ .a, .b, .c };

const keys_modifier = [_]Keycode{
    .control_left,
    .control_right,
    .shift_left,
    .shift_right,
    .alt_left,
    .alt_right,
};

const advance_ms_max: u32 = 64;

const Harness = struct {
    hits: u32 = 0,

    fn on_key(harness: *Harness, _: *const Key) Response {
        harness.hits += 1;

        return .consume;
    }
};

comptime {
    assert(keys_bound.len > 0);
    assert(keys_modifier.len > 0);
    assert(advance_ms_max > 0);
}

pub fn main(gpa: Allocator, args: fuzz.Arguments) !void {
    _ = try run(gpa, args);
}

fn run(gpa: Allocator, args: fuzz.Arguments) !u16 {
    assert(args.events_max >= 1);

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();
    const weights = fuzz.random_enum_weights(random, Operation);

    const runtime = try gpa.create(Runtime);
    defer gpa.destroy(runtime);

    try runtime.init(.{ .mode = .grab });
    defer runtime.deinit();

    const hook = try gpa.create(Keyboard);
    defer gpa.destroy(hook);

    try hook.init(runtime, .{});
    defer hook.deinit();

    var harness = Harness{};

    _ = try hook.bind("Ctrl+A").on(Harness, &harness, Harness.on_key);
    _ = try hook.bind("Ctrl+Shift+B").on(Harness, &harness, Harness.on_key);

    try hook.start();
    defer hook.stop();

    var event: u32 = 0;

    while (event < args.events_max) : (event += 1) {
        const operation = fuzz.random_enum_weighted(random, Operation, weights);

        apply(random, runtime, hook, operation);

        runtime.run();

        check_invariants(runtime, hook);
    }

    assert(event == args.events_max);

    check_invariants(runtime, hook);

    return runtime.platform.record.len();
}

fn apply(random: std.Random, runtime: *Runtime, hook: *Keyboard, operation: Operation) void {
    const queue = &runtime.platform.loop;

    switch (operation) {
        .press_bound => queue.push_key(make(pick(random, &keys_bound), true)),
        .release_bound => queue.push_key(make(pick(random, &keys_bound), false)),
        .press_random => queue.push_key(make(random_code(random), true)),
        .release_random => queue.push_key(make(random_code(random), false)),
        .press_modifier => queue.push_key(make(pick(random, &keys_modifier), true)),
        .release_modifier => queue.push_key(make(pick(random, &keys_modifier), false)),
        .advance_time => queue.push_advance(random.uintAtMost(u32, advance_ms_max)),
        .toggle_block => if (hook.is_blocked()) hook.unblock() else hook.block(),
    }
}

fn check_invariants(runtime: *const Runtime, hook: *Keyboard) void {
    const modifiers = hook.get_modifiers();
    const queue = &runtime.platform.loop;

    assert(modifiers.count() <= modifier.Set.kind_count);
    assert(hook.is_running());

    var index: u16 = 0;

    while (index < queue.response_len()) : (index += 1) {
        assert(queue.response_at(index).is_valid());
    }

    assert(!runtime.platform.record.is_overflowed());
}

fn pick(random: std.Random, codes: []const Keycode) Keycode {
    assert(codes.len > 0);

    const index = random.uintLessThan(usize, codes.len);

    assert(index < codes.len);

    return codes[index];
}

fn random_code(random: std.Random) Keycode {
    return pick(random, std.enums.values(Keycode));
}

fn make(code: Keycode, down: bool) Key {
    return Key{ .value = code, .down = down, .injected = false };
}

const testing = std.testing;

test "the hook pipeline survives a scripted queue" {
    try main(testing.allocator, .{ .seed = 789, .events_max = 512 });
}

test "the pipeline is deterministic for a fixed seed" {
    const first = try run(testing.allocator, .{ .seed = 4242, .events_max = 256 });
    const second = try run(testing.allocator, .{ .seed = 4242, .events_max = 256 });

    try testing.expectEqual(first, second);
}
