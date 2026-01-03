const std = @import("std");

const input = @import("input");
const keycode = input.keycode;
const state = input.state;

const Keyboard = state.Keyboard;

pub const invariant_count: u8 = 4;
pub const iteration_max: u32 = 0xFFFFFFFF;

pub const Invariant = struct {
    name: []const u8,
    check: *const fn (*const Context) bool,

    pub fn is_valid(self: *const Invariant) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_name = self.name.len > 0;
        const valid_check = @intFromPtr(self.check) != 0;
        const result = valid_name and valid_check;

        return result;
    }
};

pub const Context = struct {
    keyboard: *const Keyboard,
    last_key: ?u8 = null,
    last_down: bool = false,

    pub fn is_valid(self: *const Context) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_keyboard = @intFromPtr(self.keyboard) != 0;
        const valid_last_key = self.last_key == null or keycode.is_valid(self.last_key.?);
        const result = valid_keyboard and valid_last_key;

        return result;
    }
};

pub fn keyboard_down_consistency(ctx: *const Context) bool {
    std.debug.assert(@intFromPtr(ctx) != 0);
    std.debug.assert(ctx.is_valid());
    std.debug.assert(@intFromPtr(ctx.keyboard) != 0);

    const keyboard = ctx.keyboard;

    std.debug.assert(keyboard.is_valid());

    if (ctx.last_key) |key| {
        std.debug.assert(keycode.is_valid(key));

        if (ctx.last_down) {
            if (!keyboard.is_down(key)) {
                return false;
            }
        }
    }

    return true;
}

pub fn keyboard_modifier_implication(ctx: *const Context) bool {
    std.debug.assert(@intFromPtr(ctx) != 0);
    std.debug.assert(ctx.is_valid());
    std.debug.assert(@intFromPtr(ctx.keyboard) != 0);

    const keyboard = ctx.keyboard;

    std.debug.assert(keyboard.is_valid());

    const shift_implied = check_shift_implication(keyboard);
    const ctrl_implied = check_ctrl_implication(keyboard);
    const alt_implied = check_alt_implication(keyboard);

    const result = shift_implied and ctrl_implied and alt_implied;

    return result;
}

fn check_shift_implication(keyboard: *const Keyboard) bool {
    std.debug.assert(@intFromPtr(keyboard) != 0);
    std.debug.assert(keyboard.is_valid());

    const left_down = keyboard.is_down(keycode.lshift);
    const right_down = keyboard.is_down(keycode.rshift);
    const generic_down = keyboard.is_down(keycode.shift);
    const either_down = left_down or right_down;

    if (either_down and !generic_down) {
        return false;
    }

    return true;
}

fn check_ctrl_implication(keyboard: *const Keyboard) bool {
    std.debug.assert(@intFromPtr(keyboard) != 0);
    std.debug.assert(keyboard.is_valid());

    const left_down = keyboard.is_down(keycode.lctrl);
    const right_down = keyboard.is_down(keycode.rctrl);
    const generic_down = keyboard.is_down(keycode.control);
    const either_down = left_down or right_down;

    if (either_down and !generic_down) {
        return false;
    }

    return true;
}

fn check_alt_implication(keyboard: *const Keyboard) bool {
    std.debug.assert(@intFromPtr(keyboard) != 0);
    std.debug.assert(keyboard.is_valid());

    const left_down = keyboard.is_down(keycode.lmenu);
    const right_down = keyboard.is_down(keycode.rmenu);
    const generic_down = keyboard.is_down(keycode.menu);
    const either_down = left_down or right_down;

    if (either_down and !generic_down) {
        return false;
    }

    return true;
}

pub fn keyboard_count_consistency(ctx: *const Context) bool {
    std.debug.assert(@intFromPtr(ctx) != 0);
    std.debug.assert(ctx.is_valid());
    std.debug.assert(@intFromPtr(ctx.keyboard) != 0);

    const keyboard = ctx.keyboard;

    std.debug.assert(keyboard.is_valid());

    const reported_count = keyboard.count();
    const valid_range = reported_count <= 256;

    return valid_range;
}

