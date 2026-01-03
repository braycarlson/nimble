const std = @import("std");

const key_event = @import("../../event/key.zig");
const modifier = @import("../../modifier.zig");
const response_mod = @import("../../response.zig");
const filter_mod = @import("../../filter.zig");
const pattern_mod = @import("../pattern.zig");
const key_registry = @import("../../registry/key.zig");
const timed_mod = @import("../../automation/timed.zig");
const repeat_mod = @import("../../automation/repeat.zig");

const Key = key_event.Key;
const Response = response_mod.Response;
const WindowFilter = filter_mod.WindowFilter;

pub fn OneShotBuilder(comptime HookType: type, comptime RegistryType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        registry: *RegistryType,
        key: u8,
        modifiers: modifier.Set,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, r: *RegistryType, comptime pattern: []const u8) Self {
            const parsed = comptime pattern_mod.parse(pattern);

            return Self{
                .hook = h,
                .registry = r,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
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
            comptime callback: fn (@TypeOf(context), *const Key) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, k: *const Key) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed, k);
                }

                fn pass_through(_: *anyopaque, _: *const Key) Response {
                    return .pass;
                }
            };

            const binding_id = try self.hook.registry.register(
                self.key,
                self.modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = self.filter,
                    .pause_exempt = false,
                },
            );

            return self.registry.register(binding_id, wrapper.invoke, context, .{});
        }
    };
}

pub fn TimedBuilder(comptime HookType: type, comptime RegistryType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        registry: *RegistryType,
        key: u8,
        modifiers: modifier.Set,
        duration_ms: u64 = 0,
        max_count: u32 = 0,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, r: *RegistryType, comptime pattern: []const u8) Self {
            const parsed = comptime pattern_mod.parse(pattern);

            return Self{
                .hook = h,
                .registry = r,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
            };
        }

        pub fn duration(self: Self, ms: u64) Self {
            var result = self;
            result.duration_ms = ms;
            return result;
        }

        pub fn count(self: Self, max: u32) Self {
            var result = self;
            result.max_count = max;
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
            comptime callback: fn (@TypeOf(context), *const Key) Response,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, k: *const Key) Response {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    return callback(typed, k);
                }

                fn pass_through(_: *anyopaque, _: *const Key) Response {
                    return .pass;
                }
            };

            const binding_id = try self.hook.registry.register(
                self.key,
                self.modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = self.filter,
                    .pause_exempt = false,
                },
            );

            var options = timed_mod.Options{};

            if (self.max_count > 0) {
                options = timed_mod.Options.count(self.max_count);
            } else if (self.duration_ms > 0) {
                options = timed_mod.Options.duration(self.duration_ms);
            } else {
                options = timed_mod.Options.toggle_mode();
            }

            return self.registry.register(binding_id, wrapper.invoke, context, options);
        }
    };
}

pub fn RepeatBuilder(comptime HookType: type, comptime RegistryType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        registry: *RegistryType,
        key: u8,
        modifiers: modifier.Set,
        interval_ms: u32 = 100,
        initial_delay_ms: u32 = 0,
        filter: WindowFilter = .{},

        pub fn init(h: *HookType, r: *RegistryType, comptime pattern: []const u8) Self {
            const parsed = comptime pattern_mod.parse(pattern);

            return Self{
                .hook = h,
                .registry = r,
                .key = parsed.key,
                .modifiers = parsed.modifiers,
            };
        }

        pub fn interval(self: Self, ms: u32) Self {
            var result = self;
            result.interval_ms = ms;
            return result;
        }

        pub fn initial_delay(self: Self, ms: u32) Self {
            var result = self;
            result.initial_delay_ms = ms;
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
            comptime callback: fn (@TypeOf(context), u32) void,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, cnt: u32) void {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    callback(typed, cnt);
                }

                fn pass_through(_: *anyopaque, _: *const Key) Response {
                    return .pass;
                }
            };

            const binding_id = try self.hook.registry.register(
                self.key,
                self.modifiers,
                wrapper.pass_through,
                context,
                key_registry.Options{
                    .filter = self.filter,
                    .pause_exempt = false,
                },
            );

            return self.registry.register(
                binding_id,
                wrapper.invoke,
                context,
                repeat_mod.Options{
                    .interval_ms = self.interval_ms,
                    .initial_delay_ms = self.initial_delay_ms,
                },
            );
        }
    };
}
