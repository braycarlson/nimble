const std = @import("std");

const filter_mod = @import("../../filter.zig");
const sequence_registry = @import("../../registry/sequence.zig");

const WindowFilter = filter_mod.WindowFilter;

pub fn SequenceBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        pattern: []const u8,
        filter: WindowFilter = .{},
        is_block_exempt: bool = false,

        pub fn init(h: *HookType, pattern: []const u8) Self {
            return Self{
                .hook = h,
                .pattern = pattern,
            };
        }

        pub fn block_exempt(self: Self) Self {
            var result = self;
            result.is_block_exempt = true;
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
            comptime callback: fn (@TypeOf(context)) void,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque) void {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    callback(typed);
                }
            };

            return self.hook.sequence_registry.register(
                self.pattern,
                wrapper.invoke,
                context,
                sequence_registry.Options{
                    .filter = self.filter,
                    .block_exempt = self.is_block_exempt,
                },
            );
        }
    };
}
