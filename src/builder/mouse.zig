const std = @import("std");

const mouse_event = @import("../event/mouse.zig");
const response_mod = @import("../response.zig");
const filter_mod = @import("../filter.zig");
const mouse_registry = @import("../registry/mouse.zig");

const Mouse = mouse_event.Mouse;
const MouseKind = mouse_event.Kind;
const Response = response_mod.Response;
const WindowFilter = filter_mod.WindowFilter;

pub fn BindBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        kind: MouseKind,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, kind: MouseKind) Self {
            return Self{
                .hook = h,
                .kind = kind,
            };
        }

        pub fn with_filter(self: Self, f: WindowFilter) Self {
            var result = self;
            result.filter = f;
            return result;
        }

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), *const Mouse) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, mouse: *const Mouse) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed, mouse);
                }
            };

            return self.hook.registry.register(
                self.kind,
                wrapper.invoke,
                context,
                mouse_registry.Options{
                    .filter = self.filter,
                },
            );
        }
    };
}

pub fn GroupBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType) Self {
            return Self{ .hook = h };
        }

        pub fn with_filter(self: Self, f: WindowFilter) Self {
            var result = self;
            result.filter = f;
            return result;
        }

        pub fn bind(self: Self, kind: MouseKind) GroupBindBuilder(HookType) {
            return GroupBindBuilder(HookType){
                .hook = self.hook,
                .kind = kind,
                .filter = self.filter,
            };
        }
    };
}

pub fn GroupBindBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        kind: MouseKind,
        filter: WindowFilter,

        pub fn with_filter(self: Self, f: WindowFilter) Self {
            var result = self;
            result.filter = f;
            return result;
        }

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), *const Mouse) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, mouse: *const Mouse) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed, mouse);
                }
            };

            return self.hook.registry.register(
                self.kind,
                wrapper.invoke,
                context,
                mouse_registry.Options{
                    .filter = self.filter,
                },
            );
        }
    };
}
