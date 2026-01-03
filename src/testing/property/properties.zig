const std = @import("std");

const exhaustigen = @import("exhaustigen.zig");

const input = @import("input");
const keycode = input.keycode;
const modifier = input.modifier;
const binding_mod = input.binding;
const state = input.state;
const response_mod = input.response;

const Binding = binding_mod.Binding;
const Keyboard = state.Keyboard;
const Response = response_mod.Response;
const Gen = exhaustigen.Gen;

pub const iteration_max: u32 = 0xFFFFFFFF;
pub const key_range: u8 = 16;
pub const key_range_small: u8 = 8;
pub const modifier_flag_max: u4 = 0x0F;

pub fn property_keyboard_keydown_is_down() !void {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const key = g.range_inclusive(u8, keycode.value_min, keycode.value_min + key_range - 1);

        std.debug.assert(keycode.is_valid(key));
        std.debug.assert(key >= keycode.value_min);
        std.debug.assert(key < keycode.value_min + key_range);

        var keyboard = Keyboard.init();

        std.debug.assert(keyboard.count() == 0);
        std.debug.assert(!keyboard.is_down(key));

        keyboard.keydown(key);

        std.debug.assert(keyboard.is_down(key));
        std.debug.assert(keyboard.count() >= 1);

        iteration += 1;
    }

    std.debug.assert(iteration > 0);
    std.debug.assert(iteration <= key_range);
}

pub fn property_keyboard_keyup_not_down() !void {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const key = g.range_inclusive(u8, keycode.value_min, keycode.value_min + key_range - 1);

        std.debug.assert(keycode.is_valid(key));

        var keyboard = Keyboard.init();

        std.debug.assert(keyboard.count() == 0);

        keyboard.keydown(key);

        std.debug.assert(keyboard.is_down(key));

        keyboard.keyup(key);

        std.debug.assert(!keyboard.is_down(key));

        iteration += 1;
    }

    std.debug.assert(iteration > 0);
    std.debug.assert(iteration <= key_range);
}

pub fn property_keyboard_clear_empty() !void {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const key1 = g.range_inclusive(u8, keycode.value_min, keycode.value_min + key_range_small - 1);
        const key2 = g.range_inclusive(u8, keycode.value_min, keycode.value_min + key_range_small - 1);

        std.debug.assert(keycode.is_valid(key1));
        std.debug.assert(keycode.is_valid(key2));

        var keyboard = Keyboard.init();

        std.debug.assert(keyboard.count() == 0);

        keyboard.keydown(key1);
        keyboard.keydown(key2);

        std.debug.assert(keyboard.count() >= 1);
        std.debug.assert(keyboard.is_down(key1));
        std.debug.assert(keyboard.is_down(key2));

        keyboard.clear();

        std.debug.assert(keyboard.count() == 0);
        std.debug.assert(!keyboard.is_down(key1));
        std.debug.assert(!keyboard.is_down(key2));

        iteration += 1;
    }

    std.debug.assert(iteration > 0);
}

pub fn property_modifier_set_flags() !void {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const flags = g.range_inclusive(u4, 0, modifier_flag_max);

        std.debug.assert(flags <= modifier_flag_max);

        const mods = modifier.Set{ .flags = flags };

        std.debug.assert(mods.flags == flags);

        verify_modifier_consistency(&mods, flags);

        iteration += 1;
    }

    std.debug.assert(iteration > 0);
    std.debug.assert(iteration <= @as(u32, modifier_flag_max) + 1);
}

fn verify_modifier_consistency(mods: *const modifier.Set, flags: u4) void {
    std.debug.assert(@intFromPtr(mods) != 0);
    std.debug.assert(flags <= modifier_flag_max);

    const has_ctrl = (flags & modifier.flag_ctrl) != 0;
    const has_alt = (flags & modifier.flag_alt) != 0;
    const has_shift = (flags & modifier.flag_shift) != 0;
    const has_win = (flags & modifier.flag_win) != 0;

    std.debug.assert(mods.ctrl() == has_ctrl);
    std.debug.assert(mods.alt() == has_alt);
    std.debug.assert(mods.shift() == has_shift);
    std.debug.assert(mods.win() == has_win);
}

