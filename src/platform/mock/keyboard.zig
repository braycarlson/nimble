const std = @import("std");

const key_event = @import("../../event/key.zig");
const response_mod = @import("../../response.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Response = response_mod.Response;

pub const Error = error{
    HookAlreadyInstalled,
    HookInstallFailed,
};

const Dispatch = *const fn (key: *const Key) Response;

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
                return error.HookAlreadyInstalled;
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

        fn dispatch(key: *const Key) Response {
            const pointer = owner_global.load(.seq_cst) orelse return .pass;
            const owner: *Owner = @ptrCast(@alignCast(pointer));

            const result = owner.process(key);

            assert(result.is_valid());

            return result;
        }
    };
}

pub fn feed(key: *const Key) Response {
    const dispatch = dispatch_global.load(.seq_cst) orelse return .pass;

    const result = dispatch(key);

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
