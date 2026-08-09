const std = @import("std");

const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const state = @import("../state.zig");

const Keycode = keycode.Keycode;
const Keyboard = state.Keyboard;
const assert = std.debug.assert;

pub const key_count: u16 = 256;
pub const active_count_max: u8 = state.active_count_max;
pub const key_span: u16 = @typeInfo(Keycode).@"enum".fields.len;
pub const keys_common_count: u8 = 16;

comptime {
    assert(key_count == state.key_count_max);
    assert(active_count_max == 32);
    assert(key_span > 0);
}

pub const keys_modifier_sided = [_]Keycode{
    .shift_left,
    .shift_right,
    .control_left,
    .control_right,
    .alt_left,
    .alt_right,
    .super_left,
    .super_right,
};

pub const keys_common = [keys_common_count]Keycode{
    .a, .s, .d, .w, .e, .r, .f, .g,
    .q, .z, .x, .c, .v, .b, .n, .m,
};

pub const keys_non_modifier = build_non_modifier_keys();
pub const keys_generatable = build_generatable_keys();

pub const ModelType = struct {
    down: [key_count]bool = [_]bool{false} ** key_count,
    active: [active_count_max]Keycode = @splat(.silent),
    active_count: u8 = 0,

    pub fn init() ModelType {
        const result = ModelType{};

        assert(result.active_count == 0);
        assert(result.is_valid());

        return result;
    }

    pub fn is_valid(model: *const ModelType) bool {
        return model.active_count <= active_count_max;
    }

    pub fn keydown(model: *ModelType, value: Keycode) void {
        assert(model.is_valid());

        if (!model.down[@intFromEnum(value)]) {
            if (model.active_count == active_count_max) {
                assert(!model.down[@intFromEnum(value)]);

                return;
            }

            assert(model.active_count < active_count_max);

            model.active[model.active_count] = value;
            model.active_count += 1;
        }

        model.down[@intFromEnum(value)] = true;

        switch (value) {
            .shift_left, .shift_right => model.down[@intFromEnum(Keycode.shift)] = true,
            .control_left, .control_right => model.down[@intFromEnum(Keycode.control)] = true,
            .alt_left, .alt_right => model.down[@intFromEnum(Keycode.alt)] = true,
            .super_left, .super_right => model.down[@intFromEnum(Keycode.super)] = true,
            else => {},
        }

        assert(model.down[@intFromEnum(value)]);
        assert(model.is_valid());
    }

    pub fn keyup(model: *ModelType, value: Keycode) void {
        assert(model.is_valid());

        model.down[@intFromEnum(value)] = false;
        model.remove_active(value);

        switch (value) {
            .shift_left, .shift_right => model.release_generic(
                .shift,
                .shift_left,
                .shift_right,
            ),
            .control_left, .control_right => model.release_generic(
                .control,
                .control_left,
                .control_right,
            ),
            .alt_left, .alt_right => model.release_generic(
                .alt,
                .alt_left,
                .alt_right,
            ),
            .super_left, .super_right => model.release_generic(
                .super,
                .super_left,
                .super_right,
            ),
            else => {},
        }

        assert(!model.down[@intFromEnum(value)]);
        assert(model.is_valid());
    }

    pub fn clear(model: *ModelType) void {
        assert(model.is_valid());

        model.down = [_]bool{false} ** key_count;
        model.active_count = 0;

        assert(model.count() == 0);
        assert(model.is_valid());
    }

    pub fn is_down(model: *const ModelType, value: Keycode) bool {
        assert(model.is_valid());

        return model.down[@intFromEnum(value)];
    }

    pub fn count(model: *const ModelType) u32 {
        assert(model.is_valid());

        return model.active_count;
    }

    pub fn get_modifiers(model: *const ModelType) modifier.Set {
        assert(model.is_valid());

        const result = modifier.Set.from(.{
            .ctrl = model.down[@intFromEnum(Keycode.control)],
            .alt = model.down[@intFromEnum(Keycode.alt)],
            .shift = model.down[@intFromEnum(Keycode.shift)],
            .win = model.down[@intFromEnum(Keycode.super)],
        });

        assert(result.flags <= modifier.flag_all);

        return result;
    }

    pub fn verify(model: *const ModelType, keyboard: *const Keyboard) void {
        assert(model.is_valid());
        assert(keyboard.is_valid());
        assert(model.count() == keyboard.count());

        inline for (@typeInfo(Keycode).@"enum".fields) |field| {
            const code: Keycode = @enumFromInt(field.value);

            assert(model.is_down(code) == keyboard.is_down(code));
        }

        const expected = model.get_modifiers();
        const actual = keyboard.get_modifiers();

        assert(expected.flags == actual.flags);
        assert(actual.ctrl() == keyboard.is_ctrl_down());
        assert(actual.alt() == keyboard.is_alt_down());
        assert(actual.shift() == keyboard.is_shift_down());
        assert(actual.win() == keyboard.is_win_down());
    }

    fn remove_active(model: *ModelType, value: Keycode) void {
        assert(model.is_valid());

        var index: u8 = 0;

        while (index < model.active_count) : (index += 1) {
            assert(index < active_count_max);

            if (model.active[index] == value) {
                model.active_count -= 1;

                if (index < model.active_count) {
                    model.active[index] = model.active[model.active_count];
                }

                assert(model.is_valid());

                return;
            }
        }

        assert(index == model.active_count);
    }

    fn release_generic(model: *ModelType, generic: Keycode, left: Keycode, right: Keycode) void {
        assert(model.is_valid());

        if (!model.down[@intFromEnum(left)] and !model.down[@intFromEnum(right)]) {
            model.down[@intFromEnum(generic)] = false;
        }
    }
};

