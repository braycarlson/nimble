const std = @import("std");
const input = @import("input");

const entry_mod = input.registry.entry;
const filter_mod = input.filter;
const modifier = input.modifier;

const BaseEntry = entry_mod.BaseEntry;
const FilteredEntry = entry_mod.FilteredEntry;
const BindingEntry = entry_mod.BindingEntry;
const WindowFilter = filter_mod.WindowFilter;

const testing = std.testing;

fn dummy_callback(_: *anyopaque) void {}

test "BaseEntry default" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntry(Callback);
    const entry = Entry{};

    try testing.expectEqual(@as(u32, 0), entry.id);
    try testing.expect(entry.callback == null);
    try testing.expect(entry.context == null);
    try testing.expect(!entry.active);
}

test "BaseEntry.get_id" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntry(Callback);
    const entry = Entry{ .id = 123 };

    try testing.expectEqual(@as(u32, 123), entry.get_id());
}

test "BaseEntry.get_callback" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntry(Callback);
    const entry = Entry{ .callback = dummy_callback };

    try testing.expect(entry.get_callback() != null);
    try testing.expectEqual(dummy_callback, entry.get_callback().?);
}

test "BaseEntry.get_callback null" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntry(Callback);
    const entry = Entry{};

    try testing.expect(entry.get_callback() == null);
}

test "BaseEntry.get_context" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntry(Callback);
    var ctx: u32 = 42;
    const entry = Entry{ .context = &ctx };

    try testing.expect(entry.get_context() != null);
}

test "BaseEntry.get_context null" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntry(Callback);
    const entry = Entry{};

    try testing.expect(entry.get_context() == null);
}

test "BaseEntry.is_active" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntry(Callback);

    const inactive = Entry{};
    const active = Entry{ .active = true };

    try testing.expect(!inactive.is_active());
    try testing.expect(active.is_active());
}

test "BaseEntry.is_base_valid inactive" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntry(Callback);
    const entry = Entry{};

    try testing.expect(entry.is_base_valid());
}

test "BaseEntry.is_base_valid active valid" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntry(Callback);
    var ctx: u32 = 0;
    const entry = Entry{
        .id = 1,
        .callback = dummy_callback,
        .context = &ctx,
        .active = true,
    };

    try testing.expect(entry.is_base_valid());
}

test "BaseEntry.is_base_valid active no callback" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntry(Callback);
    const entry = Entry{
        .id = 1,
        .callback = null,
        .active = true,
    };

    try testing.expect(!entry.is_base_valid());
}

test "BaseEntry.is_base_valid active id zero" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntry(Callback);
    var ctx: u32 = 0;
    const entry = Entry{
        .id = 0,
        .callback = dummy_callback,
        .context = &ctx,
        .active = true,
    };

    try testing.expect(!entry.is_base_valid());
}

test "FilteredEntry default" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = FilteredEntry(Callback, WindowFilter);
    const entry = Entry{};

    try testing.expect(!entry.is_active());
    try testing.expect(entry.filter.mode == .none);
}

test "FilteredEntry.get_id" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = FilteredEntry(Callback, WindowFilter);
    const entry = Entry{ .base = .{ .id = 456 } };

    try testing.expectEqual(@as(u32, 456), entry.get_id());
}

test "FilteredEntry.is_active" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = FilteredEntry(Callback, WindowFilter);

    const inactive = Entry{};
    const active = Entry{ .base = .{ .active = true } };

    try testing.expect(!inactive.is_active());
    try testing.expect(active.is_active());
}

test "FilteredEntry.is_valid inactive" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = FilteredEntry(Callback, WindowFilter);
    const entry = Entry{};

    try testing.expect(entry.is_valid());
}

test "FilteredEntry.is_valid active valid" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = FilteredEntry(Callback, WindowFilter);
    var ctx: u32 = 0;
    const entry = Entry{
        .base = .{
            .id = 1,
            .callback = dummy_callback,
            .context = &ctx,
            .active = true,
        },
        .filter = WindowFilter{},
    };

    try testing.expect(entry.is_valid());
}

test "FilteredEntry with filter" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = FilteredEntry(Callback, WindowFilter);
    var ctx: u32 = 0;
    const entry = Entry{
        .base = .{
            .id = 1,
            .callback = dummy_callback,
            .context = &ctx,
            .active = true,
        },
        .filter = WindowFilter.for_class("Notepad"),
    };

    try testing.expect(entry.is_valid());
    try testing.expect(entry.filter.is_active());
}

test "BindingEntry default" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntry(Callback);
    const entry = Entry{};

    try testing.expect(!entry.is_active());
    try testing.expectEqual(@as(u32, 0), entry.binding_id);
}

test "BindingEntry.get_binding_id" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntry(Callback);
    const entry = Entry{ .binding_id = 789 };

    try testing.expectEqual(@as(u32, 789), entry.get_binding_id());
}

test "BindingEntry.is_active" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntry(Callback);

    const inactive = Entry{};
    const active = Entry{ .base = .{ .active = true } };

    try testing.expect(!inactive.is_active());
    try testing.expect(active.is_active());
}

test "BindingEntry.is_enabled" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntry(Callback);

    var entry = Entry{ .base = .{ .active = true } };

    try testing.expect(entry.is_enabled());

    entry.set_enabled(false);

    try testing.expect(!entry.is_enabled());
}

test "BindingEntry.set_enabled" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntry(Callback);

    var entry = Entry{ .base = .{ .active = true } };

    entry.set_enabled(false);
    try testing.expect(!entry.is_enabled());

    entry.set_enabled(true);
    try testing.expect(entry.is_enabled());
}

test "BindingEntry.is_valid inactive" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntry(Callback);
    const entry = Entry{};

    try testing.expect(entry.is_valid());
}

test "BindingEntry.is_valid active valid" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntry(Callback);
    var ctx: u32 = 0;
    const entry = Entry{
        .base = .{
            .id = 1,
            .callback = dummy_callback,
            .context = &ctx,
            .active = true,
        },
        .binding_id = 10,
    };

    try testing.expect(entry.is_valid());
}
