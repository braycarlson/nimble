const std = @import("std");

const key_event = @import("../../event/key.zig");
const modifier = @import("../../modifier.zig");
const response_mod = @import("../../response.zig");
const filter_mod = @import("../../filter.zig");
const pattern_mod = @import("../pattern.zig");
const macro_mod = @import("../../automation/macro.zig");
const key_registry = @import("../../registry/key.zig");

const Key = key_event.Key;
const Response = response_mod.Response;
const WindowFilter = filter_mod.WindowFilter;
const Action = macro_mod.Action;

const MaxSteps = 32;

const StepKind = enum {
    text,
    line,
    key,
    delay,
};

const Step = struct {
    kind: StepKind = .text,
    text: ?[]const u8 = null,
    keycode: u8 = 0,
    key_modifiers: modifier.Set = .{},
    delay_ms: u32 = 0,
};

pub fn MacroBuilder(comptime HookType: type) type {
    return struct {
        const Self = @This();

        hook: *HookType,
        name: []const u8,
        steps: [MaxSteps]Step = [_]Step{.{}} ** MaxSteps,
        step_count: u32 = 0,
        binding_key: ?u8 = null,
        binding_modifiers: modifier.Set = .{},
        filter: WindowFilter = .{},
        is_pause_exempt: bool = false,

        pub fn init(h: *HookType, name: []const u8) Self {
            return Self{
                .hook = h,
                .name = name,
            };
        }

        pub fn text(self: Self, txt: []const u8) Self {
            var result = self;
            if (result.step_count < MaxSteps) {
                result.steps[result.step_count] = .{
                    .kind = .text,
                    .text = txt,
                };
                result.step_count += 1;
            }
            return result;
        }

        pub fn line(self: Self, txt: []const u8) Self {
            var result = self;
            if (result.step_count < MaxSteps) {
                result.steps[result.step_count] = .{
                    .kind = .line,
                    .text = txt,
                };
                result.step_count += 1;
            }
            return result;
        }

        pub fn key(self: Self, comptime pattern: []const u8) Self {
            const parsed = comptime pattern_mod.parse(pattern);
            var result = self;
            if (result.step_count < MaxSteps) {
                result.steps[result.step_count] = .{
                    .kind = .key,
                    .keycode = parsed.key,
                    .key_modifiers = parsed.modifiers,
                };
                result.step_count += 1;
            }
            return result;
        }

        pub fn delay(self: Self, ms: u32) Self {
            var result = self;
            if (result.step_count < MaxSteps) {
                result.steps[result.step_count] = .{
                    .kind = .delay,
                    .delay_ms = ms,
                };
                result.step_count += 1;
            }
            return result;
        }

        pub fn bind(self: Self, comptime pattern: []const u8) Self {
            const parsed = comptime pattern_mod.parse(pattern);
            var result = self;
            result.binding_key = parsed.key;
            result.binding_modifiers = parsed.modifiers;
            return result;
        }

        pub fn with_filter(self: Self, f: WindowFilter) Self {
            var result = self;
            result.filter = f;
            return result;
        }

        pub fn pause_exempt(self: Self) Self {
            var result = self;
            result.is_pause_exempt = true;
            return result;
        }

        pub fn create(self: Self) !u32 {
            const macro_id = try self.hook.macro_registry.create(self.name);

            if (self.hook.macro_registry.get(macro_id)) |m| {
                var i: u32 = 0;
                while (i < self.step_count) : (i += 1) {
                    const step = self.steps[i];
                    switch (step.kind) {
                        .text => {
                            if (step.text) |txt| {
                                try m.add_text(txt);
                            }
                        },
                        .line => {
                            if (step.text) |txt| {
                                try m.add_line(txt);
                            }
                        },
                        .key => {
                            try m.add_action(Action{
                                .kind = .key_press,
                                .key = step.keycode,
                                .modifiers = step.key_modifiers,
                            });
                        },
                        .delay => {
                            try m.add_action(Action{
                                .kind = .delay,
                                .delay_ms = step.delay_ms,
                            });
                        },
                    }
                }
            }

            if (self.binding_key) |bkey| {
                const Dummy = struct {
                    fn pass_through(_: *anyopaque, _: *const Key) Response {
                        return .pass;
                    }
                };

                _ = try self.hook.registry.register(
                    bkey,
                    self.binding_modifiers,
                    Dummy.pass_through,
                    self.hook,
                    key_registry.Options{
                        .filter = self.filter,
                        .pause_exempt = self.is_pause_exempt,
                    },
                );
            }

            return macro_id;
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

            const macro_id = try self.hook.macro_registry.create(self.name);

            if (self.hook.macro_registry.get(macro_id)) |m| {
                var i: u32 = 0;
                while (i < self.step_count) : (i += 1) {
                    const step = self.steps[i];
                    switch (step.kind) {
                        .text => {
                            if (step.text) |txt| {
                                try m.add_text(txt);
                            }
                        },
                        .line => {
                            if (step.text) |txt| {
                                try m.add_line(txt);
                            }
                        },
                        .key => {
                            try m.add_action(Action{
                                .kind = .key_press,
                                .key = step.keycode,
                                .modifiers = step.key_modifiers,
                            });
                        },
                        .delay => {
                            try m.add_action(Action{
                                .kind = .delay,
                                .delay_ms = step.delay_ms,
                            });
                        },
                    }
                }
            }

            if (self.binding_key) |bkey| {
                _ = try self.hook.registry.register(
                    bkey,
                    self.binding_modifiers,
                    wrapper.invoke,
                    context,
                    key_registry.Options{
                        .filter = self.filter,
                        .pause_exempt = self.is_pause_exempt,
                    },
                );
            }

            return macro_id;
        }
    };
}
