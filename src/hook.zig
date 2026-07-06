const std = @import("std");

const win32 = @import("win32").everything;

pub const Callback = *const fn (c_int, win32.WPARAM, win32.LPARAM) callconv(.c) win32.LRESULT;

pub const kind_max: u8 = 1;
pub const kind_count: u8 = 2;

pub const Kind = enum(u8) {
    keyboard = 0,
    mouse = 1,

    pub fn is_valid(self: Kind) bool {
        const value = @intFromEnum(self);

        std.debug.assert(kind_max == 1);
        std.debug.assert(kind_count == 2);

        const result = value <= kind_max;

        return result;
    }

    pub fn to_id(self: Kind) win32.WINDOWS_HOOK_ID {
        std.debug.assert(self.is_valid());

        const result = switch (self) {
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
        std.debug.assert(kind.is_valid());

        const id = kind.to_id();
        const handle = win32.SetWindowsHookExW(id, @ptrCast(callback), instance, 0);

        if (handle == null) {
            return null;
        }

        std.debug.assert(handle != null);

        const result = Hook{
            .handle = handle.?,
            .kind = kind,
        };

        std.debug.assert(result.is_valid());
        std.debug.assert(result.kind == kind);

        return result;
    }

    pub fn is_valid(self: *const Hook) bool {
        const valid_kind = self.kind.is_valid();

        return valid_kind;
    }

    pub fn remove(self: *const Hook) bool {
        std.debug.assert(self.is_valid());

        const status = win32.UnhookWindowsHookEx(self.handle);
        const result = status != 0;

        return result;
    }
};

pub fn module() ?win32.HINSTANCE {
    const result = win32.GetModuleHandleW(null);

    return result;
}

pub fn next(code_hook: c_int, wparam: win32.WPARAM, lparam: win32.LPARAM) win32.LRESULT {
    const result = win32.CallNextHookEx(null, code_hook, wparam, lparam);

    return result;
}
