const std = @import("std");

const filter_mod = @import("../filter.zig");
const mouse_event = @import("../event/mouse.zig");
const mouse_module = @import("../mouse.zig");
const response = @import("../response.zig");

const assert = std.debug.assert;

const CapacityError = mouse_module.CapacityError;
const MouseEvent = mouse_event.MouseEvent;
const Response = response.Response;
const WindowFilter = filter_mod.Active;

pub fn BindBuilderType(comptime HookType: type) type {
    return struct {
        const Instance = @This();

        hook: *HookType,
        kind: MouseEvent.Kind,
        filter: WindowFilter = .{},

        pub fn with_filter(instance: Instance, filter: WindowFilter) Instance {
            comptime filter_mod.require();

            var result = instance;

            result.filter = filter;

            return result;
        }

        pub fn on(
            instance: Instance,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner, *const MouseEvent) Response,
        ) CapacityError!HookType.Binding {
            const wrapper = struct {
                fn invoke(pointer: *anyopaque, event: *const MouseEvent) Response {
                    const typed: *Owner = @ptrCast(@alignCast(pointer));
                    return callback(typed, event);
                }
            };

            const id = try instance.hook.registry.register(
                instance.kind,
                wrapper.invoke,
                owner,
                .{ .filter = instance.filter },
            );

            assert(id >= 1);

            return @fromBackingInt(id);
        }
    };
}
