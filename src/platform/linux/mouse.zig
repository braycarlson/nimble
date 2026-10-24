const std = @import("std");

const mouse_event = @import("../../event/mouse.zig");
const response_mod = @import("../../response.zig");

const assert = std.debug.assert;

const MouseEvent = mouse_event.MouseEvent;
const Response = response_mod.Response;

pub const Error = error{
    HookDuplicate,
    HookInstallFailed,
};

const Dispatch = *const fn (event: *const MouseEvent) Response;

var owner_global: std.atomic.Value(?*anyopaque) = std.atomic.Value(?*anyopaque).init(null);
var dispatch_global: std.atomic.Value(?Dispatch) = std.atomic.Value(?Dispatch).init(null);

pub fn SourceType(comptime Owner: type) type {
    return struct {
        const Instance = @This();

        installed: bool = false,

        pub fn init() Instance {
            return Instance{};
        }

        pub fn install(instance: *Instance, owner: *Owner) Error!void {
            assert(!instance.installed);

            if (owner_global.cmpxchgStrong(null, owner, .seq_cst, .seq_cst) != null) {
                return error.HookDuplicate;
            }

            dispatch_global.store(Instance.dispatch, .seq_cst);

            instance.installed = true;

            assert(instance.installed);
            assert(dispatch_global.load(.seq_cst) != null);
        }

        pub fn remove(instance: *Instance) void {
            dispatch_global.store(null, .seq_cst);
            owner_global.store(null, .seq_cst);

            instance.installed = false;

            assert(!instance.installed);
            assert(owner_global.load(.seq_cst) == null);
        }

        fn dispatch(event: *const MouseEvent) Response {
            const pointer = owner_global.load(.seq_cst) orelse return .pass;
            const owner: *Owner = @ptrCast(@alignCast(pointer));
            const result = owner.process(event);

            assert(result.is_valid());

            return result;
        }
    };
}

pub fn feed(event: *const MouseEvent) Response {
    const dispatch = dispatch_global.load(.seq_cst) orelse return .pass;
    const result = dispatch(event);

    assert(result.is_valid());

    return result;
}

pub fn is_installed() bool {
    return dispatch_global.load(.seq_cst) != null;
}

pub fn reset() void {
    dispatch_global.store(null, .seq_cst);
    owner_global.store(null, .seq_cst);

    assert(!is_installed());
}
