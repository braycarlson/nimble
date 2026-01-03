const std = @import("std");
const rl = @import("rl.zig");

pub const font_xs: f32 = 16;
pub const font_sm: f32 = 18;
pub const font_md: f32 = 20;
pub const font_lg: f32 = 24;
pub const font_xl: f32 = 28;
pub const font_xxl: f32 = 48;

pub const dark900: rl.Color = .{ .r = 10, .g = 10, .b = 15, .a = 255 };
pub const dark800: rl.Color = .{ .r = 18, .g = 18, .b = 26, .a = 255 };
pub const dark700: rl.Color = .{ .r = 26, .g = 26, .b = 36, .a = 255 };
pub const dark600: rl.Color = .{ .r = 37, .g = 37, .b = 48, .a = 255 };

pub const gray800: rl.Color = .{ .r = 45, .g = 45, .b = 55, .a = 255 };
pub const gray700: rl.Color = .{ .r = 55, .g = 55, .b = 65, .a = 255 };
pub const gray600: rl.Color = .{ .r = 75, .g = 75, .b = 85, .a = 255 };
pub const gray500: rl.Color = .{ .r = 107, .g = 114, .b = 128, .a = 255 };
pub const gray400: rl.Color = .{ .r = 156, .g = 163, .b = 175, .a = 255 };
pub const gray300: rl.Color = .{ .r = 209, .g = 213, .b = 219, .a = 255 };
pub const gray100: rl.Color = .{ .r = 243, .g = 244, .b = 246, .a = 255 };

pub const white: rl.Color = .{ .r = 255, .g = 255, .b = 255, .a = 255 };

pub const green400: rl.Color = .{ .r = 74, .g = 222, .b = 128, .a = 255 };
pub const green500: rl.Color = .{ .r = 34, .g = 197, .b = 94, .a = 255 };
pub const green500_20: rl.Color = .{ .r = 34, .g = 197, .b = 94, .a = 51 };

pub const red400: rl.Color = .{ .r = 248, .g = 113, .b = 113, .a = 255 };
pub const red500: rl.Color = .{ .r = 239, .g = 68, .b = 68, .a = 255 };
pub const red500_20: rl.Color = .{ .r = 239, .g = 68, .b = 68, .a = 51 };

pub const blue400: rl.Color = .{ .r = 96, .g = 165, .b = 250, .a = 255 };
pub const blue500: rl.Color = .{ .r = 59, .g = 130, .b = 246, .a = 255 };
pub const blue600: rl.Color = .{ .r = 37, .g = 99, .b = 235, .a = 255 };

pub const purple400: rl.Color = .{ .r = 192, .g = 132, .b = 252, .a = 255 };
pub const purple500: rl.Color = .{ .r = 168, .g = 85, .b = 247, .a = 255 };

pub const yellow400: rl.Color = .{ .r = 250, .g = 204, .b = 21, .a = 255 };
pub const orange400: rl.Color = .{ .r = 251, .g = 146, .b = 60, .a = 255 };
pub const cyan400: rl.Color = .{ .r = 34, .g = 211, .b = 238, .a = 255 };
pub const pink400: rl.Color = .{ .r = 244, .g = 114, .b = 182, .a = 255 };

pub fn draw_panel(x: i32, y: i32, w: i32, h: i32) void {
    std.debug.assert(w > 0);
    std.debug.assert(h > 0);

    rl.draw_rectangle_rounded(
        .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(w), .height = @floatFromInt(h) },
        0.03,
        8,
        dark800,
    );
}

pub fn draw_panel_inner(x: i32, y: i32, w: i32, h: i32) void {
    std.debug.assert(w > 0);
    std.debug.assert(h > 0);

    rl.draw_rectangle_rounded(
        .{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(w), .height = @floatFromInt(h) },
        0.05,
        8,
        dark700,
    );
}
