const std = @import("std");
const input = @import("input");

const filter = input.filter;

const Mode = filter.Mode;
const FullscreenMode = filter.FullscreenMode;
const MaximizedMode = filter.MaximizedMode;
const WindowFilter = filter.WindowFilter;

const testing = std.testing;

test "Mode.is_valid" {
    try testing.expect(Mode.none.is_valid());
    try testing.expect(Mode.only.is_valid());
    try testing.expect(Mode.exclude.is_valid());
}

test "Mode enum values" {
    try testing.expectEqual(@as(u2, 0), @intFromEnum(Mode.none));
    try testing.expectEqual(@as(u2, 1), @intFromEnum(Mode.only));
    try testing.expectEqual(@as(u2, 2), @intFromEnum(Mode.exclude));
}

test "FullscreenMode.is_valid" {
    try testing.expect(FullscreenMode.any.is_valid());
    try testing.expect(FullscreenMode.only.is_valid());
    try testing.expect(FullscreenMode.exclude.is_valid());
}

test "FullscreenMode enum values" {
    try testing.expectEqual(@as(u2, 0), @intFromEnum(FullscreenMode.any));
    try testing.expectEqual(@as(u2, 1), @intFromEnum(FullscreenMode.only));
    try testing.expectEqual(@as(u2, 2), @intFromEnum(FullscreenMode.exclude));
}

test "MaximizedMode.is_valid" {
    try testing.expect(MaximizedMode.any.is_valid());
    try testing.expect(MaximizedMode.only.is_valid());
    try testing.expect(MaximizedMode.exclude.is_valid());
}

test "MaximizedMode enum values" {
    try testing.expectEqual(@as(u2, 0), @intFromEnum(MaximizedMode.any));
    try testing.expectEqual(@as(u2, 1), @intFromEnum(MaximizedMode.only));
    try testing.expectEqual(@as(u2, 2), @intFromEnum(MaximizedMode.exclude));
}

test "WindowFilter.init" {
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

test "WindowFilter.is_valid default" {
    const f = WindowFilter{};
    try testing.expect(f.is_valid());
}

test "WindowFilter.for_class" {
    const f = comptime WindowFilter.for_class("Notepad");

    try testing.expect(f.is_valid());
    try testing.expect(f.class != null);
    try testing.expectEqual(@as(u8, 7), f.class_len);
    try testing.expectEqual(Mode.only, f.mode);
    try testing.expectEqualStrings("Notepad", f.class.?[0..f.class_len]);
}

test "WindowFilter.for_title" {
    const f = comptime WindowFilter.for_title("My Window");

    try testing.expect(f.is_valid());
    try testing.expect(f.title != null);
    try testing.expectEqual(@as(u8, 9), f.title_len);
    try testing.expectEqual(Mode.only, f.mode);
    try testing.expectEqualStrings("My Window", f.title.?[0..f.title_len]);
}

test "WindowFilter.exclude_class" {
    const f = comptime WindowFilter.exclude_class("Chrome");

    try testing.expect(f.is_valid());
    try testing.expect(f.class != null);
    try testing.expectEqual(Mode.exclude, f.mode);
    try testing.expectEqualStrings("Chrome", f.class.?[0..f.class_len]);
}

test "WindowFilter.exclude_title" {
    const f = comptime WindowFilter.exclude_title("Blocked");

    try testing.expect(f.is_valid());
    try testing.expect(f.title != null);
    try testing.expectEqual(Mode.exclude, f.mode);
    try testing.expectEqualStrings("Blocked", f.title.?[0..f.title_len]);
}

test "WindowFilter.fullscreen" {
    const base = WindowFilter.init();
    const f = base.fullscreen();

    try testing.expect(f.is_valid());
    try testing.expectEqual(FullscreenMode.only, f.fullscreen_mode);
}

test "WindowFilter.windowed" {
    const base = WindowFilter.init();
    const f = base.windowed();

    try testing.expect(f.is_valid());
    try testing.expectEqual(FullscreenMode.exclude, f.fullscreen_mode);
}

test "WindowFilter.maximized" {
    const base = WindowFilter.init();
    const f = base.maximized();

    try testing.expect(f.is_valid());
    try testing.expectEqual(MaximizedMode.only, f.maximized_mode);
}

test "WindowFilter.floating" {
    const base = WindowFilter.init();
    const f = base.floating();

    try testing.expect(f.is_valid());
    try testing.expectEqual(MaximizedMode.exclude, f.maximized_mode);
}

test "WindowFilter.is_active none" {
    const f = WindowFilter.init();
    try testing.expect(!f.is_active());
}

test "WindowFilter.is_active with class" {
    const f = comptime WindowFilter.for_class("Test");
    try testing.expect(f.is_active());
}

test "WindowFilter.is_active with fullscreen" {
    const base = WindowFilter.init();
    const f = base.fullscreen();
    try testing.expect(f.is_active());
}

test "WindowFilter.is_active with maximized" {
    const base = WindowFilter.init();
    const f = base.maximized();
    try testing.expect(f.is_active());
}

test "WindowFilter chaining" {
    const f = comptime WindowFilter.for_class("Game").fullscreen();

    try testing.expect(f.is_valid());
    try testing.expect(f.is_active());
    try testing.expectEqual(Mode.only, f.mode);
    try testing.expectEqual(FullscreenMode.only, f.fullscreen_mode);
}

test "WindowFilter double chaining" {
    const f = comptime WindowFilter.for_class("Game").fullscreen().maximized();

    try testing.expect(f.is_valid());
    try testing.expectEqual(FullscreenMode.only, f.fullscreen_mode);
    try testing.expectEqual(MaximizedMode.only, f.maximized_mode);
}

test "filter.length_max constant" {
    try testing.expectEqual(@as(u8, 64), filter.length_max);
}

test "filter.buffer_max constant" {
    try testing.expectEqual(@as(u16, 256), filter.buffer_max);
}
