const std = @import("std");

const mouse_event = @import("../event/mouse.zig");
const response = @import("../response.zig");
const filter_mod = @import("../filter.zig");
const mouse_registry = @import("../registry/mouse.zig");

const assert = std.debug.assert;

const Mouse = mouse_event.Mouse;
const MouseKind = mouse_event.Kind;
const Response = response.Response;
const WindowFilter = filter_mod.Active;

pub fn BindBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        kind: MouseKind,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, kind: MouseKind) Instance {
            return Instance{
                .hook = h,
                .kind = kind,
            };
        }

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            const id = try instance.hook.registry.register(
                instance.kind,
                wrapper.invoke,
                context,
                mouse_registry.Options{
                    .filter = instance.filter,
                },
            );

            assert(id >= 1);

            return id;
        }
    };
}

pub fn GroupBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType) Instance {
            return Instance{ .hook = h };
        }

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn bind(instance: Instance, kind: MouseKind) GroupBindBuilderType(HookType) {
            return GroupBindBuilderType(HookType){
                .hook = instance.hook,
                .kind = kind,
                .filter = instance.filter,
            };
        }
    };
}

pub fn GroupBindBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        kind: MouseKind,
        filter: WindowFilter,

        pub fn with_filter(instance: Instance, f: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;
            result.filter = f;
            return result;
        }

        pub fn on(
            instance: Instance,
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

            const id = try instance.hook.registry.register(
                instance.kind,
                wrapper.invoke,
                context,
                mouse_registry.Options{
                    .filter = instance.filter,
                },
            );

            assert(id >= 1);

            return id;
        }
    };
}
