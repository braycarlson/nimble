const std = @import("std");

pub fn BaseEntry(comptime Callback: type) type {
    return struct {
        const Self = @This();

        id: u32 = 0,
        callback: ?Callback = null,
        context: ?*anyopaque = null,
        active: bool = false,

        pub fn is_active(self: *const Self) bool {
            return self.active;
        }

        pub fn set_active(self: *Self, value: bool) void {
            self.active = value;
        }

        pub fn get_id(self: *const Self) u32 {
            return self.id;
        }

        pub fn get_callback(self: *const Self) ?Callback {
            return self.callback;
        }

        pub fn get_context(self: *const Self) ?*anyopaque {
            return self.context;
        }

        pub fn is_base_valid(self: *const Self) bool {
            if (!self.active) {
                return true;
            }

            const valid_callback = self.callback != null;
            const valid_id = self.id >= 1;

            return valid_callback and valid_id;
        }

        pub fn invoke(self: *const Self, args: anytype) ?InvokeResult(Callback) {
            const callback = self.callback orelse return null;
            const context = self.context orelse return null;

            return @call(.auto, callback, .{context} ++ args);
        }

        fn InvokeResult(comptime C: type) type {
            const ptr_info = @typeInfo(C);
            const fn_info = @typeInfo(ptr_info.pointer.child);
            return fn_info.@"fn".return_type.?;
        }
    };
}

pub fn FilteredEntry(comptime Callback: type, comptime FilterType: type) type {
    return struct {
        const Self = @This();

        base: BaseEntry(Callback) = .{},
        filter: FilterType = .{},

        pub fn get_id(self: *const Self) u32 {
            return self.base.id;
        }

        pub fn get_callback(self: *const Self) ?Callback {
            return self.base.callback;
        }

        pub fn get_context(self: *const Self) ?*anyopaque {
            return self.base.context;
        }

        pub fn is_active(self: *const Self) bool {
            return self.base.active;
        }

        pub fn set_active(self: *Self, value: bool) void {
            self.base.active = value;
        }

        pub fn is_valid(self: *const Self) bool {
            return self.base.is_base_valid();
        }

        pub fn matches_filter(self: *const Self) bool {
            if (@hasDecl(FilterType, "is_active") and @hasDecl(FilterType, "matches")) {
                if (self.filter.is_active() and !self.filter.matches()) {
                    return false;
                }
            }
            return true;
        }

        pub fn invoke(self: *const Self, args: anytype) ?InvokeResult(Callback) {
            return self.base.invoke(args);
        }

        fn InvokeResult(comptime C: type) type {
            const ptr_info = @typeInfo(C);
            const fn_info = @typeInfo(ptr_info.pointer.child);
            return fn_info.@"fn".return_type.?;
        }
    };
}

pub fn BindingEntry(comptime Callback: type) type {
    return struct {
        const Self = @This();

        base: BaseEntry(Callback) = .{},
        binding_id: u32 = 0,
        enabled: bool = true,

        pub fn get_id(self: *const Self) u32 {
            return self.base.id;
        }

        pub fn get_callback(self: *const Self) ?Callback {
            return self.base.callback;
        }

        pub fn get_context(self: *const Self) ?*anyopaque {
            return self.base.context;
        }

        pub fn is_active(self: *const Self) bool {
            return self.base.active;
        }

        pub fn set_active(self: *Self, value: bool) void {
            self.base.active = value;
        }

        pub fn get_binding_id(self: *const Self) u32 {
            return self.binding_id;
        }

        pub fn is_enabled(self: *const Self) bool {
            return self.enabled;
        }

        pub fn set_enabled(self: *Self, value: bool) void {
            self.enabled = value;
        }

        pub fn is_valid(self: *const Self) bool {
            if (!self.is_active()) {
                return true;
            }

            const valid_base = self.base.is_base_valid();
            const valid_binding = self.binding_id >= 1;

            return valid_base and valid_binding;
        }

        pub fn invoke(self: *const Self, args: anytype) ?InvokeResult(Callback) {
            return self.base.invoke(args);
        }

        fn InvokeResult(comptime C: type) type {
            const ptr_info = @typeInfo(C);
            const fn_info = @typeInfo(ptr_info.pointer.child);
            return fn_info.@"fn".return_type.?;
        }
    };
}

