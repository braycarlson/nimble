const std = @import("std");

const response_mod = @import("../../response.zig");
const filter_mod = @import("../../filter.zig");
const chord_registry = @import("../../registry/chord.zig");

const Response = response_mod.Response;
const WindowFilter = filter_mod.WindowFilter;

pub fn ChordBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        sequence: []const u8,
        timeout_ms: u32 = chord_registry.timeout_default_ms,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, sequence: []const u8) Self {
            return Self{
                .hook = h,
                .sequence = sequence,
            };
        }

        pub fn timeout(self: Self, ms: u32) Self {
            var result = self;
            result.timeout_ms = ms;
            return result;
        }

        pub fn with_filter(self: Self, f: WindowFilter) Self {
            var result = self;
            result.filter = f;
            return result;
        }

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context)) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed);
                }
            };

            return self.hook.chord_registry.register(
                self.sequence,
                wrapper.invoke,
                context,
                chord_registry.Options{
                    .timeout_ms = self.timeout_ms,
                    .filter = self.filter,
                },
            );
        }
    };
}
