const std = @import("std");

const key_event = @import("../../event/key.zig");
const modifier = @import("../../modifier.zig");
const response_mod = @import("../../response.zig");
const filter_mod = @import("../../filter.zig");
const pattern_mod = @import("../pattern.zig");
const key_registry = @import("../../registry/key.zig");

const Key = key_event.Key;
const Response = response_mod.Response;
const WindowFilter = filter_mod.WindowFilter;

pub fn GroupBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        filter: WindowFilter = .{},
        is_pause_exempt: bool = false,

        pub fn init(h: *HookType) Self {
            return Self{ .hook = h };
        }

        pub fn pause_exempt(self: Self) Self {
            var result = self;
            result.is_pause_exempt = true;
            return result;
        }

        pub fn with_filter(self: Self, f: WindowFilter) Self {
            var result = self;
            result.filter = f;
            return result;
        }

        pub fn bind(self: Self, comptime pattern: []const u8) GroupBindBuilder(HookType) {
            const parsed = comptime pattern_mod.parse(pattern);

            return GroupBindBuilder(HookType){
                .hook = self.hook,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
                .filter = self.filter,
                .is_pause_exempt = self.is_pause_exempt,
            };
        }
    };
}

pub fn GroupBindBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        key: u8,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,

        pub fn with_filter(self: Self, f: WindowFilter) Self {
            var result = self;
            result.filter = f;
            return result;
        }

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), *const Key) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, k: *const Key) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed, k);
                }
            };

            return self.hook.registry.register(
                self.key,
                self.modifiers,
                wrapper.invoke,
                context,
                key_registry.Options{
                    .filter = self.filter,
                    .pause_exempt = self.is_pause_exempt,
                },
            );
        }
    };
}
