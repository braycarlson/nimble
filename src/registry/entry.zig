const std = @import("std");

pub fn BaseEntryType(comptime Callback: type) type {
    return struct {
        const Instance = @This();

        id: u32 = 0,
        callback: ?Callback = null,
        context: ?*anyopaque = null,
        active: bool = false,

        pub fn is_active(instance: *const Instance) bool {
            return instance.active;
        }

        pub fn set_active(instance: *Instance, value: bool) void {
            instance.active = value;
        }

        pub fn get_id(instance: *const Instance) u32 {
            return instance.id;
        }

        pub fn get_callback(instance: *const Instance) ?Callback {
            return instance.callback;
        }

        pub fn get_context(instance: *const Instance) ?*anyopaque {
            return instance.context;
        }

        pub fn is_base_valid(instance: *const Instance) bool {
            if (!instance.active) {
                return true;
            }

            const valid_callback = instance.callback != null;
            const valid_id = instance.id >= 1;

            return valid_callback and valid_id;
        }

        pub fn invoke(instance: *const Instance, args: anytype) ?InvokeResultType(Callback) {
            const callback = instance.callback orelse return null;
            const context = instance.context orelse return null;

            return @call(.auto, callback, .{context} ++ args);
        }

        fn InvokeResultType(comptime C: type) type {
            const ptr_info = @typeInfo(C);
            const fn_info = @typeInfo(ptr_info.pointer.child);

            return fn_info.@"fn".return_type.?;
        }
    };
}

pub fn FilteredEntryType(comptime Callback: type, comptime FilterType: type) type {
    return struct {
        const Instance = @This();

        base: BaseEntryType(Callback) = .{},
        filter: FilterType = .{},

        pub fn get_id(instance: *const Instance) u32 {
            return instance.base.id;
        }

        pub fn get_callback(instance: *const Instance) ?Callback {
            return instance.base.callback;
        }

        pub fn get_context(instance: *const Instance) ?*anyopaque {
            return instance.base.context;
        }

        pub fn is_active(instance: *const Instance) bool {
            return instance.base.active;
        }

        pub fn set_active(instance: *Instance, value: bool) void {
            instance.base.active = value;
        }

        pub fn is_valid(instance: *const Instance) bool {
            return instance.base.is_base_valid();
        }

        pub fn matches_filter(instance: *const Instance) bool {
            if (@hasDecl(FilterType, "is_active") and @hasDecl(FilterType, "matches")) {
                if (instance.filter.is_active() and !instance.filter.matches()) {
                    return false;
                }
            }
            return true;
        }

        pub fn invoke(instance: *const Instance, args: anytype) ?InvokeResultType(Callback) {
            return instance.base.invoke(args);
        }

        fn InvokeResultType(comptime C: type) type {
            const ptr_info = @typeInfo(C);
            const fn_info = @typeInfo(ptr_info.pointer.child);

            return fn_info.@"fn".return_type.?;
        }
    };
}

pub fn BindingEntryType(comptime Callback: type) type {
    return struct {
        const Instance = @This();

        base: BaseEntryType(Callback) = .{},
        binding_id: u32 = 0,
        enabled: bool = true,

        pub fn get_id(instance: *const Instance) u32 {
            return instance.base.id;
        }

        pub fn get_callback(instance: *const Instance) ?Callback {
            return instance.base.callback;
        }

        pub fn get_context(instance: *const Instance) ?*anyopaque {
            return instance.base.context;
        }

        pub fn is_active(instance: *const Instance) bool {
            return instance.base.active;
        }

        pub fn set_active(instance: *Instance, value: bool) void {
            instance.base.active = value;
        }

        pub fn get_binding_id(instance: *const Instance) u32 {
            return instance.binding_id;
        }

        pub fn is_enabled(instance: *const Instance) bool {
            return instance.enabled;
        }

        pub fn set_enabled(instance: *Instance, value: bool) void {
            instance.enabled = value;
        }

        pub fn is_valid(instance: *const Instance) bool {
            if (!instance.is_active()) {
                return true;
            }

            const valid_base = instance.base.is_base_valid();
            const valid_binding = instance.binding_id >= 1;

            return valid_base and valid_binding;
        }

        pub fn invoke(instance: *const Instance, args: anytype) ?InvokeResultType(Callback) {
            return instance.base.invoke(args);
        }

        fn InvokeResultType(comptime C: type) type {
            const ptr_info = @typeInfo(C);
            const fn_info = @typeInfo(ptr_info.pointer.child);

            return fn_info.@"fn".return_type.?;
        }
    };
}