pub fn keyboard_helper_consistency(ctx: *const Context) bool {
    std.debug.assert(@intFromPtr(ctx) != 0);
    std.debug.assert(ctx.is_valid());
    std.debug.assert(@intFromPtr(ctx.keyboard) != 0);

    const keyboard = ctx.keyboard;

    std.debug.assert(keyboard.is_valid());

    const mods = keyboard.get_modifiers();

    const ctrl_consistent = check_modifier_flag_consistency(
        keyboard,
        mods.ctrl(),
        keycode.lctrl,
        keycode.rctrl,
    );

    const alt_consistent = check_modifier_flag_consistency(
        keyboard,
        mods.alt(),
        keycode.lmenu,
        keycode.rmenu,
    );

    const shift_consistent = check_modifier_flag_consistency(
        keyboard,
        mods.shift(),
        keycode.lshift,
        keycode.rshift,
    );

    const result = ctrl_consistent and alt_consistent and shift_consistent;

    return result;
}

fn check_modifier_flag_consistency(
    keyboard: *const Keyboard,
    flag_set: bool,
    left_key: u8,
    right_key: u8,
) bool {
    std.debug.assert(@intFromPtr(keyboard) != 0);
    std.debug.assert(keyboard.is_valid());
    std.debug.assert(keycode.is_valid(left_key));
    std.debug.assert(keycode.is_valid(right_key));

    const left_down = keyboard.is_down(left_key);
    const right_down = keyboard.is_down(right_key);
    const either_down = left_down or right_down;

    if (either_down and !flag_set) {
        return false;
    }

    return true;
}

pub const keyboard_invariants = [invariant_count]Invariant{
    .{ .name = "down_consistency", .check = keyboard_down_consistency },
    .{ .name = "modifier_implication", .check = keyboard_modifier_implication },
    .{ .name = "count_consistency", .check = keyboard_count_consistency },
    .{ .name = "helper_consistency", .check = keyboard_helper_consistency },
};

pub fn check_all(ctx: *const Context) ?[]const u8 {
    std.debug.assert(@intFromPtr(ctx) != 0);
    std.debug.assert(ctx.is_valid());
    std.debug.assert(@intFromPtr(ctx.keyboard) != 0);

    var i: u8 = 0;

    while (i < invariant_count) : (i += 1) {
        std.debug.assert(i < invariant_count);

        const inv = keyboard_invariants[i];

        std.debug.assert(inv.is_valid());

        if (!inv.check(ctx)) {
            std.debug.assert(inv.name.len > 0);

            return inv.name;
        }
    }

    std.debug.assert(i == invariant_count);

    return null;
}

pub fn check_single(ctx: *const Context, name: []const u8) bool {
    std.debug.assert(@intFromPtr(ctx) != 0);
    std.debug.assert(ctx.is_valid());
    std.debug.assert(name.len > 0);

    var i: u8 = 0;

    while (i < invariant_count) : (i += 1) {
        std.debug.assert(i < invariant_count);

        const inv = keyboard_invariants[i];

        std.debug.assert(inv.is_valid());

        if (std.mem.eql(u8, inv.name, name)) {
            const result = inv.check(ctx);

            return result;
        }
    }

    std.debug.assert(i == invariant_count);

    return true;
}

const testing = std.testing;

test "Context is_valid" {
    var keyboard = Keyboard.init();

    const ctx = Context{
        .keyboard = &keyboard,
        .last_key = null,
        .last_down = false,
    };

    std.debug.assert(ctx.is_valid());

    try testing.expect(ctx.is_valid());
}

test "Context with last_key is_valid" {
    var keyboard = Keyboard.init();

    const ctx = Context{
        .keyboard = &keyboard,
        .last_key = 'A',
        .last_down = true,
    };

    std.debug.assert(ctx.is_valid());

    try testing.expect(ctx.is_valid());
}

test "Invariant is_valid" {
    const inv = keyboard_invariants[0];

    std.debug.assert(inv.is_valid());
    std.debug.assert(inv.name.len > 0);

    try testing.expect(inv.is_valid());
    try testing.expect(inv.name.len > 0);
}

