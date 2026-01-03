const std = @import("std");

const timer_mod = @import("../../registry/timer.zig");

pub fn TimerBuilder(comptime RegistryType: type) type {
    return struct {
        const Self = @This();

        registry: *RegistryType,
        interval_ms: u32,
        repeating: bool = true,

        pub fn every(r: *RegistryType, ms: u32) Self {
            return Self{
                .registry = r,
                .interval_ms = ms,
                .repeating = true,
            };
        }

        pub fn after(r: *RegistryType, ms: u32) Self {
            return Self{
                .registry = r,
                .interval_ms = ms,
                .repeating = false,
            };
        }

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context)) void,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque) void {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    callback(typed);
                }
            };

            return self.registry.register(
                self.interval_ms,
                wrapper.invoke,
                context,
                timer_mod.Options{
                    .binding_id = 0,
                    .repeat = self.repeating,
                },
            );
        }
    };
}