pub fn property_modifier_set_total() !void {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const flags = g.range_inclusive(u4, 0, modifier_flag_max);

        std.debug.assert(flags <= modifier_flag_max);

        const mods = modifier.Set{ .flags = flags };
        const expected = compute_expected_count(flags);
        const actual = mods.count();

        std.debug.assert(expected == actual);
        std.debug.assert(actual <= 4);

        iteration += 1;
    }

    std.debug.assert(iteration > 0);
}

fn compute_expected_count(flags: u4) u8 {
    std.debug.assert(flags <= modifier_flag_max);

    var expected: u8 = 0;

    if ((flags & modifier.flag_ctrl) != 0) {
        expected += 1;
    }

    if ((flags & modifier.flag_alt) != 0) {
        expected += 1;
    }

    if ((flags & modifier.flag_shift) != 0) {
        expected += 1;
    }

    if ((flags & modifier.flag_win) != 0) {
        expected += 1;
    }

    std.debug.assert(expected <= 4);

    return expected;
}

pub fn property_modifier_set_equality() !void {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const flags1 = g.range_inclusive(u4, 0, modifier_flag_max);
        const flags2 = g.range_inclusive(u4, 0, modifier_flag_max);

        std.debug.assert(flags1 <= modifier_flag_max);
        std.debug.assert(flags2 <= modifier_flag_max);

        const mods1 = modifier.Set{ .flags = flags1 };
        const mods2 = modifier.Set{ .flags = flags2 };
        const are_equal = mods1.equals(&mods2);
        const flags_equal = flags1 == flags2;

        std.debug.assert(are_equal == flags_equal);

        iteration += 1;
    }

    std.debug.assert(iteration > 0);
}

pub fn property_binding_match_self() !void {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const key = g.range_inclusive(u8, keycode.value_min, keycode.value_min + key_range_small - 1);
        const flags = g.range_inclusive(u4, 0, modifier_flag_max);

        std.debug.assert(keycode.is_valid(key));
        std.debug.assert(flags <= modifier_flag_max);

        if (keycode.is_modifier(key)) {
            iteration += 1;
            continue;
        }

        const mods = modifier.Set{ .flags = flags };
        const binding = Binding.init(key, mods);

        std.debug.assert(binding.is_valid());

        var keyboard = Keyboard.init();

        std.debug.assert(keyboard.count() == 0);

        setup_keyboard_for_binding(&keyboard, key, &mods);

        std.debug.assert(keyboard.is_down(key));
        std.debug.assert(binding.match(&keyboard));

        iteration += 1;
    }

    std.debug.assert(iteration > 0);
}

fn setup_keyboard_for_binding(
    keyboard: *Keyboard,
    key: u8,
    mods: *const modifier.Set,
) void {
    std.debug.assert(@intFromPtr(keyboard) != 0);
    std.debug.assert(keycode.is_valid(key));
    std.debug.assert(mods.flags <= modifier_flag_max);

    keyboard.keydown(key);

    if (mods.ctrl()) {
        keyboard.keydown(keycode.lctrl);
    }

    if (mods.alt()) {
        keyboard.keydown(keycode.lmenu);
    }

    if (mods.shift()) {
        keyboard.keydown(keycode.lshift);
    }

    if (mods.win()) {
        keyboard.keydown(keycode.lwin);
    }

    std.debug.assert(keyboard.is_down(key));
}

pub fn property_binding_id_unique() !void {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const key1 = g.range_inclusive(u8, keycode.value_min, keycode.value_min + key_range_small - 1);
        const key2 = g.range_inclusive(u8, keycode.value_min, keycode.value_min + key_range_small - 1);

        std.debug.assert(keycode.is_valid(key1));
        std.debug.assert(keycode.is_valid(key2));

        if (keycode.is_modifier(key1) or keycode.is_modifier(key2)) {
            iteration += 1;
            continue;
        }

        const mods1 = modifier.Set{ .flags = 0 };
        const mods2 = modifier.Set{ .flags = modifier.flag_ctrl };

        const binding1 = Binding.init(key1, mods1);
        const binding2 = Binding.init(key2, mods2);

        std.debug.assert(binding1.is_valid());
        std.debug.assert(binding2.is_valid());

        const same_key = key1 == key2;
        const same_mods = mods1.equals(&mods2);

        if (!same_key or !same_mods) {
            std.debug.assert(!binding1.equals(&binding2));
        }

        iteration += 1;
    }

    std.debug.assert(iteration > 0);
}

