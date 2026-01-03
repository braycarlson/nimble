const std = @import("std");
const rl = @import("rl.zig");
const c = rl.c;
const Theme = @import("theme.zig");

const button_height: i32 = 32;
const button_small_width: i32 = 36;
const button_medium_width: i32 = 44;
const button_play_width: i32 = 70;
const button_gap: i32 = 4;
const button_count: usize = 13;
const panel_padding: i32 = 20;
const play_gap_extra: i32 = 8;
const group_gap: i32 = 32;
const label_gap: i32 = 50;
const tick_display_width: i32 = 300;

x: i32,
y: i32,
width: i32,
height: i32,

const Self = @This();

const Button = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    label: []const u8,
    action: Action,

    const Action = enum {
        reset,
        step_back_100,
        step_back_10,
        step_back_1,
        play_pause,
        step_fwd_1,
        step_fwd_10,
        step_fwd_100,
        go_end,
        speed_down,
        speed_up,
        zoom_out,
        zoom_in,
    };
};

pub fn init(x: i32, y: i32, width: i32, height: i32) Self {
    std.debug.assert(width > 0);
    std.debug.assert(height > 0);

    return .{
        .x = x,
        .y = y,
        .width = width,
        .height = height,
    };
}

pub fn handle_input(self: *Self, state: anytype) void {
    std.debug.assert(self.width > 0);
    std.debug.assert(self.height > 0);

    const mouse_x = c.GetMouseX();
    const mouse_y = c.GetMouseY();

    if (!c.IsMouseButtonPressed(c.MOUSE_BUTTON_LEFT)) return;

    const buttons = self.get_buttons(state);

    for (buttons) |btn| {
        if (mouse_x >= btn.x and mouse_x <= btn.x + btn.width and
            mouse_y >= btn.y and mouse_y <= btn.y + btn.height)
        {
            self.execute_action(btn.action, state);
            break;
        }
    }
}

fn execute_action(_: *Self, action: Button.Action, state: anytype) void {
    switch (action) {
        .reset => state.current_tick = 0,
        .step_back_100 => state.step(-100),
        .step_back_10 => state.step(-10),
        .step_back_1 => state.step(-1),
        .play_pause => state.playing = !state.playing,
        .step_fwd_1 => state.step(1),
        .step_fwd_10 => state.step(10),
        .step_fwd_100 => state.step(100),
        .go_end => state.current_tick = state.max_tick,
        .speed_down => state.speed = if (state.speed <= 1.0) @max(state.speed - 0.25, 0.25) else state.speed - 1.0,
        .speed_up => state.speed = if (state.speed < 1.0) state.speed + 0.25 else @min(state.speed + 1.0, 16.0),
        .zoom_out => state.timeline.zoom = @max(state.timeline.zoom / 1.5, 0.1),
        .zoom_in => state.timeline.zoom = @min(state.timeline.zoom * 1.5, 10.0),
    }
}

fn get_buttons(self: *Self, state: anytype) [button_count]Button {
    std.debug.assert(self.width > 0);
    std.debug.assert(self.height > 0);

    const btn_h = button_height;
    const btn_y = self.y + @divTrunc(self.height - btn_h, 2);
    const small_w = button_small_width;
    const med_w = button_medium_width;
    const play_w = button_play_width;
    const gap = button_gap;

    const base_x = self.x + panel_padding;

    var positions: [button_count]i32 = undefined;
    positions[0] = base_x;
    positions[1] = positions[0] + small_w + gap;
    positions[2] = positions[1] + med_w + gap;
    positions[3] = positions[2] + small_w + gap;
    positions[4] = positions[3] + small_w + gap + play_gap_extra;
    positions[5] = positions[4] + play_w + gap + play_gap_extra;
    positions[6] = positions[5] + small_w + gap;
    positions[7] = positions[6] + small_w + gap;
    positions[8] = positions[7] + med_w + gap;
    positions[9] = positions[8] + small_w + group_gap;
    positions[10] = positions[9] + small_w + label_gap;
    positions[11] = positions[10] + small_w + group_gap;
    positions[12] = positions[11] + small_w + label_gap;

    const play_label: []const u8 = if (state.playing) "Pause" else "Play";

    const buttons = [button_count]Button{
        .{ .x = positions[0], .y = btn_y, .width = small_w, .height = btn_h, .label = "<<", .action = .reset },
        .{ .x = positions[1], .y = btn_y, .width = med_w, .height = btn_h, .label = "-100", .action = .step_back_100 },
        .{ .x = positions[2], .y = btn_y, .width = small_w, .height = btn_h, .label = "-10", .action = .step_back_10 },
        .{ .x = positions[3], .y = btn_y, .width = small_w, .height = btn_h, .label = "-1", .action = .step_back_1 },
        .{ .x = positions[4], .y = btn_y, .width = play_w, .height = btn_h, .label = play_label, .action = .play_pause },
        .{ .x = positions[5], .y = btn_y, .width = small_w, .height = btn_h, .label = "+1", .action = .step_fwd_1 },
        .{ .x = positions[6], .y = btn_y, .width = small_w, .height = btn_h, .label = "+10", .action = .step_fwd_10 },
        .{ .x = positions[7], .y = btn_y, .width = med_w, .height = btn_h, .label = "+100", .action = .step_fwd_100 },
        .{ .x = positions[8], .y = btn_y, .width = small_w, .height = btn_h, .label = ">>", .action = .go_end },
        .{ .x = positions[9], .y = btn_y, .width = small_w, .height = btn_h, .label = "-", .action = .speed_down },
        .{ .x = positions[10], .y = btn_y, .width = small_w, .height = btn_h, .label = "+", .action = .speed_up },
        .{ .x = positions[11], .y = btn_y, .width = small_w, .height = btn_h, .label = "-", .action = .zoom_out },
        .{ .x = positions[12], .y = btn_y, .width = small_w, .height = btn_h, .label = "+", .action = .zoom_in },
    };

    return buttons;
}

