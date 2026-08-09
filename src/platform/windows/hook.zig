const std = @import("std");

const win32 = @import("win32.zig");

const assert = std.debug.assert;

pub const Callback = *const fn (c_int, win32.WPARAM, win32.LPARAM) callconv(.c) win32.LRESULT;

pub const kind_max: u8 = 1;
pub const kind_count: u8 = 2;

pub const Kind = enum(u8) {
    keyboard = 0,
    mouse = 1,

    pub fn is_valid(kind: Kind) bool {
        const value = @intFromEnum(kind);

        assert(kind_max == 1);
        assert(kind_count == 2);

        return value <= kind_max;
    }

    pub fn to_id(kind: Kind) win32.WINDOWS_HOOK_ID {
        assert(kind.is_valid());

        const result = switch (kind) {
            .keyboard => win32.WH_KEYBOARD_LL,
            .mouse => win32.WH_MOUSE_LL,
        };

        return result;
    }
};

pub const Hook = struct {
    handle: win32.HHOOK,
    kind: Kind,

    pub fn install(kind: Kind, callback: Callback, instance: win32.HINSTANCE) ?Hook {
        assert(kind.is_valid());

        const id = kind.to_id();
        const handle = win32.SetWindowsHookExW(id, @ptrCast(callback), instance, 0);

        if (handle == null) {
            return null;
        }

        assert(handle != null);

        const result = Hook{
            .handle = handle.?,
            .kind = kind,
        };

        assert(result.is_valid());
        assert(result.kind == kind);

        return result;
    }

    pub fn is_valid(hook: *const Hook) bool {
        const valid_kind = hook.kind.is_valid();

        return valid_kind;
    }

    pub fn remove(hook: *const Hook) bool {
        assert(hook.is_valid());

        const status = win32.UnhookWindowsHookEx(hook.handle);

        return status != 0;
    }
};

pub fn module() ?win32.HINSTANCE {
    return win32.GetModuleHandleW(null);
}

pub fn next(code_hook: c_int, wparam: win32.WPARAM, lparam: win32.LPARAM) win32.LRESULT {
    return win32.CallNextHookEx(null, code_hook, wparam, lparam);
}

const testing = std.testing;

test "a keyboard hook kind is valid" {
    try testing.expect(Kind.keyboard.is_valid());
}

test "a mouse hook kind is valid" {
    try testing.expect(Kind.mouse.is_valid());
}

test "the hook kinds are stable" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(Kind.keyboard));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(Kind.mouse));
}

test "hook constants" {
    try testing.expectEqual(@as(u8, 1), kind_max);
    try testing.expectEqual(@as(u8, 2), kind_count);
}