pub fn BindingFilteredEntryType(comptime Callback: type, comptime FilterType: type) type {
    return struct {
        const Instance = @This();

        base: BaseEntryType(Callback) = .{},
        binding_id: u32 = 0,
        filter: FilterType = .{},
        enabled: bool = true,

        pub fn get_id(instance: *const Instance) u32 {
            return instance.base.id;
        }

        pub fn get_callback(instance: *const Instance) ?Callback {
            return instance.base.callback;
        }

        pub fn get_context(instance: *const Instance) ?*anyopaque {
            return instance.base.context;
        }

        pub fn is_active(instance: *const Instance) bool {
            return instance.base.active;
        }

        pub fn set_active(instance: *Instance, value: bool) void {
            instance.base.active = value;
        }

        pub fn get_binding_id(instance: *const Instance) u32 {
            return instance.binding_id;
        }

        pub fn is_enabled(instance: *const Instance) bool {
            return instance.enabled;
        }

        pub fn set_enabled(instance: *Instance, value: bool) void {
            instance.enabled = value;
        }

        pub fn is_valid(instance: *const Instance) bool {
            if (!instance.is_active()) {
                return true;
            }

            const valid_base = instance.base.is_base_valid();
            const valid_binding = instance.binding_id >= 1;

            return valid_base and valid_binding;
        }

        pub fn matches_filter(instance: *const Instance) bool {
            if (@hasDecl(FilterType, "is_active") and @hasDecl(FilterType, "matches")) {
                if (instance.filter.is_active() and !instance.filter.matches()) {
                    return false;
                }
            }
            return true;
        }

        pub fn invoke(instance: *const Instance, args: anytype) ?InvokeResultType(Callback) {
            return instance.base.invoke(args);
        }

        fn InvokeResultType(comptime C: type) type {
            const ptr_info = @typeInfo(C);
            const fn_info = @typeInfo(ptr_info.pointer.child);

            return fn_info.@"fn".return_type.?;
        }
    };
}

pub fn DualBindingFilteredEntryType(comptime Callback: type, comptime FilterType: type) type {
    return struct {
        const Instance = @This();

        base: BaseEntryType(Callback) = .{},
        action_binding_id: u32 = 0,
        toggle_binding_id: u32 = 0,
        filter: FilterType = .{},
        enabled: bool = false,

        pub fn get_id(instance: *const Instance) u32 {
            return instance.base.id;
        }

        pub fn get_callback(instance: *const Instance) ?Callback {
            return instance.base.callback;
        }

        pub fn get_context(instance: *const Instance) ?*anyopaque {
            return instance.base.context;
        }

        pub fn is_active(instance: *const Instance) bool {
            return instance.base.active;
        }

        pub fn set_active(instance: *Instance, value: bool) void {
            instance.base.active = value;
        }

        pub fn get_action_binding_id(instance: *const Instance) u32 {
            return instance.action_binding_id;
        }

        pub fn get_toggle_binding_id(instance: *const Instance) u32 {
            return instance.toggle_binding_id;
        }

        pub fn is_enabled(instance: *const Instance) bool {
            return instance.enabled;
        }

        pub fn set_enabled(instance: *Instance, value: bool) void {
            instance.enabled = value;
        }

        pub fn is_valid(instance: *const Instance) bool {
            if (!instance.is_active()) {
                return true;
            }

            const valid_base = instance.base.is_base_valid();
            const valid_action_binding = instance.action_binding_id >= 1;
            const valid_toggle_binding = instance.toggle_binding_id >= 1;

            return valid_base and valid_action_binding and valid_toggle_binding;
        }

        pub fn matches_filter(instance: *const Instance) bool {
            if (@hasDecl(FilterType, "is_active") and @hasDecl(FilterType, "matches")) {
                if (instance.filter.is_active() and !instance.filter.matches()) {
                    return false;
                }
            }
            return true;
        }

        pub fn invoke(instance: *const Instance, args: anytype) ?InvokeResultType(Callback) {
            return instance.base.invoke(args);
        }

        fn InvokeResultType(comptime C: type) type {
            const ptr_info = @typeInfo(C);
            const fn_info = @typeInfo(ptr_info.pointer.child);

            return fn_info.@"fn".return_type.?;
        }
    };
}

const filter_mod = @import("../filter.zig");

const WindowFilter = filter_mod.Active;

const testing = std.testing;

fn dummy_callback(_: *anyopaque) void {}

test "a default base entry is inactive and unbound" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntryType(Callback);
    const entry = Entry{};

    try testing.expectEqual(@as(u32, 0), entry.id);
    try testing.expect(entry.callback == null);
    try testing.expect(entry.context == null);
    try testing.expect(!entry.active);
}

test "a base entry carries the id it was built from" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntryType(Callback);
    const entry = Entry{ .id = 123 };

    try testing.expectEqual(@as(u32, 123), entry.get_id());
}

