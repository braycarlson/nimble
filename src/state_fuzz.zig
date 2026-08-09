const std = @import("std");

const fuzz = @import("testing/fuzz.zig");
const keyboard_testing = @import("testing/keyboard.zig");
const keycode = @import("keycode.zig");
const state = @import("state.zig");

const Keycode = keycode.Keycode;
const Allocator = std.mem.Allocator;
const Keyboard = state.Keyboard;
const ModelType = keyboard_testing.ModelType;
const assert = std.debug.assert;

const Operation = enum {
    keydown,
    keydown_common,
    keydown_modifier,
    keyup,
    keyup_common,
    keyup_modifier,
    keyup_held,
    clear,
};

pub fn main(gpa: Allocator, args: fuzz.FuzzArgs) !void {
    _ = gpa;

    assert(args.events_max >= 1);

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();
    const weights = fuzz.random_enum_weights(random, Operation);

    var keyboard = Keyboard.init();
    var model = ModelType.init();

    model.verify(&keyboard);
    check_invariants(&keyboard);

    var event: u32 = 0;

    while (event < args.events_max) : (event += 1) {
        const operation = fuzz.random_enum_weighted(random, Operation, weights);

        apply(random, &keyboard, &model, operation);

        model.verify(&keyboard);
        check_invariants(&keyboard);
    }

    assert(event == args.events_max);
}

fn apply(random: std.Random, keyboard: *Keyboard, model: *ModelType, operation: Operation) void {
    assert(keyboard.is_valid());
    assert(model.is_valid());

    switch (operation) {
        .keydown => press(keyboard, model, keyboard_testing.random_key(random)),
        .keydown_common => press(keyboard, model, keyboard_testing.random_key_common(random)),
        .keydown_modifier => press(keyboard, model, keyboard_testing.random_key_modifier(random)),
        .keyup => release(keyboard, model, keyboard_testing.random_key(random)),
        .keyup_common => release(keyboard, model, keyboard_testing.random_key_common(random)),
        .keyup_modifier => release(keyboard, model, keyboard_testing.random_key_modifier(random)),
        .keyup_held => {
            const held = random_held_key(random, model) orelse return;

            release(keyboard, model, held);
        },
        .clear => {
            keyboard.clear();
            model.clear();

            assert(keyboard.count() == 0);
            assert(model.count() == 0);
        },
    }
}

fn press(keyboard: *Keyboard, model: *ModelType, value: Keycode) void {
    const saturated = model.count() == keyboard_testing.active_count_max and !model.is_down(value);

    keyboard.keydown(value);
    model.keydown(value);

    assert(model.is_down(value) == !saturated);
}

fn release(keyboard: *Keyboard, model: *ModelType, value: Keycode) void {
    keyboard.keyup(value);
    model.keyup(value);

    assert(!keyboard.is_down(value));
    assert(!model.is_down(value));
}

fn random_held_key(random: std.Random, model: *const ModelType) ?Keycode {
    assert(model.is_valid());

    if (model.active_count == 0) return null;

    const index = random.uintLessThan(u8, model.active_count);

    assert(index < model.active_count);

    return model.active[index];
}

fn check_invariants(keyboard: *const Keyboard) void {
    assert(keyboard.is_valid());
    assert(keyboard.count() <= keyboard_testing.active_count_max);

    check_generic_modifier(keyboard, .shift, .shift_left, .shift_right);
    check_generic_modifier(keyboard, .control, .control_left, .control_right);
    check_generic_modifier(keyboard, .alt, .alt_left, .alt_right);
    check_generic_modifier(keyboard, .super, .super_left, .super_right);

    const modifiers = keyboard.get_modifiers();

    assert(modifiers.ctrl() == keyboard.is_down(.control));
    assert(modifiers.alt() == keyboard.is_down(.alt));
    assert(modifiers.shift() == keyboard.is_down(.shift));

    const win_left = keyboard.is_down(.super_left);
    const win_right = keyboard.is_down(.super_right);

    assert(modifiers.win() == (win_left or win_right));
    assert(keyboard.is_win_down() == (win_left or win_right));
    assert(keyboard.is_ctrl_down() == modifiers.ctrl());
    assert(keyboard.is_alt_down() == modifiers.alt());
    assert(keyboard.is_shift_down() == modifiers.shift());
}

fn check_generic_modifier(
    keyboard: *const Keyboard,
    generic: Keycode,
    left: Keycode,
    right: Keycode,
) void {
    const sided_down = keyboard.is_down(left) or keyboard.is_down(right);

    if (sided_down) assert(keyboard.is_down(generic));
}

test "fuzz: keyboard state tracks the reference model" {
    try main(std.testing.allocator, .{ .seed = 0x5f3d_1c07, .events_max = 512 });
}

test "fuzz: keyboard state is deterministic per seed" {
    try main(std.testing.allocator, .{ .seed = 12345, .events_max = 128 });
    try main(std.testing.allocator, .{ .seed = 12345, .events_max = 128 });
}