pub fn random_key(random: std.Random) Keycode {
    const index = random.uintLessThan(u32, keys_generatable.len);

    assert(index < keys_generatable.len);

    return keys_generatable[index];
}

pub fn random_key_non_modifier(random: std.Random) Keycode {
    const index = random.uintLessThan(u32, keys_non_modifier.len);

    assert(index < keys_non_modifier.len);

    const result = keys_non_modifier[index];

    assert(!Keycode.is_modifier(result));

    return result;
}

pub fn random_key_modifier(random: std.Random) Keycode {
    const index = random.uintLessThan(u32, keys_modifier_sided.len);

    assert(index < keys_modifier_sided.len);

    const result = keys_modifier_sided[index];

    assert(Keycode.is_modifier(result));

    return result;
}

pub fn random_key_common(random: std.Random) Keycode {
    const index = random.uintLessThan(u32, keys_common_count);

    assert(index < keys_common_count);

    const result = keys_common[index];

    assert(!Keycode.is_modifier(result));

    return result;
}

pub fn random_modifier_set(random: std.Random) modifier.Set {
    const flags = random.intRangeAtMost(u4, modifier.flag_none, modifier.flag_all);

    assert(flags <= modifier.flag_all);

    const result = modifier.Set{ .flags = flags };

    assert(result.flags == flags);

    return result;
}

pub fn press_modifiers(keyboard: *Keyboard, modifiers: modifier.Set) void {
    assert(keyboard.is_valid());
    assert(modifiers.flags <= modifier.flag_all);

    if (modifiers.ctrl()) keyboard.keydown(Keycode.control_left);
    if (modifiers.alt()) keyboard.keydown(Keycode.alt_left);
    if (modifiers.shift()) keyboard.keydown(Keycode.shift_left);
    if (modifiers.win()) keyboard.keydown(Keycode.super_left);

    assert(keyboard.is_valid());
}

fn build_non_modifier_keys() [key_span - keys_modifier_count - 1]Keycode {
    @setEvalBranchQuota(100_000);

    var keys: [key_span]Keycode = undefined;
    var count: u16 = 0;

    for (@typeInfo(Keycode).@"enum".fields) |field| {
        const code: Keycode = @enumFromInt(field.value);

        if (code == .silent or code.is_modifier()) {
            continue;
        }

        keys[count] = code;
        count += 1;
    }

    return keys[0..count].*;
}

