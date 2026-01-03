const std = @import("std");

const w32 = @import("win32").everything;

const window = @import("window.zig");

pub const length_max: u8 = 64;
pub const buffer_max: u16 = 256;

pub const Mode = enum(u2) {
    none = 0,
    only = 1,
    exclude = 2,

    pub fn is_valid(self: Mode) bool {
        const value = @intFromEnum(self);
        return value <= 2;
    }
};

pub const FullscreenMode = enum(u2) {
    any = 0,
    only = 1,
    exclude = 2,

    pub fn is_valid(self: FullscreenMode) bool {
        const value = @intFromEnum(self);
        return value <= 2;
    }
};

pub const MaximizedMode = enum(u2) {
    any = 0,
    only = 1,
    exclude = 2,

    pub fn is_valid(self: MaximizedMode) bool {
        const value = @intFromEnum(self);
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

    pub fn is_valid(self: *const WindowFilter) bool {
        const valid_mode = self.mode.is_valid();
        const valid_fullscreen = self.fullscreen_mode.is_valid();
        const valid_maximized = self.maximized_mode.is_valid();
        const valid_class_len = self.class_len <= length_max;
        const valid_title_len = self.title_len <= length_max;

        return valid_mode and valid_fullscreen and valid_maximized and valid_class_len and valid_title_len;
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

    pub fn fullscreen(self: WindowFilter) WindowFilter {
        std.debug.assert(self.is_valid());

        var result = self;
        result.fullscreen_mode = .only;

        return result;
    }

    pub fn windowed(self: WindowFilter) WindowFilter {
        std.debug.assert(self.is_valid());

        var result = self;
        result.fullscreen_mode = .exclude;

        return result;
    }

    pub fn maximized(self: WindowFilter) WindowFilter {
        std.debug.assert(self.is_valid());

        var result = self;
        result.maximized_mode = .only;

        return result;
    }

    pub fn floating(self: WindowFilter) WindowFilter {
        std.debug.assert(self.is_valid());

        var result = self;
        result.maximized_mode = .exclude;

        return result;
    }

    pub fn is_active(self: *const WindowFilter) bool {
        std.debug.assert(self.is_valid());

        const has_mode = self.mode != .none;
        const has_fullscreen = self.fullscreen_mode != .any;
        const has_maximized = self.maximized_mode != .any;

        return has_mode or has_fullscreen or has_maximized;
    }

    pub fn matches(self: *const WindowFilter) bool {
        std.debug.assert(self.is_valid());

        const hwnd = w32.GetForegroundWindow() orelse return self.mode == .exclude;

        if (!self.check_fullscreen_mode(hwnd)) {
            return false;
        }

        if (!self.check_maximized_mode(hwnd)) {
            return false;
        }

        if (self.mode == .none) {
            return true;
        }

        const matched = self.match_window(hwnd);

        return switch (self.mode) {
            .none => true,
            .only => matched,
            .exclude => !matched,
        };
    }

    fn check_fullscreen_mode(self: *const WindowFilter, hwnd: w32.HWND) bool {
        if (self.fullscreen_mode == .any) {
            return true;
        }

        const is_fs = window.is_fullscreen(hwnd);

        return switch (self.fullscreen_mode) {
            .any => true,
            .only => is_fs,
            .exclude => !is_fs,
        };
    }

    fn check_maximized_mode(self: *const WindowFilter, hwnd: w32.HWND) bool {
        if (self.maximized_mode == .any) {
            return true;
        }

        const is_max = window.is_maximized(hwnd);

        return switch (self.maximized_mode) {
            .any => true,
            .only => is_max,
            .exclude => !is_max,
        };
    }

    fn match_window(self: *const WindowFilter, hwnd: w32.HWND) bool {
        if (self.class_len > 0) {
            if (self.match_class(hwnd)) {
                return true;
            }
        }

        if (self.title_len > 0) {
            if (self.match_title(hwnd)) {
                return true;
            }
        }

        return false;
    }

    fn match_class(self: *const WindowFilter, hwnd: w32.HWND) bool {
        std.debug.assert(self.class_len > 0);
        std.debug.assert(self.class_len <= length_max);

        const target = self.class.?[0..self.class_len];

        return window.class_matches(hwnd, target);
    }

    fn match_title(self: *const WindowFilter, hwnd: w32.HWND) bool {
        std.debug.assert(self.title_len > 0);
        std.debug.assert(self.title_len <= length_max);

        const target = self.title.?[0..self.title_len];

        return window.title_matches(hwnd, target);
    }
};