pub fn draw(self: *Self, state: anytype) void {
    std.debug.assert(self.width > 0);
    std.debug.assert(self.height > 0);

    Theme.draw_panel(self.x, self.y, self.width, self.height);

    const buttons = self.get_buttons(state);
    const mouse_x = c.GetMouseX();
    const mouse_y = c.GetMouseY();

    for (buttons) |btn| {
        const hovered = mouse_x >= btn.x and mouse_x <= btn.x + btn.width and
            mouse_y >= btn.y and mouse_y <= btn.y + btn.height;

        const bg = if (btn.action == .play_pause)
            (if (state.playing) Theme.red500 else Theme.green500)
        else if (hovered)
            Theme.dark600
        else
            Theme.dark700;

        c.DrawRectangleRounded(
            .{ .x = @floatFromInt(btn.x), .y = @floatFromInt(btn.y), .width = @floatFromInt(btn.width), .height = @floatFromInt(btn.height) },
            0.2,
            8,
            bg,
        );

        if (state.fonts.loaded) {
            var label_buf: [8]u8 = undefined;
            const label_z = std.fmt.bufPrintZ(&label_buf, "{s}", .{btn.label}) catch continue;
            const text_size = c.MeasureTextEx(state.fonts.regular, label_z, Theme.font_sm, 0);
            const text_x = @as(f32, @floatFromInt(btn.x)) + (@as(f32, @floatFromInt(btn.width)) - text_size.x) / 2;
            const text_y = @as(f32, @floatFromInt(btn.y)) + (@as(f32, @floatFromInt(btn.height)) - text_size.y) / 2;
            c.DrawTextEx(state.fonts.regular, label_z, .{ .x = text_x, .y = text_y }, Theme.font_sm, 0, Theme.gray300);
        }
    }

    if (state.fonts.loaded) {
        var buf: [32]u8 = undefined;

        const speed_x = buttons[9].x + buttons[9].width + 8;
        const speed_text = std.fmt.bufPrintZ(&buf, "{d:.1}x", .{state.speed}) catch "1.0x";
        c.DrawTextEx(state.fonts.regular, speed_text, .{ .x = @floatFromInt(speed_x), .y = @floatFromInt(self.y + 10) }, Theme.font_md, 0, Theme.blue400);

        c.DrawTextEx(state.fonts.regular, "Speed", .{ .x = @floatFromInt(speed_x), .y = @floatFromInt(self.y + 32) }, Theme.font_xs, 0, Theme.gray600);

        const zoom_x = buttons[11].x + buttons[11].width + 8;
        const zoom_text = std.fmt.bufPrintZ(&buf, "{d:.1}x", .{state.timeline.zoom}) catch "1.0x";
        c.DrawTextEx(state.fonts.regular, zoom_text, .{ .x = @floatFromInt(zoom_x), .y = @floatFromInt(self.y + 10) }, Theme.font_md, 0, Theme.blue400);

        c.DrawTextEx(state.fonts.regular, "Zoom", .{ .x = @floatFromInt(zoom_x), .y = @floatFromInt(self.y + 32) }, Theme.font_xs, 0, Theme.gray600);

        const tick_x = self.x + self.width - tick_display_width;
        c.DrawTextEx(state.fonts.regular, "Tick:", .{ .x = @floatFromInt(tick_x), .y = @floatFromInt(self.y + 18) }, Theme.font_md, 0, Theme.gray500);

        const tick_val = std.fmt.bufPrintZ(&buf, "{d}", .{state.current_tick}) catch "0";
        c.DrawTextEx(state.fonts.regular, tick_val, .{ .x = @floatFromInt(tick_x + 55), .y = @floatFromInt(self.y + 18) }, Theme.font_md, 0, Theme.yellow400);

        c.DrawTextEx(state.fonts.regular, "/", .{ .x = @floatFromInt(tick_x + 130), .y = @floatFromInt(self.y + 18) }, Theme.font_md, 0, Theme.gray600);

        const max_val = std.fmt.bufPrintZ(&buf, "{d}", .{state.max_tick}) catch "0";
        c.DrawTextEx(state.fonts.regular, max_val, .{ .x = @floatFromInt(tick_x + 150), .y = @floatFromInt(self.y + 18) }, Theme.font_md, 0, Theme.gray400);

        if (state.max_tick > 0) {
            const pct = (@as(f32, @floatFromInt(state.current_tick)) / @as(f32, @floatFromInt(state.max_tick))) * 100;
            const pct_text = std.fmt.bufPrintZ(&buf, "({d:.0}%)", .{pct}) catch "";
            c.DrawTextEx(state.fonts.regular, pct_text, .{ .x = @floatFromInt(tick_x + 225), .y = @floatFromInt(self.y + 18) }, Theme.font_sm, 0, Theme.gray600);
        }
    }
}