test "keyboard_down_consistency passes on empty" {
    var keyboard = Keyboard.init();

    const ctx = Context{
        .keyboard = &keyboard,
        .last_key = null,
        .last_down = false,
    };

    std.debug.assert(ctx.is_valid());

    const result = keyboard_down_consistency(&ctx);

    std.debug.assert(result);

    try testing.expect(result);
}

test "keyboard_down_consistency passes after keydown" {
    var keyboard = Keyboard.init();

    keyboard.keydown('A');

    std.debug.assert(keyboard.is_down('A'));

    const ctx = Context{
        .keyboard = &keyboard,
        .last_key = 'A',
        .last_down = true,
    };

    std.debug.assert(ctx.is_valid());

    const result = keyboard_down_consistency(&ctx);

    std.debug.assert(result);

    try testing.expect(result);
}

test "keyboard_modifier_implication passes on empty" {
    var keyboard = Keyboard.init();

    const ctx = Context{
        .keyboard = &keyboard,
        .last_key = null,
        .last_down = false,
    };

    std.debug.assert(ctx.is_valid());

    const result = keyboard_modifier_implication(&ctx);

    std.debug.assert(result);

    try testing.expect(result);
}

test "keyboard_modifier_implication passes with left shift" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.lshift);

    std.debug.assert(keyboard.is_down(keycode.lshift));
    std.debug.assert(keyboard.is_down(keycode.shift));

    const ctx = Context{
        .keyboard = &keyboard,
        .last_key = keycode.lshift,
        .last_down = true,
    };

    std.debug.assert(ctx.is_valid());

    const result = keyboard_modifier_implication(&ctx);

    std.debug.assert(result);

    try testing.expect(result);
}

test "keyboard_count_consistency passes" {
    var keyboard = Keyboard.init();

    keyboard.keydown('A');
    keyboard.keydown('B');

    std.debug.assert(keyboard.count() <= 256);

    const ctx = Context{
        .keyboard = &keyboard,
        .last_key = null,
        .last_down = false,
    };

    std.debug.assert(ctx.is_valid());

    const result = keyboard_count_consistency(&ctx);

    std.debug.assert(result);

    try testing.expect(result);
}

test "keyboard_helper_consistency passes" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.lctrl);

    std.debug.assert(keyboard.is_down(keycode.lctrl));

    const mods = keyboard.get_modifiers();

    std.debug.assert(mods.ctrl());

    const ctx = Context{
        .keyboard = &keyboard,
        .last_key = keycode.lctrl,
        .last_down = true,
    };

    std.debug.assert(ctx.is_valid());

    const result = keyboard_helper_consistency(&ctx);

    std.debug.assert(result);

    try testing.expect(result);
}

test "check_all passes on valid keyboard" {
    var keyboard = Keyboard.init();

    keyboard.keydown('A');
    keyboard.keydown(keycode.lshift);

    std.debug.assert(keyboard.is_down('A'));
    std.debug.assert(keyboard.is_down(keycode.lshift));

    const ctx = Context{
        .keyboard = &keyboard,
        .last_key = 'A',
        .last_down = true,
    };

    std.debug.assert(ctx.is_valid());

    const result = check_all(&ctx);

    std.debug.assert(result == null);

    try testing.expect(result == null);
}

test "check_single finds invariant" {
    var keyboard = Keyboard.init();

    const ctx = Context{
        .keyboard = &keyboard,
        .last_key = null,
        .last_down = false,
    };

    std.debug.assert(ctx.is_valid());

    const result = check_single(&ctx, "down_consistency");

    std.debug.assert(result);

    try testing.expect(result);
}

test "all invariants have valid names" {
    var i: u8 = 0;

    while (i < invariant_count) : (i += 1) {
        std.debug.assert(i < invariant_count);

        const inv = keyboard_invariants[i];

        std.debug.assert(inv.is_valid());
        std.debug.assert(inv.name.len > 0);

        try testing.expect(inv.name.len > 0);
    }

    std.debug.assert(i == invariant_count);
}