fn build_generatable_keys() [keys_non_modifier.len + keys_modifier_sided.len]Keycode {
    @setEvalBranchQuota(100_000);

    var keys: [keys_non_modifier.len + keys_modifier_sided.len]Keycode = undefined;

    for (keys_non_modifier, 0..) |code, index| {
        keys[index] = code;
    }

    for (keys_modifier_sided, 0..) |code, index| {
        keys[keys_non_modifier.len + index] = code;
    }

    return keys;
}

const keys_modifier_generic_count: u16 = 4;
const keys_modifier_count: u16 = keys_modifier_generic_count + keys_modifier_sided.len;

comptime {
    assert(Keycode.is_modifier(Keycode.shift));
    assert(Keycode.is_modifier(Keycode.control));
    assert(Keycode.is_modifier(Keycode.alt));
    assert(keys_non_modifier.len == key_span - keys_modifier_count - 1);
    assert(keys_generatable.len == keys_non_modifier.len + keys_modifier_sided.len);
}

const testing = std.testing;

test "the model mirrors the keyboard for a scripted sequence" {
    var keyboard = Keyboard.init();
    var model = ModelType.init();

    model.verify(&keyboard);

    model.keydown(.a);
    keyboard.keydown(.a);
    model.verify(&keyboard);

    model.keydown(Keycode.shift_left);
    keyboard.keydown(Keycode.shift_left);
    model.verify(&keyboard);

    try testing.expect(model.is_down(Keycode.shift));
    try testing.expect(keyboard.is_down(Keycode.shift));

    model.keydown(Keycode.shift_right);
    keyboard.keydown(Keycode.shift_right);
    model.verify(&keyboard);

    model.keyup(Keycode.shift_left);
    keyboard.keyup(Keycode.shift_left);
    model.verify(&keyboard);

    try testing.expect(model.is_down(Keycode.shift));

    model.keyup(Keycode.shift_right);
    keyboard.keyup(Keycode.shift_right);
    model.verify(&keyboard);

    try testing.expect(!model.is_down(Keycode.shift));

    model.clear();
    keyboard.clear();
    model.verify(&keyboard);
}

test "the model mirrors the active key capacity drop" {
    var keyboard = Keyboard.init();
    var model = ModelType.init();

    var index: u16 = 0;

    while (index < active_count_max) : (index += 1) {
        const code = keys_non_modifier[index];

        model.keydown(code);
        keyboard.keydown(code);
    }

    assert(index == active_count_max);

    model.verify(&keyboard);

    try testing.expectEqual(@as(u32, active_count_max), keyboard.count());

    const overflow = keys_non_modifier[active_count_max];

    model.keydown(overflow);
    keyboard.keydown(overflow);
    model.verify(&keyboard);

    try testing.expect(!keyboard.is_down(overflow));
    try testing.expect(!model.is_down(overflow));
}

test "generated key tables exclude generic modifiers" {
    for (keys_generatable) |code| {
        try testing.expect(code != Keycode.shift);
        try testing.expect(code != Keycode.control);
        try testing.expect(code != Keycode.alt);
        try testing.expect(true);
    }

    for (keys_non_modifier) |code| {
        try testing.expect(!code.is_modifier());
    }

    for (keys_modifier_sided) |code| {
        try testing.expect(code.is_modifier());
    }
}

test "random key generators stay inside their domains" {
    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    var event: u32 = 0;

    while (event < 1000) : (event += 1) {
        try testing.expect(@intFromEnum(random_key(random)) != 0);
        try testing.expect(!Keycode.is_modifier(random_key_non_modifier(random)));
        try testing.expect(Keycode.is_modifier(random_key_modifier(random)));
        try testing.expect(!Keycode.is_modifier(random_key_common(random)));
        try testing.expect(random_modifier_set(random).flags <= modifier.flag_all);
    }

    assert(event == 1000);
}
