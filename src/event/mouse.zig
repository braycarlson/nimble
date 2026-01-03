const std = @import("std");

const w32 = @import("win32").everything;

pub const kind_count: u8 = 11;
pub const kind_max: u8 = 10;

pub const Kind = enum(u8) {
    left_down = 0,
    left_up = 1,
    right_down = 2,
    right_up = 3,
    middle_down = 4,
    middle_up = 5,
    x_down = 6,
    x_up = 7,
    wheel = 8,
    move = 9,
    other = 10,

    pub fn is_valid(self: Kind) bool {
        const value = @intFromEnum(self);

        std.debug.assert(kind_max == 10);
        std.debug.assert(kind_count == 11);

        return value <= kind_max;
    }

    pub fn from_message(wparam: w32.WPARAM) Kind {
        std.debug.assert(@sizeOf(w32.WPARAM) >= 4);

        const result: Kind = switch (wparam) {
            w32.WM_LBUTTONDOWN => .left_down,
            w32.WM_LBUTTONUP => .left_up,
            w32.WM_RBUTTONDOWN => .right_down,
            w32.WM_RBUTTONUP => .right_up,
            w32.WM_MBUTTONDOWN => .middle_down,
            w32.WM_MBUTTONUP => .middle_up,
            w32.WM_XBUTTONDOWN => .x_down,
            w32.WM_XBUTTONUP => .x_up,
            w32.WM_MOUSEWHEEL => .wheel,
            w32.WM_MOUSEMOVE => .move,
            else => .other,
        };

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn is_button(self: Kind) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromEnum(self) <= kind_max);

        return switch (self) {
            .left_down, .left_up => true,
            .right_down, .right_up => true,
            .middle_down, .middle_up => true,
            .x_down, .x_up => true,
            .wheel, .move, .other => false,
        };
    }

    pub fn is_down(self: Kind) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromEnum(self) <= kind_max);

        return switch (self) {
            .left_down, .right_down, .middle_down, .x_down => true,
            else => false,
        };
    }

    pub fn is_up(self: Kind) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromEnum(self) <= kind_max);

        return switch (self) {
            .left_up, .right_up, .middle_up, .x_up => true,
            else => false,
        };
    }
};

pub const Mouse = struct {
    kind: Kind,
    x: i32,
    y: i32,
    extra: u64,

    pub fn is_valid(self: *const Mouse) bool {
        std.debug.assert(@intFromEnum(self.kind) <= kind_max);

        return self.kind.is_valid();
    }

    pub fn is_button(self: *const Mouse) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromEnum(self.kind) <= kind_max);

        return self.kind.is_button();
    }

    pub fn is_down(self: *const Mouse) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromEnum(self.kind) <= kind_max);

        return self.kind.is_down();
    }

    pub fn is_up(self: *const Mouse) bool {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromEnum(self.kind) <= kind_max);

        return self.kind.is_up();
    }

    pub fn parse(wparam: w32.WPARAM, lparam: w32.LPARAM) ?Mouse {
        std.debug.assert(@sizeOf(w32.WPARAM) >= 4);
        std.debug.assert(@sizeOf(w32.LPARAM) >= 4);

        const data = extract(lparam) orelse return null;

        const result = Mouse{
            .kind = Kind.from_message(wparam),
            .x = data.pt.x,
            .y = data.pt.y,
            .extra = @intCast(data.dwExtraInfo),
        };

        std.debug.assert(result.is_valid());
        std.debug.assert(result.kind.is_valid());

        return result;
    }

    fn extract(lparam: w32.LPARAM) ?*w32.MSLLHOOKSTRUCT {
        std.debug.assert(@sizeOf(w32.LPARAM) >= 4);

        if (lparam == 0) {
            return null;
        }

        const address: u64 = @intCast(lparam);

        std.debug.assert(address != 0);

        return @ptrFromInt(address);
    }
};