pub fn property_response_validity() !void {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const value = g.range_inclusive(u8, 0, 2);

        std.debug.assert(value <= 2);

        const response: Response = @enumFromInt(value);

        std.debug.assert(response.is_valid());
        std.debug.assert(@intFromEnum(response) == value);

        iteration += 1;
    }

    std.debug.assert(iteration > 0);
    std.debug.assert(iteration == 3);
}

pub fn property_keyboard_modifier_tracking() !void {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const use_left = g.boolean();
        const mod_key = select_shift_modifier(use_left);

        std.debug.assert(keycode.is_modifier(mod_key));

        var keyboard = Keyboard.init();

        std.debug.assert(keyboard.count() == 0);
        std.debug.assert(!keyboard.is_down(mod_key));

        keyboard.keydown(mod_key);

        std.debug.assert(keyboard.is_down(mod_key));
        std.debug.assert(keyboard.is_down(keycode.shift));

        keyboard.keyup(mod_key);

        std.debug.assert(!keyboard.is_down(mod_key));

        iteration += 1;
    }

    std.debug.assert(iteration > 0);
}

fn select_shift_modifier(use_left: bool) u8 {
    const result = if (use_left) keycode.lshift else keycode.rshift;

    std.debug.assert(keycode.is_modifier(result));

    return result;
}

pub fn property_keyboard_modifier_tracking_ctrl() !void {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const use_left = g.boolean();
        const mod_key = select_ctrl_modifier(use_left);

        std.debug.assert(keycode.is_modifier(mod_key));

        var keyboard = Keyboard.init();

        std.debug.assert(keyboard.count() == 0);

        keyboard.keydown(mod_key);

        std.debug.assert(keyboard.is_down(mod_key));
        std.debug.assert(keyboard.is_down(keycode.control));

        keyboard.keyup(mod_key);

        std.debug.assert(!keyboard.is_down(mod_key));

        iteration += 1;
    }

    std.debug.assert(iteration > 0);
}

fn select_ctrl_modifier(use_left: bool) u8 {
    const result = if (use_left) keycode.lctrl else keycode.rctrl;

    std.debug.assert(keycode.is_modifier(result));

    return result;
}

pub fn property_keyboard_modifier_tracking_alt() !void {
    var g = Gen.init();
    var iteration: u32 = 0;

    std.debug.assert(g.is_valid());

    while (!g.done()) {
        std.debug.assert(iteration < iteration_max);
        std.debug.assert(g.is_valid());

        const use_left = g.boolean();
        const mod_key = select_alt_modifier(use_left);

        std.debug.assert(keycode.is_modifier(mod_key));

        var keyboard = Keyboard.init();

        std.debug.assert(keyboard.count() == 0);

        keyboard.keydown(mod_key);

        std.debug.assert(keyboard.is_down(mod_key));
        std.debug.assert(keyboard.is_down(keycode.menu));

        keyboard.keyup(mod_key);

        std.debug.assert(!keyboard.is_down(mod_key));

        iteration += 1;
    }

    std.debug.assert(iteration > 0);
}

fn select_alt_modifier(use_left: bool) u8 {
    const result = if (use_left) keycode.lmenu else keycode.rmenu;

    std.debug.assert(keycode.is_modifier(result));

    return result;
}

const testing = std.testing;

test "property: keyboard keydown is down" {
    try property_keyboard_keydown_is_down();
}

test "property: keyboard keyup not down" {
    try property_keyboard_keyup_not_down();
}

test "property: keyboard clear empty" {
    try property_keyboard_clear_empty();
}

test "property: modifier set flags" {
    try property_modifier_set_flags();
}

test "property: modifier set total" {
    try property_modifier_set_total();
}

test "property: modifier set equality" {
    try property_modifier_set_equality();
}

test "property: binding match self" {
    try property_binding_match_self();
}

test "property: binding id unique" {
    try property_binding_id_unique();
}

test "property: response validity" {
    try property_response_validity();
}

test "property: keyboard modifier tracking shift" {
    try property_keyboard_modifier_tracking();
}

test "property: keyboard modifier tracking ctrl" {
    try property_keyboard_modifier_tracking_ctrl();
}

test "property: keyboard modifier tracking alt" {
    try property_keyboard_modifier_tracking_alt();
}
