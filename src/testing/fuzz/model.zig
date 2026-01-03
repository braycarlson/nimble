const std = @import("std");

const input = @import("input");
const keycode = input.keycode;
const state = input.state;

const Keyboard = state.Keyboard;

pub const key_buffer_size: u8 = 32;
pub const generic_modifier_count: u8 = 3;
pub const specific_modifier_count: u8 = 8;
pub const bits_per_byte: u8 = 8;
pub const retry_max: u8 = 10;
pub const key_count: u16 = 256;
pub const operation_threshold_keydown: u8 = 60;
pub const operation_threshold_keyup: u8 = 90;
pub const operation_threshold_clear: u8 = 95;
pub const iteration_max: u32 = 0xFFFFFFFF;

const generic_modifiers = [generic_modifier_count]u8{
    keycode.shift,
    keycode.control,
    keycode.menu,
};

const specific_modifiers = [specific_modifier_count]u8{
    keycode.lshift,
    keycode.rshift,
    keycode.lctrl,
    keycode.rctrl,
    keycode.lmenu,
    keycode.rmenu,
    keycode.lwin,
    keycode.rwin,
};

pub const Operation = union(enum) {
    keydown: u8,
    keyup: u8,
    clear: void,

    pub fn apply(self: Operation, keyboard: *Keyboard) void {
        std.debug.assert(@intFromPtr(keyboard) != 0);
        std.debug.assert(keyboard.is_valid());

        switch (self) {
            .keydown => |key| {
                std.debug.assert(keycode.is_valid(key));

                keyboard.keydown(key);

                std.debug.assert(keyboard.is_down(key));
            },
            .keyup => |key| {
                std.debug.assert(keycode.is_valid(key));

                keyboard.keyup(key);

                std.debug.assert(!keyboard.is_down(key));
            },
            .clear => {
                keyboard.clear();

                std.debug.assert(keyboard.count() == 0);
            },
        }
    }

    pub fn apply_to_model(self: Operation, model: *Model) void {
        std.debug.assert(@intFromPtr(model) != 0);
        std.debug.assert(model.is_valid());

        switch (self) {
            .keydown => |key| {
                std.debug.assert(keycode.is_valid(key));

                model.keydown(key);

                std.debug.assert(model.is_down(key));
            },
            .keyup => |key| {
                std.debug.assert(keycode.is_valid(key));

                model.keyup(key);

                std.debug.assert(!model.is_down(key));
            },
            .clear => {
                model.clear();

                std.debug.assert(model.count() == 0);
            },
        }
    }

    pub fn format(self: Operation, writer: anytype) !void {
        switch (self) {
            .keydown => |key| {
                std.debug.assert(keycode.is_valid(key));

                try writer.print("keydown(0x{X:0>2})", .{key});
            },
            .keyup => |key| {
                std.debug.assert(keycode.is_valid(key));

                try writer.print("keyup(0x{X:0>2})", .{key});
            },
            .clear => try writer.print("clear()", .{}),
        }
    }

    pub fn is_valid(self: Operation) bool {
        const result = switch (self) {
            .keydown => |key| keycode.is_valid(key),
            .keyup => |key| keycode.is_valid(key),
            .clear => true,
        };

        return result;
    }
};

