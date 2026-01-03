const std = @import("std");
const input = @import("input");

const state_mod = input.state;
const keycode = input.keycode;

const Keyboard = state_mod.Keyboard;

const testing = std.testing;

test "Keyboard.init" {
    const keyboard = Keyboard.init();

    try testing.expect(keyboard.is_valid());
    try testing.expectEqual(@as(u32, 0), keyboard.count());
}

test "Keyboard.keydown and keyup" {
    var keyboard = Keyboard.init();

    keyboard.keydown('A');
    try testing.expect(keyboard.is_down('A'));
    try testing.expectEqual(@as(u32, 1), keyboard.count());

    keyboard.keyup('A');
    try testing.expect(!keyboard.is_down('A'));
    try testing.expectEqual(@as(u32, 0), keyboard.count());
}

test "Keyboard.modifier tracking" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.lctrl);
    try testing.expect(keyboard.is_ctrl_down());
    try testing.expect(keyboard.is_down(keycode.control));

    keyboard.keydown(keycode.lshift);
    try testing.expect(keyboard.is_shift_down());

    keyboard.keyup(keycode.lctrl);
    try testing.expect(!keyboard.is_ctrl_down());
    try testing.expect(!keyboard.is_down(keycode.control));
}

test "Keyboard.dual modifier keys" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.lctrl);
    keyboard.keydown(keycode.rctrl);
    try testing.expect(keyboard.is_ctrl_down());

    keyboard.keyup(keycode.lctrl);
    try testing.expect(keyboard.is_ctrl_down());

    keyboard.keyup(keycode.rctrl);
    try testing.expect(!keyboard.is_ctrl_down());
}

test "Keyboard.clear" {
    var keyboard = Keyboard.init();

    keyboard.keydown('A');
    keyboard.keydown('B');
    keyboard.keydown(keycode.lctrl);

    keyboard.clear();

    try testing.expect(keyboard.is_valid());
    try testing.expectEqual(@as(u32, 0), keyboard.count());
    try testing.expect(!keyboard.is_down('A'));
    try testing.expect(!keyboard.is_ctrl_down());
}

test "Keyboard.get_modifiers" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.lctrl);
    keyboard.keydown(keycode.lmenu);

    const modifiers = keyboard.get_modifiers();

    try testing.expect(modifiers.ctrl());
    try testing.expect(modifiers.alt());
    try testing.expect(!modifiers.shift());
    try testing.expect(!modifiers.win());
}

test "Keyboard.is_win_down left" {
    var keyboard = Keyboard.init();

    try testing.expect(!keyboard.is_win_down());

    keyboard.keydown(keycode.lwin);
    try testing.expect(keyboard.is_win_down());

    keyboard.keyup(keycode.lwin);
    try testing.expect(!keyboard.is_win_down());
}

test "Keyboard.is_win_down right" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.rwin);
    try testing.expect(keyboard.is_win_down());

    keyboard.keyup(keycode.rwin);
    try testing.expect(!keyboard.is_win_down());
}

test "Keyboard.is_win_down both" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.lwin);
    keyboard.keydown(keycode.rwin);
    try testing.expect(keyboard.is_win_down());

    keyboard.keyup(keycode.lwin);
    try testing.expect(keyboard.is_win_down());

    keyboard.keyup(keycode.rwin);
    try testing.expect(!keyboard.is_win_down());
}

test "Keyboard.is_alt_down left and right" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.lmenu);
    try testing.expect(keyboard.is_alt_down());
    try testing.expect(keyboard.is_down(keycode.menu));

    keyboard.keyup(keycode.lmenu);
    try testing.expect(!keyboard.is_alt_down());

    keyboard.keydown(keycode.rmenu);
    try testing.expect(keyboard.is_alt_down());
}

test "Keyboard.is_shift_down left and right" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.lshift);
    try testing.expect(keyboard.is_shift_down());
    try testing.expect(keyboard.is_down(keycode.shift));

    keyboard.keyup(keycode.lshift);
    try testing.expect(!keyboard.is_shift_down());

    keyboard.keydown(keycode.rshift);
    try testing.expect(keyboard.is_shift_down());
}

