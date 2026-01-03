const std = @import("std");

const input = @import("input");
const keycode = input.keycode;
const modifier = input.modifier;
const registry = input.registry;
const response = input.response;
const event = input.event;

const Response = response.Response;
const Key = event.key.Key;

const common = @import("common.zig");
const input_fuzz = @import("input.zig");

pub const registered_capacity: u32 = 64;
pub const iteration_max: u32 = 0xFFFFFFFF;
pub const registry_capacity: u32 = 1024;
pub const modifier_limit: u8 = 2;
pub const binding_modifier_limit: u8 = 3;
pub const operation_register_threshold: u8 = 40;
pub const operation_unregister_threshold: u8 = 60;
pub const operation_process_threshold: u8 = 80;
pub const operation_pause_threshold: u8 = 90;

pub const KeyRegistry = registry.key.KeyRegistry(registry_capacity);

pub const RegistryState = struct {
    ids: [registered_capacity]u32 = [_]u32{0} ** registered_capacity,
    count: u32 = 0,

    pub fn init() RegistryState {
        const result = RegistryState{};

        std.debug.assert(result.count == 0);
        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn is_valid(self: *const RegistryState) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_count = self.count <= registered_capacity;
        const result = valid_count;

        return result;
    }

    pub fn add(self: *RegistryState, id: u32) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(id >= 1);

        if (self.count >= registered_capacity) {
            std.debug.assert(self.count == registered_capacity);

            return;
        }

        std.debug.assert(self.count < registered_capacity);

        self.ids[self.count] = id;
        self.count += 1;

        std.debug.assert(self.count <= registered_capacity);
        std.debug.assert(self.is_valid());
    }

    pub fn remove_at(self: *RegistryState, idx: u32) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(idx < self.count);
        std.debug.assert(self.count > 0);

        self.ids[idx] = self.ids[self.count - 1];
        self.count -= 1;

        std.debug.assert(self.count < registered_capacity);
        std.debug.assert(self.is_valid());
    }

    pub fn clear(self: *RegistryState) void {
        std.debug.assert(self.is_valid());

        self.count = 0;

        std.debug.assert(self.count == 0);
        std.debug.assert(self.is_valid());
    }

    pub fn get_random_index(self: *const RegistryState, random: *std.Random) ?u32 {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(random) != 0);

        if (self.count == 0) {
            return null;
        }

        std.debug.assert(self.count > 0);

        const idx = random.intRangeLessThan(u32, 0, self.count);

        std.debug.assert(idx < self.count);

        return idx;
    }
};

fn test_callback(_: *anyopaque, _: *const Key) Response {
    return .pass;
}

pub fn fuzz_key_registry(seed: u64, iterations: u32) !void {
    std.debug.assert(iterations > 0);
    std.debug.assert(iterations <= iteration_max);

    var prng = std.Random.DefaultPrng.init(seed);
    var random = prng.random();
    var reg = KeyRegistry.init();
    var state = RegistryState.init();

    std.debug.assert(reg.base.slot.count == 0);
    std.debug.assert(state.is_valid());

    var iteration: u32 = 0;

    while (iteration < iterations) : (iteration += 1) {
        std.debug.assert(iteration < iterations);
        std.debug.assert(state.is_valid());

        const operation = random.intRangeLessThan(u8, 0, 100);

        std.debug.assert(operation < 100);

        execute_registry_operation(&reg, &random, &state, operation);
    }

    std.debug.assert(iteration == iterations);
}

fn execute_registry_operation(
    reg: *KeyRegistry,
    random: *std.Random,
    state: *RegistryState,
    operation: u8,
) void {
    std.debug.assert(@intFromPtr(reg) != 0);
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(state.is_valid());
    std.debug.assert(operation < 100);

    if (operation < operation_register_threshold) {
        try_register_binding(reg, random, state);
    } else if (operation < operation_unregister_threshold) {
        try_unregister_binding(reg, random, state);
    } else if (operation < operation_process_threshold) {
        process_random_key(reg, random);
    } else if (operation < operation_pause_threshold) {
        toggle_pause(reg, random);
    } else {
        clear_registry(reg, state);
    }
}