pub const Model = struct {
    keys_down: [key_count]bool = [_]bool{false} ** key_count,
    left_shift_down: bool = false,
    right_shift_down: bool = false,
    left_ctrl_down: bool = false,
    right_ctrl_down: bool = false,
    left_alt_down: bool = false,
    right_alt_down: bool = false,

    pub fn init() Model {
        const result = Model{};

        std.debug.assert(result.count() == 0);
        std.debug.assert(!result.left_shift_down);
        std.debug.assert(!result.right_shift_down);
        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn is_valid(self: *const Model) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const result = true;

        return result;
    }

    pub fn keydown(self: *Model, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        self.keys_down[key] = true;
        self.update_modifier_state(key, true);

        std.debug.assert(self.is_down(key));
    }

    pub fn keyup(self: *Model, key: u8) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        self.keys_down[key] = false;
        self.update_modifier_state(key, false);

        std.debug.assert(!self.is_down(key));
    }

    fn update_modifier_state(self: *Model, key: u8, down: bool) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key));

        if (key == keycode.lshift) {
            self.left_shift_down = down;
        } else if (key == keycode.rshift) {
            self.right_shift_down = down;
        } else if (key == keycode.lctrl) {
            self.left_ctrl_down = down;
        } else if (key == keycode.rctrl) {
            self.right_ctrl_down = down;
        } else if (key == keycode.lmenu) {
            self.left_alt_down = down;
        } else if (key == keycode.rmenu) {
            self.right_alt_down = down;
        }
    }

    pub fn clear(self: *Model) void {
        std.debug.assert(self.is_valid());

        var i: u16 = 0;

        while (i < key_count) : (i += 1) {
            std.debug.assert(i < key_count);

            self.keys_down[i] = false;
        }

        std.debug.assert(i == key_count);

        self.left_shift_down = false;
        self.right_shift_down = false;
        self.left_ctrl_down = false;
        self.right_ctrl_down = false;
        self.left_alt_down = false;
        self.right_alt_down = false;

        std.debug.assert(self.count() == 0);
    }

    pub fn is_down(self: *const Model, key: u8) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(keycode.is_valid(key) or key < key_count);

        if (is_generic_modifier(key)) {
            return self.is_generic_modifier_down(key);
        }

        const result = self.keys_down[key];

        return result;
    }

    fn is_generic_modifier_down(self: *const Model, key: u8) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(is_generic_modifier(key));

        if (key == keycode.shift) {
            const result = self.left_shift_down or self.right_shift_down;

            return result;
        } else if (key == keycode.control) {
            const result = self.left_ctrl_down or self.right_ctrl_down;

            return result;
        } else if (key == keycode.menu) {
            const result = self.left_alt_down or self.right_alt_down;

            return result;
        }

        return false;
    }

    pub fn count(self: *const Model) u32 {
        std.debug.assert(self.is_valid());

        var result: u32 = 0;
        var i: u16 = keycode.value_min;

        while (i <= keycode.value_max) : (i += 1) {
            std.debug.assert(i >= keycode.value_min);
            std.debug.assert(i <= keycode.value_max);

            if (self.keys_down[i]) {
                result += 1;
            }
        }

        std.debug.assert(i > keycode.value_max);
        std.debug.assert(result <= key_count);

        return result;
    }

    pub fn matches(self: *const Model, keyboard: *const Keyboard) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(keyboard) != 0);
        std.debug.assert(keyboard.is_valid());

        var i: u16 = keycode.value_min;

        while (i <= keycode.value_max) : (i += 1) {
            std.debug.assert(i >= keycode.value_min);
            std.debug.assert(i <= keycode.value_max);

            const key: u8 = @intCast(i);
            const model_down = self.keys_down[key];
            const keyboard_down = keyboard.is_down(key);

            if (model_down != keyboard_down) {
                return false;
            }
        }

        std.debug.assert(i > keycode.value_max);

        return true;
    }
};

pub fn is_generic_modifier(key: u8) bool {
    var i: u8 = 0;

    while (i < generic_modifier_count) : (i += 1) {
        std.debug.assert(i < generic_modifier_count);

        if (key == generic_modifiers[i]) {
            return true;
        }
    }

    std.debug.assert(i == generic_modifier_count);

    return false;
}

pub fn is_specific_modifier(key: u8) bool {
    var i: u8 = 0;

    while (i < specific_modifier_count) : (i += 1) {
        std.debug.assert(i < specific_modifier_count);

        if (key == specific_modifiers[i]) {
            return true;
        }
    }

    std.debug.assert(i == specific_modifier_count);

    return false;
}

pub fn is_any_modifier(key: u8) bool {
    const result = is_generic_modifier(key) or is_specific_modifier(key);

    return result;
}

pub fn generate_valid_key(random: *std.Random) u8 {
    std.debug.assert(@intFromPtr(random) != 0);

    var attempts: u8 = 0;
    var result = random.intRangeAtMost(u8, keycode.value_min, keycode.value_max);

    while (is_any_modifier(result) and attempts < retry_max) : (attempts += 1) {
        std.debug.assert(attempts < retry_max);

        result = random.intRangeAtMost(u8, keycode.value_min, keycode.value_max);
    }

    std.debug.assert(attempts <= retry_max);

    if (is_any_modifier(result)) {
        result = 'A';
    }

    std.debug.assert(!is_any_modifier(result));
    std.debug.assert(keycode.is_valid(result));

    return result;
}

pub fn generate_operation(random: *std.Random, model: *const Model) Operation {
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(model.is_valid());

    const op_type = random.intRangeLessThan(u8, 0, 100);

    std.debug.assert(op_type < 100);

    if (op_type < operation_threshold_keydown) {
        return generate_keydown_operation(random);
    }

    if (op_type < operation_threshold_keyup) {
        return generate_keyup_operation(random);
    }

    if (op_type < operation_threshold_clear) {
        return Operation{ .clear = {} };
    }

    return generate_keydown_operation(random);
}