test "a base entry carries its callback" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntryType(Callback);
    const entry = Entry{ .callback = dummy_callback };

    try testing.expect(entry.get_callback() != null);
    try testing.expectEqual(dummy_callback, entry.get_callback().?);
}

test "a base entry can carry no callback" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntryType(Callback);
    const entry = Entry{};

    try testing.expect(entry.get_callback() == null);
}

test "a base entry carries its context" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntryType(Callback);
    var ctx: u32 = 42;
    const entry = Entry{ .context = &ctx };

    try testing.expect(entry.get_context() != null);
}

test "a base entry can carry no context" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntryType(Callback);
    const entry = Entry{};

    try testing.expect(entry.get_context() == null);
}

test "a base entry reports whether it is active" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntryType(Callback);

    const inactive = Entry{};
    const active = Entry{ .active = true };

    try testing.expect(!inactive.is_active());
    try testing.expect(active.is_active());
}

test "an inactive base entry is not valid" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntryType(Callback);
    const entry = Entry{};

    try testing.expect(entry.is_base_valid());
}

test "an active base entry with a callback and an id is valid" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntryType(Callback);
    var ctx: u32 = 0;

    const entry = Entry{
        .id = 1,
        .callback = dummy_callback,
        .context = &ctx,
        .active = true,
    };

    try testing.expect(entry.is_base_valid());
}

test "an active base entry without a callback is not valid" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntryType(Callback);

    const entry = Entry{
        .id = 1,
        .callback = null,
        .active = true,
    };

    try testing.expect(!entry.is_base_valid());
}

test "an active base entry with a zero id is not valid" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BaseEntryType(Callback);
    var ctx: u32 = 0;

    const entry = Entry{
        .id = 0,
        .callback = dummy_callback,
        .context = &ctx,
        .active = true,
    };

    try testing.expect(!entry.is_base_valid());
}

test "a default filtered entry carries no filter" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = FilteredEntryType(Callback, WindowFilter);
    const entry = Entry{};

    try testing.expect(!entry.is_active());
    try testing.expect(!entry.filter.is_active());
    try testing.expect(entry.matches_filter());
}

test "a filtered entry carries the id it was built from" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = FilteredEntryType(Callback, WindowFilter);
    const entry = Entry{ .base = .{ .id = 456 } };

    try testing.expectEqual(@as(u32, 456), entry.get_id());
}

test "a filtered entry reports whether it is active" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = FilteredEntryType(Callback, WindowFilter);

    const inactive = Entry{};
    const active = Entry{ .base = .{ .active = true } };

    try testing.expect(!inactive.is_active());
    try testing.expect(active.is_active());
}

test "an inactive filtered entry is not valid" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = FilteredEntryType(Callback, WindowFilter);
    const entry = Entry{};

    try testing.expect(entry.is_valid());
}

test "an active filtered entry with a callback and an id is valid" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = FilteredEntryType(Callback, WindowFilter);
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

test "a filtered entry carries the filter its backend supports" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = FilteredEntryType(Callback, WindowFilter);

    try testing.expectEqual(WindowFilter, @FieldType(Entry, "filter"));
    try testing.expectEqual(filter_mod.Active, @FieldType(Entry, "filter"));
}

test "a default binding entry carries no binding" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntryType(Callback);
    const entry = Entry{};

    try testing.expect(!entry.is_active());
    try testing.expectEqual(@as(u32, 0), entry.binding_id);
}

test "a binding entry carries its binding id" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntryType(Callback);
    const entry = Entry{ .binding_id = 789 };

    try testing.expectEqual(@as(u32, 789), entry.get_binding_id());
}

test "a binding entry reports whether it is active" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntryType(Callback);

    const inactive = Entry{};
    const active = Entry{ .base = .{ .active = true } };

    try testing.expect(!inactive.is_active());
    try testing.expect(active.is_active());
}

test "a binding entry reports whether it is enabled" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntryType(Callback);

    var entry = Entry{ .base = .{ .active = true } };

    try testing.expect(entry.is_enabled());

    entry.set_enabled(false);

    try testing.expect(!entry.is_enabled());
}

test "enabling a binding entry updates its flag" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntryType(Callback);

    var entry = Entry{ .base = .{ .active = true } };

    entry.set_enabled(false);
    try testing.expect(!entry.is_enabled());

    entry.set_enabled(true);
    try testing.expect(entry.is_enabled());
}

test "an inactive binding entry is not valid" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntryType(Callback);
    const entry = Entry{};

    try testing.expect(entry.is_valid());
}

test "an active binding entry with a callback and an id is valid" {
    const Callback = *const fn (*anyopaque) void;
    const Entry = BindingEntryType(Callback);
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
