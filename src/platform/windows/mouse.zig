const std = @import("std");

const win32 = @import("win32.zig");

const event = @import("event.zig");
const hook = @import("hook.zig");
const loop = @import("loop.zig");

const assert = std.debug.assert;

pub const Error = error{
    HookAlreadyInstalled,
    HookInstallFailed,
};

const Procedure = *const fn (c_int, win32.WPARAM, win32.LPARAM) callconv(.c) win32.LRESULT;

var instance_global: std.atomic.Value(?*anyopaque) = std.atomic.Value(?*anyopaque).init(null);
var procedure_global: std.atomic.Value(?Procedure) = std.atomic.Value(?Procedure).init(null);

pub fn SourceType(comptime Owner: type) type {
    return struct {
        const Instance = @This();

        handle: ?hook.Hook = null,
        module: ?win32.HINSTANCE = null,

        pub fn init() Instance {
            return Instance{};
        }

        pub fn install(instance: *Instance, owner: *Owner) Error!void {
            assert(instance.handle == null);

            instance.module = hook.module();

            if (instance.module == null) {
                return error.HookInstallFailed;
            }

            if (instance_global.cmpxchgStrong(null, owner, .seq_cst, .seq_cst) != null) {
                return error.HookAlreadyInstalled;
            }

            procedure_global.store(Instance.procedure, .seq_cst);

            const module = instance.module.?;

            instance.handle = hook.Hook.install(.mouse, trampoline, module);

            if (instance.handle == null) {
                procedure_global.store(null, .seq_cst);
                instance_global.store(null, .seq_cst);

                return error.HookInstallFailed;
            }

            loop.claim_thread();

            assert(instance.handle != null);
            assert(instance.module != null);
        }

        pub fn remove(instance: *Instance) void {
            const handle = instance.handle orelse return;

            procedure_global.store(null, .seq_cst);
            instance_global.store(null, .seq_cst);

            _ = handle.remove();

            instance.handle = null;

            loop.release_thread();

            assert(instance.handle == null);
            assert(instance_global.load(.seq_cst) == null);
        }

        fn procedure(
            code: c_int,
            wparam: win32.WPARAM,
            lparam: win32.LPARAM,
        ) callconv(.c) win32.LRESULT {
            if (code < 0) {
                return hook.next(code, wparam, lparam);
            }

            assert(code >= 0);

            const parsed = event.parse_mouse(wparam, lparam) orelse
                return hook.next(code, wparam, lparam);

            const pointer = instance_global.load(.seq_cst) orelse
                return hook.next(code, wparam, lparam);

            const owner: *Owner = @ptrCast(@alignCast(pointer));

            assert(parsed.is_valid());

            const response = owner.process(&parsed);

            assert(response.is_valid());

            if (response.should_block()) {
                return 1;
            }

            return hook.next(code, wparam, lparam);
        }
    };
}

fn trampoline(
    code: c_int,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(.c) win32.LRESULT {
    if (procedure_global.load(.seq_cst)) |procedure| {
        return procedure(code, wparam, lparam);
    }

    return hook.next(code, wparam, lparam);
}