fn generate_keydown_operation(random: *std.Random) Operation {
    std.debug.assert(@intFromPtr(random) != 0);

    const key = generate_valid_key(random);

    std.debug.assert(!is_generic_modifier(key));
    std.debug.assert(keycode.is_valid(key));

    const result = Operation{ .keydown = key };

    std.debug.assert(result.is_valid());

    return result;
}

fn generate_keyup_operation(random: *std.Random) Operation {
    std.debug.assert(@intFromPtr(random) != 0);

    const key = generate_valid_key(random);

    std.debug.assert(!is_generic_modifier(key));
    std.debug.assert(keycode.is_valid(key));

    const result = Operation{ .keyup = key };

    std.debug.assert(result.is_valid());

    return result;
}

const testing = std.testing;

test "Model init" {
    const model = Model.init();

    std.debug.assert(model.is_valid());
    std.debug.assert(model.count() == 0);
    std.debug.assert(!model.left_shift_down);
    std.debug.assert(!model.right_shift_down);

    try testing.expect(model.is_valid());
    try testing.expectEqual(@as(u32, 0), model.count());
}

test "Model keydown and keyup" {
    var model = Model.init();

    std.debug.assert(model.count() == 0);
    std.debug.assert(!model.is_down('A'));

    model.keydown('A');

    std.debug.assert(model.is_down('A'));
    std.debug.assert(model.count() >= 1);

    try testing.expect(model.is_down('A'));

    model.keyup('A');

    std.debug.assert(!model.is_down('A'));

    try testing.expect(!model.is_down('A'));
}

test "Model modifier tracking left shift" {
    var model = Model.init();

    std.debug.assert(!model.is_down(keycode.lshift));
    std.debug.assert(!model.is_down(keycode.shift));
    std.debug.assert(!model.left_shift_down);

    model.keydown(keycode.lshift);

    std.debug.assert(model.is_down(keycode.lshift));
    std.debug.assert(model.is_down(keycode.shift));
    std.debug.assert(model.left_shift_down);

    try testing.expect(model.is_down(keycode.lshift));
    try testing.expect(model.is_down(keycode.shift));

    model.keyup(keycode.lshift);

    std.debug.assert(!model.is_down(keycode.lshift));
    std.debug.assert(!model.left_shift_down);

    try testing.expect(!model.is_down(keycode.lshift));
}

test "Model modifier tracking both shifts" {
    var model = Model.init();

    std.debug.assert(!model.is_down(keycode.shift));

    model.keydown(keycode.lshift);

    std.debug.assert(model.is_down(keycode.shift));
    std.debug.assert(model.left_shift_down);

    model.keydown(keycode.rshift);

    std.debug.assert(model.is_down(keycode.rshift));
    std.debug.assert(model.is_down(keycode.shift));
    std.debug.assert(model.right_shift_down);

    try testing.expect(model.is_down(keycode.rshift));
    try testing.expect(model.is_down(keycode.shift));

    model.keyup(keycode.lshift);

    std.debug.assert(!model.is_down(keycode.lshift));
    std.debug.assert(model.is_down(keycode.shift));

    try testing.expect(!model.is_down(keycode.lshift));
    try testing.expect(model.is_down(keycode.shift));

    model.keyup(keycode.rshift);

    std.debug.assert(!model.is_down(keycode.rshift));
    std.debug.assert(!model.is_down(keycode.shift));

    try testing.expect(!model.is_down(keycode.rshift));
    try testing.expect(!model.is_down(keycode.shift));
}

test "Model clear" {
    var model = Model.init();

    model.keydown('A');
    model.keydown('B');
    model.keydown(keycode.lshift);

    std.debug.assert(model.count() >= 3);
    std.debug.assert(model.left_shift_down);

    model.clear();

    std.debug.assert(model.count() == 0);
    std.debug.assert(!model.left_shift_down);
    std.debug.assert(!model.is_down('A'));
    std.debug.assert(!model.is_down('B'));

    try testing.expectEqual(@as(u32, 0), model.count());
    try testing.expect(!model.is_down('A'));
    try testing.expect(!model.is_down('B'));
}

test "Model matches Keyboard" {
    var model = Model.init();
    var keyboard = Keyboard.init();

    std.debug.assert(model.matches(&keyboard));

    model.keydown('A');
    keyboard.keydown('A');

    std.debug.assert(model.matches(&keyboard));

    try testing.expect(model.matches(&keyboard));

    model.keydown('B');

    std.debug.assert(!model.matches(&keyboard));

    try testing.expect(!model.matches(&keyboard));
}