fn try_register_binding(
    reg: *KeyRegistry,
    random: *std.Random,
    state: *RegistryState,
) void {
    std.debug.assert(@intFromPtr(reg) != 0);
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(state.is_valid());

    const key_keycode = input_fuzz.random_non_modifier_key_keycode(random);
    const mods = common.random_modifier_set_limited(random, modifier_limit);

    std.debug.assert(!keycode.is_modifier(key_keycode));
    std.debug.assert(mods.count() <= modifier_limit);

    const id = reg.register(
        key_keycode,
        mods,
        &test_callback,
        null,
        .{},
    ) catch {
        return;
    };

    std.debug.assert(id >= 1);

    state.add(id);

    std.debug.assert(state.is_valid());
}

fn try_unregister_binding(
    reg: *KeyRegistry,
    random: *std.Random,
    state: *RegistryState,
) void {
    std.debug.assert(@intFromPtr(reg) != 0);
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(state.is_valid());

    const idx = state.get_random_index(random) orelse return;

    std.debug.assert(idx < state.count);

    const id = state.ids[idx];

    std.debug.assert(id >= 1);

    reg.unregister(id) catch {};

    state.remove_at(idx);

    std.debug.assert(state.is_valid());
}

fn process_random_key(reg: *KeyRegistry, random: *std.Random) void {
    std.debug.assert(@intFromPtr(reg) != 0);
    std.debug.assert(@intFromPtr(random) != 0);

    const key_keycode = input_fuzz.random_non_modifier_key_keycode(random);
    const mods = common.random_modifier_set(random);

    std.debug.assert(!keycode.is_modifier(key_keycode));
    std.debug.assert(mods.flags <= modifier.flag_all);

    const key_event = Key{
        .value = key_keycode,
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = mods,
    };

    std.debug.assert(key_event.is_valid());

    _ = reg.process(&key_event);
}

fn toggle_pause(reg: *KeyRegistry, random: *std.Random) void {
    std.debug.assert(@intFromPtr(reg) != 0);
    std.debug.assert(@intFromPtr(random) != 0);

    const paused = common.random_bool(random);

    reg.set_paused(paused);
}

fn clear_registry(reg: *KeyRegistry, state: *RegistryState) void {
    std.debug.assert(@intFromPtr(reg) != 0);
    std.debug.assert(state.is_valid());

    reg.clear();
    state.clear();

    std.debug.assert(state.count == 0);
    std.debug.assert(state.is_valid());
}

pub fn fuzz_binding_matching(seed: u64, iterations: u32) !void {
    std.debug.assert(iterations > 0);
    std.debug.assert(iterations <= iteration_max);

    var prng = std.Random.DefaultPrng.init(seed);
    var random = prng.random();

    const Binding = input.binding.Binding;
    const Keyboard = input.state.Keyboard;

    var iteration: u32 = 0;

    while (iteration < iterations) : (iteration += 1) {
        std.debug.assert(iteration < iterations);

        const key_keycode = input_fuzz.random_non_modifier_key_keycode(&random);
        const mods = common.random_modifier_set_limited(&random, binding_modifier_limit);
        const binding = Binding.init(key_keycode, mods);

        std.debug.assert(binding.is_valid());
        std.debug.assert(!keycode.is_modifier(key_keycode));
        std.debug.assert(mods.count() <= binding_modifier_limit);

        var keyboard = Keyboard.init();

        std.debug.assert(keyboard.count() == 0);

        apply_binding_to_keyboard(&keyboard, key_keycode, &mods);

        std.debug.assert(keyboard.is_down(key_keycode));
        std.debug.assert(binding.match(&keyboard));

        keyboard.clear();

        std.debug.assert(keyboard.count() == 0);
        std.debug.assert(!binding.match(&keyboard));
    }

    std.debug.assert(iteration == iterations);
}

