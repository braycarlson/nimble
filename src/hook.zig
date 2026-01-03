const std = @import("std");

const w32 = @import("win32").everything;

pub const Callback = *const fn (c_int, w32.WPARAM, w32.LPARAM) callconv(.c) w32.LRESULT;

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

    pub fn to_id(self: Kind) w32.WINDOWS_HOOK_ID {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromEnum(self) <= kind_max);

        const result = switch (self) {
            .keyboard => w32.WH_KEYBOARD_LL,
            .mouse => w32.WH_MOUSE_LL,
        };

        return result;
    }
};

pub const Hook = struct {
    handle: w32.HHOOK,
    kind: Kind,

    pub fn install(kind: Kind, callback: Callback, instance: w32.HINSTANCE) ?Hook {
        std.debug.assert(kind.is_valid());
        std.debug.assert(@intFromPtr(callback) != 0);

        const id = kind.to_id();
        const handle = w32.SetWindowsHookExW(id, @ptrCast(callback), instance, 0);

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
        std.debug.assert(@intFromPtr(self.handle) != 0 or @intFromPtr(self.handle) == 0);

        const valid_kind = self.kind.is_valid();

        return valid_kind;
    }

    pub fn remove(self: *const Hook) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(self.handle) != 0);

        const status = w32.UnhookWindowsHookEx(self.handle);
        const result = status != 0;

        return result;
    }
};

pub fn module() ?w32.HINSTANCE {
    const result = w32.GetModuleHandleW(null);

    return result;
}

pub fn next(code_hook: c_int, wparam: w32.WPARAM, lparam: w32.LPARAM) w32.LRESULT {
    const result = w32.CallNextHookEx(null, code_hook, wparam, lparam);

    return result;
}
