const std = @import("std");

const response_mod = @import("../../response.zig");

const Response = response_mod.Response;

pub fn CommandBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        name: []const u8,

        pub fn init(h: *HookType, name: []const u8) Self {
            return Self{
                .hook = h,
                .name = name,
            };
        }

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), []const u8, []const u8) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, name: []const u8, args: []const u8) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed, name, args);
                }
            };

            return self.hook.command_registry.register(self.name, wrapper.invoke, context);
        }

        pub fn on_simple(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context)) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, _: []const u8, _: []const u8) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed);
                }
            };

            return self.hook.command_registry.register(self.name, wrapper.invoke, context);
        }
    };
}