test "Keyboard.multiple keys" {
    var keyboard = Keyboard.init();

    keyboard.keydown('A');
    keyboard.keydown('B');
    keyboard.keydown('C');

    try testing.expectEqual(@as(u32, 3), keyboard.count());
    try testing.expect(keyboard.is_down('A'));
    try testing.expect(keyboard.is_down('B'));
    try testing.expect(keyboard.is_down('C'));
    try testing.expect(!keyboard.is_down('D'));

    keyboard.keyup('B');

    try testing.expectEqual(@as(u32, 2), keyboard.count());
    try testing.expect(keyboard.is_down('A'));
    try testing.expect(!keyboard.is_down('B'));
    try testing.expect(keyboard.is_down('C'));
}

test "Keyboard.keydown duplicate" {
    var keyboard = Keyboard.init();

    keyboard.keydown('A');
    keyboard.keydown('A');

    try testing.expectEqual(@as(u32, 1), keyboard.count());
    try testing.expect(keyboard.is_down('A'));
}

test "Keyboard.keyup not pressed" {
    var keyboard = Keyboard.init();

    keyboard.keyup('A');

    try testing.expect(keyboard.is_valid());
    try testing.expectEqual(@as(u32, 0), keyboard.count());
}

test "Keyboard.get_modifiers all" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.lctrl);
    keyboard.keydown(keycode.lmenu);
    keyboard.keydown(keycode.lshift);
    keyboard.keydown(keycode.lwin);

    const modifiers = keyboard.get_modifiers();

    try testing.expect(modifiers.ctrl());
    try testing.expect(modifiers.alt());
    try testing.expect(modifiers.shift());
    try testing.expect(modifiers.win());
    try testing.expectEqual(@as(u8, 4), modifiers.count());
}

test "Keyboard.get_modifiers none" {
    var keyboard = Keyboard.init();

    keyboard.keydown('A');

    const modifiers = keyboard.get_modifiers();

    try testing.expect(!modifiers.ctrl());
    try testing.expect(!modifiers.alt());
    try testing.expect(!modifiers.shift());
    try testing.expect(!modifiers.win());
    try testing.expect(modifiers.none());
}

test "Keyboard.function keys" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.f1);
    try testing.expect(keyboard.is_down(keycode.f1));

    keyboard.keydown(keycode.f12);
    try testing.expect(keyboard.is_down(keycode.f12));

    try testing.expectEqual(@as(u32, 2), keyboard.count());
}

test "Keyboard.special keys" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.escape);
    try testing.expect(keyboard.is_down(keycode.escape));

    keyboard.keydown(keycode.tab);
    try testing.expect(keyboard.is_down(keycode.tab));

    keyboard.keydown(keycode.space);
    try testing.expect(keyboard.is_down(keycode.space));

    keyboard.keydown(keycode.@"return");
    try testing.expect(keyboard.is_down(keycode.@"return"));
}

test "Keyboard.navigation keys" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.left);
    keyboard.keydown(keycode.right);
    keyboard.keydown(keycode.up);
    keyboard.keydown(keycode.down);

    try testing.expect(keyboard.is_down(keycode.left));
    try testing.expect(keyboard.is_down(keycode.right));
    try testing.expect(keyboard.is_down(keycode.up));
    try testing.expect(keyboard.is_down(keycode.down));
    try testing.expectEqual(@as(u32, 4), keyboard.count());
}

test "Keyboard.clear after modifiers" {
    var keyboard = Keyboard.init();

    keyboard.keydown(keycode.lctrl);
    keyboard.keydown(keycode.lshift);
    keyboard.keydown(keycode.lmenu);
    keyboard.keydown(keycode.lwin);

    try testing.expect(keyboard.is_ctrl_down());
    try testing.expect(keyboard.is_shift_down());
    try testing.expect(keyboard.is_alt_down());
    try testing.expect(keyboard.is_win_down());

    keyboard.clear();

    try testing.expect(!keyboard.is_ctrl_down());
    try testing.expect(!keyboard.is_shift_down());
    try testing.expect(!keyboard.is_alt_down());
    try testing.expect(!keyboard.is_win_down());
    try testing.expectEqual(@as(u32, 0), keyboard.count());
}
