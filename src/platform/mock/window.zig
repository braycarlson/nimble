const std = @import("std");

const assert = std.debug.assert;

pub const text_bytes_max: u16 = 256;

pub const Handle = u32;

pub const handle_none: Handle = 0;
pub const handle_default: Handle = 1;

const Desktop = struct {
    handle: Handle = handle_default,
    present: bool = true,
    fullscreen: bool = false,
    maximized: bool = false,
    class: [text_bytes_max]u8 = @splat(0),
    class_len: u16 = 0,
    title: [text_bytes_max]u8 = @splat(0),
    title_len: u16 = 0,
};

var desktop: Desktop = .{};

comptime {
    assert(handle_none != handle_default);
    assert(text_bytes_max > 0);
}

pub fn foreground() ?Handle {
    if (!desktop.present) {
        return null;
    }

    assert(desktop.handle != handle_none);

    return desktop.handle;
}

pub fn get_focused() ?Handle {
    return foreground();
}

pub fn is_fullscreen(handle: Handle) bool {
    assert(handle != handle_none);

    return desktop.fullscreen;
}

pub fn is_maximized(handle: Handle) bool {
    assert(handle != handle_none);

    return desktop.maximized;
}

pub fn class_matches(handle: Handle, target: []const u8) bool {
    assert(handle != handle_none);
    assert(target.len <= text_bytes_max);

    const class = desktop.class[0..desktop.class_len];

    return std.mem.indexOf(u8, class, target) != null;
}

pub fn title_matches(handle: Handle, target: []const u8) bool {
    assert(handle != handle_none);
    assert(target.len <= text_bytes_max);

    const title = desktop.title[0..desktop.title_len];

    return std.mem.indexOf(u8, title, target) != null;
}

pub fn set_present(present: bool) void {
    desktop.present = present;

    assert(desktop.present == present);
}

pub fn set_class(class: []const u8) void {
    assert(class.len <= text_bytes_max);

    @memcpy(desktop.class[0..class.len], class);

    desktop.class_len = @intCast(class.len);

    assert(desktop.class_len == class.len);
}

pub fn set_title(title: []const u8) void {
    assert(title.len <= text_bytes_max);

    @memcpy(desktop.title[0..title.len], title);

    desktop.title_len = @intCast(title.len);

    assert(desktop.title_len == title.len);
}

pub fn set_fullscreen(value: bool) void {
    desktop.fullscreen = value;
}

pub fn set_maximized(value: bool) void {
    desktop.maximized = value;
}

pub fn reset() void {
    desktop = .{};

    assert(desktop.present);
    assert(desktop.class_len == 0);
}
