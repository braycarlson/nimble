const std = @import("std");

const assert = std.debug.assert;

handle: Handle = handle_default,
present: bool = true,
fullscreen: bool = false,
maximized: bool = false,
class: [text_bytes_max]u8 = @splat(0),
class_len: u16 = 0,
title: [text_bytes_max]u8 = @splat(0),
title_len: u16 = 0,

const Window = @This();

pub const Handle = u32;

pub const handle_none: Handle = 0;
const handle_default: Handle = 1;
const text_bytes_max: u16 = 256;

comptime {
    assert(handle_none != handle_default);
    assert(text_bytes_max > 0);
}

pub fn foreground(window: *const Window) ?Handle {
    if (!window.present) {
        return null;
    }

    assert(window.handle != handle_none);

    return window.handle;
}

pub fn is_fullscreen(window: *const Window, handle: Handle) bool {
    assert(handle != handle_none);
    assert(handle == window.handle);

    return window.fullscreen;
}

pub fn is_maximized(window: *const Window, handle: Handle) bool {
    assert(handle != handle_none);
    assert(handle == window.handle);

    return window.maximized;
}

pub fn class_matches(window: *const Window, handle: Handle, target: []const u8) bool {
    assert(handle != handle_none);
    assert(target.len <= text_bytes_max);

    const class = window.class[0..window.class_len];
    return std.mem.find(u8, class, target) != null;
}

pub fn title_matches(window: *const Window, handle: Handle, target: []const u8) bool {
    assert(handle != handle_none);
    assert(target.len <= text_bytes_max);

    const title = window.title[0..window.title_len];
    return std.mem.find(u8, title, target) != null;
}

pub fn set_present(window: *Window, present: bool) void {
    window.present = present;

    assert(window.present == present);
}

pub fn set_class(window: *Window, class: []const u8) void {
    assert(class.len <= text_bytes_max);

    @memcpy(window.class[0..class.len], class);

    window.class_len = @intCast(class.len);

    assert(window.class_len == class.len);
}

pub fn set_title(window: *Window, title: []const u8) void {
    assert(title.len <= text_bytes_max);

    @memcpy(window.title[0..title.len], title);

    window.title_len = @intCast(title.len);

    assert(window.title_len == title.len);
}

pub fn set_fullscreen(window: *Window, value: bool) void {
    window.fullscreen = value;

    assert(window.fullscreen == value);
}

pub fn set_maximized(window: *Window, value: bool) void {
    window.maximized = value;

    assert(window.maximized == value);
}

const testing = std.testing;

test "the fake desktop answers for its one foreground window" {
    var window: Window = .{};

    const handle = window.foreground() orelse return error.WindowMissing;

    window.set_class("Notepad");
    window.set_title("Untitled - Notepad");
    window.set_maximized(true);

    try testing.expect(window.class_matches(handle, "Note"));
    try testing.expect(window.title_matches(handle, "Untitled"));
    try testing.expect(window.is_maximized(handle));
    try testing.expect(!window.is_fullscreen(handle));

    window.set_present(false);

    try testing.expect(window.foreground() == null);
}
