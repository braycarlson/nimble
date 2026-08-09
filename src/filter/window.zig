const std = @import("std");

const platform = @import("../platform.zig");

const assert = std.debug.assert;

const window = platform.backend.window;

const Handle = window.Handle;

pub const length_max: u8 = 64;
pub const buffer_max: u16 = 256;

pub const Mode = enum(u2) {
    none = 0,
    only = 1,
    exclude = 2,

    pub fn is_valid(mode: Mode) bool {
        const value = @intFromEnum(mode);

        return value <= 2;
    }
};

pub const FullscreenMode = enum(u2) {
    any = 0,
    only = 1,
    exclude = 2,

    pub fn is_valid(mode: FullscreenMode) bool {
        const value = @intFromEnum(mode);

        return value <= 2;
    }
};

pub const MaximizedMode = enum(u2) {
    any = 0,
    only = 1,
    exclude = 2,

    pub fn is_valid(mode: MaximizedMode) bool {
        const value = @intFromEnum(mode);

        return value <= 2;
    }
};

pub const WindowFilter = struct {
    class: ?[length_max]u8 = null,
    class_len: u8 = 0,
    title: ?[length_max]u8 = null,
    title_len: u8 = 0,
    mode: Mode = .none,
    fullscreen_mode: FullscreenMode = .any,
    maximized_mode: MaximizedMode = .any,

    pub fn init() WindowFilter {
        return WindowFilter{};
    }

    pub fn is_valid(filter: *const WindowFilter) bool {
        const valid_mode = filter.mode.is_valid();
        const valid_fullscreen = filter.fullscreen_mode.is_valid();
        const valid_maximized = filter.maximized_mode.is_valid();
        const valid_class_len = filter.class_len <= length_max;
        const valid_title_len = filter.title_len <= length_max;

        const valid_modes = valid_mode and valid_fullscreen and valid_maximized;
        const valid_lengths = valid_class_len and valid_title_len;

        return valid_modes and valid_lengths;
    }

    pub fn for_class(comptime class: []const u8) WindowFilter {
        comptime {
            if (class.len > length_max) {
                @compileError("Class name exceeds maximum length");
            }
        }

        var filter = WindowFilter{};

        filter.class = [_]u8{0} ** length_max;
        @memcpy(filter.class.?[0..class.len], class);
        filter.class_len = class.len;
        filter.mode = .only;

        return filter;
    }

    pub fn for_title(comptime title: []const u8) WindowFilter {
        comptime {
            if (title.len > length_max) {
                @compileError("Title exceeds maximum length");
            }
        }

        var filter = WindowFilter{};

        filter.title = [_]u8{0} ** length_max;
        @memcpy(filter.title.?[0..title.len], title);
        filter.title_len = title.len;
        filter.mode = .only;

        return filter;
    }

    pub fn exclude_class(comptime class: []const u8) WindowFilter {
        var filter = for_class(class);

        filter.mode = .exclude;

        return filter;
    }

    pub fn exclude_title(comptime title: []const u8) WindowFilter {
        var filter = for_title(title);

        filter.mode = .exclude;

        return filter;
    }

    pub fn fullscreen(filter: WindowFilter) WindowFilter {
        assert(filter.is_valid());

        var result = filter;
        result.fullscreen_mode = .only;

        return result;
    }

    pub fn windowed(filter: WindowFilter) WindowFilter {
        assert(filter.is_valid());

        var result = filter;
        result.fullscreen_mode = .exclude;

        return result;
    }

    pub fn maximized(filter: WindowFilter) WindowFilter {
        assert(filter.is_valid());

        var result = filter;
        result.maximized_mode = .only;

        return result;
    }

    pub fn floating(filter: WindowFilter) WindowFilter {
        assert(filter.is_valid());

        var result = filter;
        result.maximized_mode = .exclude;

        return result;
    }

    pub fn is_active(filter: *const WindowFilter) bool {
        assert(filter.is_valid());

        const has_mode = filter.mode != .none;
        const has_fullscreen = filter.fullscreen_mode != .any;
        const has_maximized = filter.maximized_mode != .any;

        return has_mode or has_fullscreen or has_maximized;
    }

    pub fn matches(filter: *const WindowFilter) bool {
        assert(filter.is_valid());

        const hwnd = window.foreground() orelse return filter.mode == .exclude;

        if (!filter.check_fullscreen_mode(hwnd)) {
            return false;
        }

        if (!filter.check_maximized_mode(hwnd)) {
            return false;
        }

        if (filter.mode == .none) {
            return true;
        }

        const matched = filter.match_window(hwnd);

        return switch (filter.mode) {
            .none => true,
            .only => matched,
            .exclude => !matched,
        };
    }

    fn check_fullscreen_mode(filter: *const WindowFilter, hwnd: Handle) bool {
        if (filter.fullscreen_mode == .any) {
            return true;
        }

        const is_fs = window.is_fullscreen(hwnd);

        return switch (filter.fullscreen_mode) {
            .any => true,
            .only => is_fs,
            .exclude => !is_fs,
        };
    }

    fn check_maximized_mode(filter: *const WindowFilter, hwnd: Handle) bool {
        if (filter.maximized_mode == .any) {
            return true;
        }

        const is_max = window.is_maximized(hwnd);

        return switch (filter.maximized_mode) {
            .any => true,
            .only => is_max,
            .exclude => !is_max,
        };
    }

    fn match_window(filter: *const WindowFilter, hwnd: Handle) bool {
        if (filter.class_len > 0) {
            if (filter.match_class(hwnd)) {
                return true;
            }
        }

        if (filter.title_len > 0) {
            if (filter.match_title(hwnd)) {
                return true;
            }
        }

        return false;
    }

    fn match_class(filter: *const WindowFilter, hwnd: Handle) bool {
        assert(filter.class_len > 0);
        assert(filter.class_len <= length_max);

        const target = filter.class.?[0..filter.class_len];

        return window.class_matches(hwnd, target);
    }

    fn match_title(filter: *const WindowFilter, hwnd: Handle) bool {
        assert(filter.title_len > 0);
        assert(filter.title_len <= length_max);

        const target = filter.title.?[0..filter.title_len];

        return window.title_matches(hwnd, target);
    }
};

