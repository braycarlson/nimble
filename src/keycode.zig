const std = @import("std");

pub const silent: u8 = 0xE8;
pub const value_min: u8 = 0x01;
pub const value_max: u8 = 0xFE;
pub const value_dummy: u8 = 0xFF;

pub const back: u8 = 0x08;
pub const tab: u8 = 0x09;
pub const @"return": u8 = 0x0D;
pub const shift: u8 = 0x10;
pub const control: u8 = 0x11;
pub const menu: u8 = 0x12;
pub const pause: u8 = 0x13;
pub const capital: u8 = 0x14;
pub const escape: u8 = 0x1B;
pub const space: u8 = 0x20;
pub const prior: u8 = 0x21;
pub const next: u8 = 0x22;
pub const end: u8 = 0x23;
pub const home: u8 = 0x24;
pub const left: u8 = 0x25;
pub const up: u8 = 0x26;
pub const right: u8 = 0x27;
pub const down: u8 = 0x28;
pub const snapshot: u8 = 0x2C;
pub const insert: u8 = 0x2D;
pub const delete: u8 = 0x2E;
pub const lwin: u8 = 0x5B;
pub const rwin: u8 = 0x5C;
pub const app: u8 = 0x5D;
pub const numpad0: u8 = 0x60;
pub const numpad9: u8 = 0x69;
pub const multiply: u8 = 0x6A;
pub const add: u8 = 0x6B;
pub const separator: u8 = 0x6C;
pub const subtract: u8 = 0x6D;
pub const decimal: u8 = 0x6E;
pub const divide: u8 = 0x6F;
pub const numlock: u8 = 0x90;
pub const scroll: u8 = 0x91;
pub const lshift: u8 = 0xA0;
pub const rshift: u8 = 0xA1;
pub const lctrl: u8 = 0xA2;
pub const rctrl: u8 = 0xA3;
pub const lmenu: u8 = 0xA4;
pub const rmenu: u8 = 0xA5;
pub const f1: u8 = 0x70;
pub const f2: u8 = 0x71;
pub const f3: u8 = 0x72;
pub const f4: u8 = 0x73;
pub const f5: u8 = 0x74;
pub const f6: u8 = 0x75;
pub const f7: u8 = 0x76;
pub const f8: u8 = 0x77;
pub const f9: u8 = 0x78;
pub const f10: u8 = 0x79;
pub const f11: u8 = 0x7A;
pub const f12: u8 = 0x7B;
pub const oem_1: u8 = 0xBA;
pub const oem_plus: u8 = 0xBB;
pub const oem_comma: u8 = 0xBC;
pub const oem_minus: u8 = 0xBD;
pub const oem_period: u8 = 0xBE;
pub const oem_2: u8 = 0xBF;
pub const oem_3: u8 = 0xC0;
pub const oem_4: u8 = 0xDB;
pub const oem_5: u8 = 0xDC;
pub const oem_6: u8 = 0xDD;
pub const oem_7: u8 = 0xDE;

const name_map = std.StaticStringMap(u8).initComptime(.{
    .{ "backspace", back },
    .{ "tab", tab },
    .{ "enter", @"return" },
    .{ "return", @"return" },
    .{ "pause", pause },
    .{ "capslock", capital },
    .{ "caps", capital },
    .{ "escape", escape },
    .{ "esc", escape },
    .{ "space", space },
    .{ "pageup", prior },
    .{ "pagedown", next },
    .{ "end", end },
    .{ "home", home },
    .{ "left", left },
    .{ "up", up },
    .{ "right", right },
    .{ "down", down },
    .{ "printscreen", snapshot },
    .{ "insert", insert },
    .{ "delete", delete },
    .{ "del", delete },
    .{ "f1", f1 },
    .{ "f12", f12 },
    .{ "numlock", numlock },
    .{ "scrolllock", scroll },
});

pub fn from_char(character: u8) ?u8 {
    std.debug.assert(character != 0);

    const upper = std.ascii.toUpper(character);

    std.debug.assert(upper == character or upper == character - 32);

    const alpha = upper >= 'A' and upper <= 'Z';
    const digit = upper >= '0' and upper <= '9';

    if (alpha or digit) {
        std.debug.assert(is_valid(upper));
        return upper;
    }

    return null;
}

pub fn from_name(text: []const u8) ?u8 {
    std.debug.assert(text.len > 0);
    std.debug.assert(text.len <= 16);

    const result = name_map.get(text);

    return result;
}

pub fn from_string(text: []const u8) ?u8 {
    if (text.len == 0) {
        return null;
    }

    std.debug.assert(text.len > 0);
    std.debug.assert(text.len <= 32);

    if (text.len == 1) {
        return from_char(text[0]);
    }

    std.debug.assert(text.len > 1);

    return from_name(text);
}

pub fn is_alpha(value: u8) bool {
    std.debug.assert(is_valid(value));
    std.debug.assert(value >= value_min);
    std.debug.assert(value <= value_max);

    const result = value >= 'A' and value <= 'Z';

    return result;
}

pub fn is_digit(value: u8) bool {
    std.debug.assert(is_valid(value));
    std.debug.assert(value >= value_min);
    std.debug.assert(value <= value_max);

    const result = value >= '0' and value <= '9';

    return result;
}

pub fn is_modifier(value: u8) bool {
    std.debug.assert(is_valid(value));
    std.debug.assert(value >= value_min);
    std.debug.assert(value <= value_max);

    const result = switch (value) {
        shift, lshift, rshift => true,
        control, lctrl, rctrl => true,
        menu, lmenu, rmenu => true,
        lwin, rwin => true,
        else => false,
    };

    return result;
}

pub fn is_valid(value: u8) bool {
    std.debug.assert(value_min == 0x01);
    std.debug.assert(value_max == 0xFE);

    const above_min = value >= value_min;
    const below_max = value <= value_max;
    const result = above_min and below_max;

    return result;
}

pub fn to_name(value: u8) ?[]const u8 {
    std.debug.assert(is_valid(value));
    std.debug.assert(value >= value_min);
    std.debug.assert(value <= value_max);

    const result: ?[]const u8 = switch (value) {
        back => "Backspace",
        tab => "Tab",
        @"return" => "Enter",
        shift, lshift, rshift => "Shift",
        control, lctrl, rctrl => "Ctrl",
        menu, lmenu, rmenu => "Alt",
        pause => "Pause",
        capital => "CapsLock",
        escape => "Escape",
        space => "Space",
        prior => "PageUp",
        next => "PageDown",
        end => "End",
        home => "Home",
        left => "Left",
        up => "Up",
        right => "Right",
        down => "Down",
        snapshot => "PrintScreen",
        insert => "Insert",
        delete => "Delete",
        lwin, rwin => "Win",
        app => "App",
        f1 => "F1",
        f12 => "F12",
        numlock => "NumLock",
        scroll => "ScrollLock",
        else => null,
    };

    return result;
}

pub fn to_string(value: u8) ?[]const u8 {
    std.debug.assert(is_valid(value));
    std.debug.assert(value >= value_min);
    std.debug.assert(value <= value_max);

    if (is_alpha(value)) {
        return null;
    }

    if (is_digit(value)) {
        return null;
    }

    return to_name(value);
}
