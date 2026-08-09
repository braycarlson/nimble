const std = @import("std");

const fuzz = @import("testing/fuzz.zig");
const keycode = @import("keycode.zig");
const key_event = @import("event/key.zig");
const modifier = @import("modifier.zig");
const platform = @import("platform.zig");
const response_mod = @import("response.zig");
const root = @import("root.zig");

const Allocator = std.mem.Allocator;
const Key = key_event.Key;
const Keycode = keycode.Keycode;
const Response = response_mod.Response;
const assert = std.debug.assert;
const backend = platform.backend;

const Keyboard = root.KeyboardType(.{});

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

pub fn main(gpa: Allocator, args: fuzz.FuzzArgs) !void {
    _ = gpa;

    assert(args.events_max >= 1);

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();
    const weights = fuzz.random_enum_weights(random, Operation);

    backend.reset();

    try backend.runtime.open(.{ .mode = .grab });
    defer backend.runtime.close();

    var hook = Keyboard.init();
    defer hook.deinit();

    var harness = Harness{};

    _ = try hook.bind("Ctrl+A").on(&harness, Harness.on_key);
    _ = try hook.bind("Ctrl+Shift+B").on(&harness, Harness.on_key);

    try hook.start();
    defer hook.stop();

    var event: u32 = 0;

    while (event < args.events_max) : (event += 1) {
        const operation = fuzz.random_enum_weighted(random, Operation, weights);

        apply(random, &hook, operation);

        backend.loop.run();

        check_invariants(&hook);
    }

    assert(event == args.events_max);

    check_invariants(&hook);
}

fn apply(random: std.Random, hook: *Keyboard, operation: Operation) void {
    switch (operation) {
        .press_bound => backend.loop.push_key(make(pick(random, &keys_bound), true)),
        .release_bound => backend.loop.push_key(make(pick(random, &keys_bound), false)),
        .press_random => backend.loop.push_key(make(random_code(random), true)),
        .release_random => backend.loop.push_key(make(random_code(random), false)),
        .press_modifier => backend.loop.push_key(make(pick(random, &keys_modifier), true)),
        .release_modifier => backend.loop.push_key(make(pick(random, &keys_modifier), false)),
        .advance_time => backend.loop.push_advance(random.uintAtMost(u32, advance_ms_max)),
        .toggle_block => hook.set_blocked(!hook.is_blocked()),
    }
}

fn check_invariants(hook: *Keyboard) void {
    const modifiers = hook.get_modifiers();

    assert(modifiers.flags <= modifier.flag_all);
    assert(modifiers.count() <= modifier.kind_count);
    assert(hook.is_running());

    var index: u16 = 0;

    while (index < backend.loop.response_len()) : (index += 1) {
        assert(backend.loop.response_at(index).is_valid());
    }

    assert(!backend.record.is_overflowed());
}

fn pick(random: std.Random, codes: []const Keycode) Keycode {
    assert(codes.len > 0);

    const index = random.uintLessThan(usize, codes.len);

    assert(index < codes.len);

    return codes[index];
}

fn random_code(random: std.Random) Keycode {
    const fields = @typeInfo(Keycode).@"enum".fields;
    const index = random.uintLessThan(u16, fields.len);

    inline for (fields, 0..) |field, position| {
        if (position == index) {
            return @enumFromInt(field.value);
        }
    }

    unreachable;
}

fn make(code: Keycode, down: bool) Key {
    return Key{
        .value = code,
        .down = down,
        .injected = false,
    };
}

const testing = std.testing;

test "fuzz: the hook pipeline survives a scripted tape" {
    try main(testing.allocator, .{ .seed = 789, .events_max = 512 });
}

test "fuzz: the pipeline is deterministic for a fixed seed" {
    try main(testing.allocator, .{ .seed = 4242, .events_max = 256 });

    const first = backend.record.len();

    try main(testing.allocator, .{ .seed = 4242, .events_max = 256 });

    try testing.expectEqual(first, backend.record.len());
}