const testing = std.testing;

test "a filter mode reports whether it is valid" {
    try testing.expect(Mode.none.is_valid());
    try testing.expect(Mode.only.is_valid());
    try testing.expect(Mode.exclude.is_valid());
}

test "the window filter modes are stable" {
    try testing.expectEqual(@as(u2, 0), @intFromEnum(Mode.none));
    try testing.expectEqual(@as(u2, 1), @intFromEnum(Mode.only));
    try testing.expectEqual(@as(u2, 2), @intFromEnum(Mode.exclude));
}

test "a fullscreen mode reports whether it is valid" {
    try testing.expect(FullscreenMode.any.is_valid());
    try testing.expect(FullscreenMode.only.is_valid());
    try testing.expect(FullscreenMode.exclude.is_valid());
}

test "the fullscreen modes are stable" {
    try testing.expectEqual(@as(u2, 0), @intFromEnum(FullscreenMode.any));
    try testing.expectEqual(@as(u2, 1), @intFromEnum(FullscreenMode.only));
    try testing.expectEqual(@as(u2, 2), @intFromEnum(FullscreenMode.exclude));
}

test "a maximized mode reports whether it is valid" {
    try testing.expect(MaximizedMode.any.is_valid());
    try testing.expect(MaximizedMode.only.is_valid());
    try testing.expect(MaximizedMode.exclude.is_valid());
}

test "the maximized modes are stable" {
    try testing.expectEqual(@as(u2, 0), @intFromEnum(MaximizedMode.any));
    try testing.expectEqual(@as(u2, 1), @intFromEnum(MaximizedMode.only));
    try testing.expectEqual(@as(u2, 2), @intFromEnum(MaximizedMode.exclude));
}

test "a fresh window filter narrows nothing" {
    const f = WindowFilter.init();

    try testing.expect(f.is_valid());
    try testing.expect(f.class == null);
    try testing.expect(f.title == null);
    try testing.expectEqual(@as(u8, 0), f.class_len);
    try testing.expectEqual(@as(u8, 0), f.title_len);
    try testing.expectEqual(Mode.none, f.mode);
    try testing.expectEqual(FullscreenMode.any, f.fullscreen_mode);
    try testing.expectEqual(MaximizedMode.any, f.maximized_mode);
}

