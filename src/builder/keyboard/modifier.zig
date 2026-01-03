const std = @import("std");

const key_event = @import("../../event/key.zig");
const modifier = @import("../../modifier.zig");
const response_mod = @import("../../response.zig");
const filter_mod = @import("../../filter.zig");
const key_registry = @import("../../registry/key.zig");
const timer_mod = @import("../../registry/timer.zig");
const repeat_mod = @import("../../automation/repeat.zig");

const Key = key_event.Key;
const Response = response_mod.Response;
const WindowFilter = filter_mod.WindowFilter;

pub fn ModifierBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        modifiers: modifier.Set.Args = .{},

        pub fn init(h: *HookType) Self {
            return Self{ .hook = h };
        }

        pub fn ctrl(self: Self) Self {
            var result = self;
            result.modifiers.ctrl = true;
            return result;
        }

        pub fn alt(self: Self) Self {
            var result = self;
            result.modifiers.alt = true;
            return result;
        }

        pub fn shift(self: Self) Self {
            var result = self;
            result.modifiers.shift = true;
            return result;
        }

        pub fn win(self: Self) Self {
            var result = self;
            result.modifiers.win = true;
            return result;
        }

        pub fn key(self: Self, value: u8) KeyBindBuilder(HookType) {
            return KeyBindBuilder(HookType){
                .hook = self.hook,
                .modifiers = modifier.Set.from(self.modifiers),
                .key = value,
            };
        }
    };
}

pub fn KeyBindBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        modifiers: modifier.Set,
        key: u8,
        is_pause_exempt: bool = false,
        filter: WindowFilter = .{},

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

        pub fn repeat(self: Self, interval_ms: u32) KeyRepeatChainBuilder(HookType) {
            return KeyRepeatChainBuilder(HookType){
                .hook = self.hook,
                .key = self.key,
                .modifiers = self.modifiers,
                .filter = self.filter,
                .is_pause_exempt = self.is_pause_exempt,
                .interval_ms = interval_ms,
                .initial_delay_ms = 0,
            };
        }

        pub fn timer(self: Self, interval_ms: u32) KeyTimerChainBuilder(HookType) {
            return KeyTimerChainBuilder(HookType){
                .hook = self.hook,
                .key = self.key,
                .modifiers = self.modifiers,
                .filter = self.filter,
                .is_pause_exempt = self.is_pause_exempt,
                .interval_ms = interval_ms,
                .repeating = true,
            };
        }
    };
}

pub fn KeyRepeatChainBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        key: u8,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,
        interval_ms: u32,
        initial_delay_ms: u32,

        pub fn initial_delay(self: Self, ms: u32) Self {
            var result = self;
            result.initial_delay_ms = ms;
            return result;
        }

        pub fn on(
            self: Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), u32) void,
        ) !u32 {
            const Context = std.meta.Child(@TypeOf(context));

            const wrapper = struct {
                fn invoke(ctx: *anyopaque, count: u32) void {
                    const typed: *Context = @ptrCast(@alignCast(ctx));
                    callback(typed, count);
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
                    .pause_exempt = self.is_pause_exempt,
                },
            );

            return self.hook.repeat_registry.register(
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

pub fn KeyTimerChainBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        key: u8,
        modifiers: modifier.Set,
        filter: WindowFilter,
        is_pause_exempt: bool,
        interval_ms: u32,
        repeating: bool,

        pub fn once(self: Self) Self {
            var result = self;
            result.repeating = false;
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
                    .pause_exempt = self.is_pause_exempt,
                },
            );

            return self.hook.timer_registry.register(
                self.interval_ms,
                wrapper.invoke,
                context,
                timer_mod.Options{
                    .binding_id = binding_id,
                    .repeat = self.repeating,
                },
            );
        }
    };
}