pub fn BindingFilteredEntry(comptime Callback: type, comptime FilterType: type) type {
    return struct {
        const Self = @This();

        base: BaseEntry(Callback) = .{},
        binding_id: u32 = 0,
        filter: FilterType = .{},
        enabled: bool = true,

        pub fn get_id(self: *const Self) u32 {
            return self.base.id;
        }

        pub fn get_callback(self: *const Self) ?Callback {
            return self.base.callback;
        }

        pub fn get_context(self: *const Self) ?*anyopaque {
            return self.base.context;
        }

        pub fn is_active(self: *const Self) bool {
            return self.base.active;
        }

        pub fn set_active(self: *Self, value: bool) void {
            self.base.active = value;
        }

        pub fn get_binding_id(self: *const Self) u32 {
            return self.binding_id;
        }

        pub fn is_enabled(self: *const Self) bool {
            return self.enabled;
        }

        pub fn set_enabled(self: *Self, value: bool) void {
            self.enabled = value;
        }

        pub fn is_valid(self: *const Self) bool {
            if (!self.is_active()) {
                return true;
            }

            const valid_base = self.base.is_base_valid();
            const valid_binding = self.binding_id >= 1;

            return valid_base and valid_binding;
        }

        pub fn matches_filter(self: *const Self) bool {
            if (@hasDecl(FilterType, "is_active") and @hasDecl(FilterType, "matches")) {
                if (self.filter.is_active() and !self.filter.matches()) {
                    return false;
                }
            }
            return true;
        }

        pub fn invoke(self: *const Self, args: anytype) ?InvokeResult(Callback) {
            return self.base.invoke(args);
        }

        fn InvokeResult(comptime C: type) type {
            const ptr_info = @typeInfo(C);
            const fn_info = @typeInfo(ptr_info.pointer.child);
            return fn_info.@"fn".return_type.?;
        }
    };
}

pub fn DualBindingFilteredEntry(comptime Callback: type, comptime FilterType: type) type {
    return struct {
        const Self = @This();

        base: BaseEntry(Callback) = .{},
        action_binding_id: u32 = 0,
        toggle_binding_id: u32 = 0,
        filter: FilterType = .{},
        enabled: bool = false,

        pub fn get_id(self: *const Self) u32 {
            return self.base.id;
        }

        pub fn get_callback(self: *const Self) ?Callback {
            return self.base.callback;
        }

        pub fn get_context(self: *const Self) ?*anyopaque {
            return self.base.context;
        }

        pub fn is_active(self: *const Self) bool {
            return self.base.active;
        }

        pub fn set_active(self: *Self, value: bool) void {
            self.base.active = value;
        }

        pub fn get_action_binding_id(self: *const Self) u32 {
            return self.action_binding_id;
        }

        pub fn get_toggle_binding_id(self: *const Self) u32 {
            return self.toggle_binding_id;
        }

        pub fn is_enabled(self: *const Self) bool {
            return self.enabled;
        }

        pub fn set_enabled(self: *Self, value: bool) void {
            self.enabled = value;
        }

        pub fn is_valid(self: *const Self) bool {
            if (!self.is_active()) {
                return true;
            }

            const valid_base = self.base.is_base_valid();
            const valid_action_binding = self.action_binding_id >= 1;
            const valid_toggle_binding = self.toggle_binding_id >= 1;

            return valid_base and valid_action_binding and valid_toggle_binding;
        }

        pub fn matches_filter(self: *const Self) bool {
            if (@hasDecl(FilterType, "is_active") and @hasDecl(FilterType, "matches")) {
                if (self.filter.is_active() and !self.filter.matches()) {
                    return false;
                }
            }
            return true;
        }

        pub fn invoke(self: *const Self, args: anytype) ?InvokeResult(Callback) {
            return self.base.invoke(args);
        }

        fn InvokeResult(comptime C: type) type {
            const ptr_info = @typeInfo(C);
            const fn_info = @typeInfo(ptr_info.pointer.child);
            return fn_info.@"fn".return_type.?;
        }
    };
}