test "Model matches Keyboard with modifiers" {
    var model = Model.init();
    var keyboard = Keyboard.init();

    std.debug.assert(model.matches(&keyboard));

    model.keydown(keycode.lctrl);
    keyboard.keydown(keycode.lctrl);

    std.debug.assert(model.matches(&keyboard));

    try testing.expect(model.matches(&keyboard));

    model.keyup(keycode.lctrl);
    keyboard.keyup(keycode.lctrl);

    std.debug.assert(model.matches(&keyboard));

    try testing.expect(model.matches(&keyboard));
}

test "generate_valid_key excludes all modifiers" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var i: u32 = 0;

    while (i < 1000) : (i += 1) {
        std.debug.assert(i < 1000);

        const key = generate_valid_key(&random);

        std.debug.assert(!is_any_modifier(key));
        std.debug.assert(keycode.is_valid(key));

        try testing.expect(!is_any_modifier(key));
    }

    std.debug.assert(i == 1000);
}

test "generate_operation produces valid operations" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var model = Model.init();
    var i: u32 = 0;

    while (i < 100) : (i += 1) {
        std.debug.assert(i < 100);
        std.debug.assert(model.is_valid());

        const op = generate_operation(&random, &model);

        std.debug.assert(op.is_valid());

        try testing.expect(op.is_valid());
    }

    std.debug.assert(i == 100);
}

test "Operation apply consistency" {
    var model = Model.init();
    var keyboard = Keyboard.init();

    std.debug.assert(model.matches(&keyboard));

    const op1 = Operation{ .keydown = 'A' };

    std.debug.assert(op1.is_valid());

    op1.apply(&keyboard);
    op1.apply_to_model(&model);

    std.debug.assert(model.matches(&keyboard));
    std.debug.assert(keyboard.is_down('A'));
    std.debug.assert(model.is_down('A'));

    try testing.expect(model.matches(&keyboard));

    const op2 = Operation{ .keyup = 'A' };

    std.debug.assert(op2.is_valid());

    op2.apply(&keyboard);
    op2.apply_to_model(&model);

    std.debug.assert(model.matches(&keyboard));
    std.debug.assert(!keyboard.is_down('A'));
    std.debug.assert(!model.is_down('A'));

    try testing.expect(model.matches(&keyboard));
}

test "is_generic_modifier identifies correctly" {
    std.debug.assert(is_generic_modifier(keycode.shift));
    std.debug.assert(is_generic_modifier(keycode.control));
    std.debug.assert(is_generic_modifier(keycode.menu));
    std.debug.assert(!is_generic_modifier('A'));
    std.debug.assert(!is_generic_modifier(keycode.lshift));
    std.debug.assert(!is_generic_modifier(keycode.lctrl));

    try testing.expect(is_generic_modifier(keycode.shift));
    try testing.expect(is_generic_modifier(keycode.control));
    try testing.expect(is_generic_modifier(keycode.menu));
    try testing.expect(!is_generic_modifier('A'));
    try testing.expect(!is_generic_modifier(keycode.lshift));
}

test "is_specific_modifier identifies correctly" {
    std.debug.assert(is_specific_modifier(keycode.lshift));
    std.debug.assert(is_specific_modifier(keycode.rshift));
    std.debug.assert(is_specific_modifier(keycode.lctrl));
    std.debug.assert(is_specific_modifier(keycode.rctrl));
    std.debug.assert(is_specific_modifier(keycode.lmenu));
    std.debug.assert(is_specific_modifier(keycode.rmenu));
    std.debug.assert(!is_specific_modifier('A'));
    std.debug.assert(!is_specific_modifier(keycode.shift));

    try testing.expect(is_specific_modifier(keycode.lshift));
    try testing.expect(is_specific_modifier(keycode.rshift));
    try testing.expect(!is_specific_modifier('A'));
    try testing.expect(!is_specific_modifier(keycode.shift));
}

test "is_any_modifier identifies all modifiers" {
    std.debug.assert(is_any_modifier(keycode.shift));
    std.debug.assert(is_any_modifier(keycode.lshift));
    std.debug.assert(is_any_modifier(keycode.rshift));
    std.debug.assert(is_any_modifier(keycode.control));
    std.debug.assert(is_any_modifier(keycode.lctrl));
    std.debug.assert(!is_any_modifier('A'));

    try testing.expect(is_any_modifier(keycode.shift));
    try testing.expect(is_any_modifier(keycode.lshift));
    try testing.expect(!is_any_modifier('A'));
}