fn apply_binding_to_keyboard(
    keyboard: *input.state.Keyboard,
    key_keycode: u8,
    mods: *const modifier.Set,
) void {
    std.debug.assert(@intFromPtr(keyboard) != 0);
    std.debug.assert(keycode.is_valid(key_keycode));
    std.debug.assert(mods.flags <= modifier.flag_all);

    const initial_count = keyboard.count();

    keyboard.keydown(key_keycode);

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

    std.debug.assert(keyboard.is_down(key_keycode));
    std.debug.assert(keyboard.count() >= initial_count + 1);
}

const testing = std.testing;

test "RegistryState init" {
    const state = RegistryState.init();

    std.debug.assert(state.count == 0);
    std.debug.assert(state.is_valid());

    try testing.expectEqual(@as(u32, 0), state.count);
    try testing.expect(state.is_valid());
}

test "RegistryState add and remove" {
    var state = RegistryState.init();

    std.debug.assert(state.count == 0);

    state.add(1);

    std.debug.assert(state.count == 1);
    std.debug.assert(state.ids[0] == 1);

    state.add(2);

    std.debug.assert(state.count == 2);
    std.debug.assert(state.ids[1] == 2);

    try testing.expectEqual(@as(u32, 2), state.count);

    state.remove_at(0);

    std.debug.assert(state.count == 1);

    try testing.expectEqual(@as(u32, 1), state.count);

    state.clear();

    std.debug.assert(state.count == 0);

    try testing.expectEqual(@as(u32, 0), state.count);
}

test "RegistryState get_random_index empty" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    const state = RegistryState.init();

    std.debug.assert(state.count == 0);

    const result = state.get_random_index(&random);

    std.debug.assert(result == null);

    try testing.expect(result == null);
}

test "RegistryState get_random_index populated" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var state = RegistryState.init();

    state.add(10);
    state.add(20);
    state.add(30);

    std.debug.assert(state.count == 3);

    const result = state.get_random_index(&random);

    std.debug.assert(result != null);
    std.debug.assert(result.? < state.count);

    try testing.expect(result != null);
    try testing.expect(result.? < state.count);
}

test "RegistryState capacity limit" {
    var state = RegistryState.init();
    var i: u32 = 0;

    while (i < registered_capacity) : (i += 1) {
        std.debug.assert(i < registered_capacity);

        state.add(i + 1);
    }

    std.debug.assert(i == registered_capacity);
    std.debug.assert(state.count == registered_capacity);

    state.add(999);

    std.debug.assert(state.count == registered_capacity);

    try testing.expectEqual(registered_capacity, state.count);
}

test "fuzz_key_registry basic" {
    try fuzz_key_registry(42, 1000);
}

test "fuzz_key_registry determinism" {
    try fuzz_key_registry(12345, 500);
    try fuzz_key_registry(12345, 500);
}

test "fuzz_binding_matching basic" {
    try fuzz_binding_matching(42, 1000);
}

test "fuzz_binding_matching determinism" {
    try fuzz_binding_matching(12345, 500);
    try fuzz_binding_matching(12345, 500);
}

test "apply_binding_to_keyboard" {
    var keyboard = input.state.Keyboard.init();
    const mods = modifier.Set{ .flags = modifier.flag_ctrl | modifier.flag_shift };

    std.debug.assert(keyboard.count() == 0);

    apply_binding_to_keyboard(&keyboard, 'A', &mods);

    std.debug.assert(keyboard.is_down('A'));
    std.debug.assert(keyboard.is_down(keycode.lctrl));
    std.debug.assert(keyboard.is_down(keycode.lshift));

    try testing.expect(keyboard.is_down('A'));
    try testing.expect(keyboard.is_down(keycode.lctrl));
    try testing.expect(keyboard.is_down(keycode.lshift));
}