test "a default window filter is valid" {
    const f = WindowFilter{};

    try testing.expect(f.is_valid());
}

test "a window filter narrows to a class" {
    const f = comptime WindowFilter.for_class("Notepad");

    try testing.expect(f.is_valid());
    try testing.expect(f.class != null);
    try testing.expectEqual(@as(u8, 7), f.class_len);
    try testing.expectEqual(Mode.only, f.mode);
    try testing.expectEqualStrings("Notepad", f.class.?[0..f.class_len]);
}

test "a window filter narrows to a title" {
    const f = comptime WindowFilter.for_title("My Window");

    try testing.expect(f.is_valid());
    try testing.expect(f.title != null);
    try testing.expectEqual(@as(u8, 9), f.title_len);
    try testing.expectEqual(Mode.only, f.mode);
    try testing.expectEqualStrings("My Window", f.title.?[0..f.title_len]);
}

test "a window filter excludes a class" {
    const f = comptime WindowFilter.exclude_class("Chrome");

    try testing.expect(f.is_valid());
    try testing.expect(f.class != null);
    try testing.expectEqual(Mode.exclude, f.mode);
    try testing.expectEqualStrings("Chrome", f.class.?[0..f.class_len]);
}

test "a window filter excludes a title" {
    const f = comptime WindowFilter.exclude_title("Blocked");

    try testing.expect(f.is_valid());
    try testing.expect(f.title != null);
    try testing.expectEqual(Mode.exclude, f.mode);
    try testing.expectEqualStrings("Blocked", f.title.?[0..f.title_len]);
}

test "a window filter narrows to fullscreen windows" {
    const base = WindowFilter.init();
    const f = base.fullscreen();

    try testing.expect(f.is_valid());
    try testing.expectEqual(FullscreenMode.only, f.fullscreen_mode);
}

test "a window filter narrows to windowed windows" {
    const base = WindowFilter.init();
    const f = base.windowed();

    try testing.expect(f.is_valid());
    try testing.expectEqual(FullscreenMode.exclude, f.fullscreen_mode);
}

test "a window filter narrows to maximized windows" {
    const base = WindowFilter.init();
    const f = base.maximized();

    try testing.expect(f.is_valid());
    try testing.expectEqual(MaximizedMode.only, f.maximized_mode);
}

test "a window filter narrows to floating windows" {
    const base = WindowFilter.init();
    const f = base.floating();

    try testing.expect(f.is_valid());
    try testing.expectEqual(MaximizedMode.exclude, f.maximized_mode);
}

test "a window filter that narrows nothing is inactive" {
    const f = WindowFilter.init();

    try testing.expect(!f.is_active());
}

test "a window filter narrowing on class is active" {
    const f = comptime WindowFilter.for_class("Test");

    try testing.expect(f.is_active());
}

test "a window filter narrowing on fullscreen is active" {
    const base = WindowFilter.init();
    const f = base.fullscreen();

    try testing.expect(f.is_active());
}

test "a window filter narrowing on maximized is active" {
    const base = WindowFilter.init();
    const f = base.maximized();

    try testing.expect(f.is_active());
}

test "a window filter keeps every chained value" {
    const f = comptime WindowFilter.for_class("Game").fullscreen();

    try testing.expect(f.is_valid());
    try testing.expect(f.is_active());
    try testing.expectEqual(Mode.only, f.mode);
    try testing.expectEqual(FullscreenMode.only, f.fullscreen_mode);
}

test "a later chained value wins over an earlier one" {
    const f = comptime WindowFilter.for_class("Game").fullscreen().maximized();

    try testing.expect(f.is_valid());
    try testing.expectEqual(FullscreenMode.only, f.fullscreen_mode);
    try testing.expectEqual(MaximizedMode.only, f.maximized_mode);
}

test "filter length constants" {
    try testing.expectEqual(@as(u8, 64), length_max);
    try testing.expectEqual(@as(u16, 256), buffer_max);
}
