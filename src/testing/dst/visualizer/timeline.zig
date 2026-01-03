const std = @import("std");
const rl = @import("rl.zig");
const c = rl.c;
const Theme = @import("theme.zig");

const canvas_padding: i32 = 16;
const canvas_top_offset: i32 = 64;
const canvas_bottom_margin: i32 = 104;
const button_height: i32 = 28;
const button_top_offset: i32 = 18;
const button_small_width: i32 = 32;
const button_medium_width: i32 = 44;
const button_play_width: i32 = 72;
const button_gap: i32 = 4;
const button_play_margin: i32 = 12;
const nav_button_count: usize = 9;
const marker_count: u32 = 10;
const zoom_min: f32 = 0.1;
const zoom_max: f32 = 50.0;
const zoom_wheel_factor: f32 = 0.15;
const zoom_button_factor: f32 = 1.5;
const cursor_margin_ratio: f32 = 0.1;
const speed_control_offset: i32 = 280;
const zoom_control_offset: i32 = 110;
const hit_height: i32 = 28;
const hit_width: i32 = 20;
const speed_display_width: i32 = 70;
const zoom_display_width: i32 = 60;

x: i32,
y: i32,
width: i32,
height: i32,
zoom: f32,
offset: f32,
dragging: bool,

const Self = @This();

const NavButton = struct {
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    label: []const u8,
    action: Action,
    is_play: bool,

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
        .zoom = 1.0,
        .offset = 0.0,
        .dragging = false,
    };
}

pub fn handle_input(self: *Self, state: anytype) void {
    std.debug.assert(self.width > 0);
    std.debug.assert(self.height > 0);
    std.debug.assert(self.zoom >= zoom_min);
    std.debug.assert(self.zoom <= zoom_max);

    const mouse_x = c.GetMouseX();
    const mouse_y = c.GetMouseY();

    const canvas_x = self.x + canvas_padding;
    const canvas_y = self.y + canvas_top_offset;
    const canvas_w = self.width - canvas_padding * 2;
    const canvas_h = self.height - canvas_bottom_margin;

    const in_canvas = mouse_x >= canvas_x and
        mouse_x <= canvas_x + canvas_w and
        mouse_y >= canvas_y and
        mouse_y <= canvas_y + canvas_h;

    const in_bounds = mouse_x >= self.x and
        mouse_x <= self.x + self.width and
        mouse_y >= self.y and
        mouse_y <= self.y + self.height;

    if (in_bounds) {
        const wheel = c.GetMouseWheelMove();
        if (wheel != 0 and state.max_tick > 0) {
            const old_zoom = self.zoom;
            self.zoom = std.math.clamp(self.zoom * (1.0 + wheel * zoom_wheel_factor), zoom_min, zoom_max);

            const max_tick_f = @as(f32, @floatFromInt(state.max_tick));
            const current_f = @as(f32, @floatFromInt(state.current_tick));
            const old_range = max_tick_f / old_zoom;
            const new_range = max_tick_f / self.zoom;

            const rel_pos = if (old_range > 0) (current_f - self.offset) / old_range else 0.5;
            self.offset = current_f - rel_pos * new_range;
            self.offset = std.math.clamp(self.offset, 0, max_tick_f - new_range);
        }
    }

    if (in_canvas and c.IsMouseButtonPressed(c.MOUSE_BUTTON_LEFT)) {
        self.dragging = true;
    }

    if (c.IsMouseButtonReleased(c.MOUSE_BUTTON_LEFT)) {
        self.dragging = false;
    }

    if (self.dragging and state.recording != null) {
        const rel_x = @as(f32, @floatFromInt(mouse_x - canvas_x));
        const width_f = @as(f32, @floatFromInt(canvas_w));
        const max_tick_f = @as(f32, @floatFromInt(state.max_tick));

        const visible_range = max_tick_f / self.zoom;
        const tick = self.offset + (rel_x / width_f) * visible_range;

        state.current_tick = @intFromFloat(std.math.clamp(tick, 0, max_tick_f));
    }

    self.handle_button_input(state, mouse_x, mouse_y);
    self.handle_text_button_input(state, mouse_x, mouse_y);
}

fn handle_button_input(self: *Self, state: anytype, mouse_x: i32, mouse_y: i32) void {
    if (!c.IsMouseButtonPressed(c.MOUSE_BUTTON_LEFT)) return;

    const buttons = self.get_nav_buttons(state);
    for (buttons) |btn| {
        if (mouse_x >= btn.x and mouse_x <= btn.x + btn.width and
            mouse_y >= btn.y and mouse_y <= btn.y + btn.height)
        {
            self.execute_nav_action(btn.action, state);
            break;
        }
    }
}

fn handle_text_button_input(self: *Self, state: anytype, mouse_x: i32, mouse_y: i32) void {
    if (!c.IsMouseButtonPressed(c.MOUSE_BUTTON_LEFT)) return;

    const btn_y = self.y + button_top_offset;

    if (mouse_y < btn_y or mouse_y > btn_y + hit_height) return;

    const speed_x = self.x + self.width - speed_control_offset;
    if (mouse_x >= speed_x and mouse_x <= speed_x + hit_width) {
        state.speed = if (state.speed <= 1.0) @max(state.speed - 0.25, 0.25) else state.speed - 1.0;
    } else if (mouse_x >= speed_x + 12 + speed_display_width and mouse_x <= speed_x + 12 + speed_display_width + hit_width) {
        state.speed = if (state.speed < 1.0) state.speed + 0.25 else @min(state.speed + 1.0, 16.0);
    }

    const zoom_x = self.x + self.width - zoom_control_offset;
    if (mouse_x >= zoom_x and mouse_x <= zoom_x + hit_width) {
        self.zoom = @max(self.zoom / zoom_button_factor, zoom_min);
        self.center_on_tick(state);
    } else if (mouse_x >= zoom_x + 12 + zoom_display_width and mouse_x <= zoom_x + 12 + zoom_display_width + hit_width) {
        self.zoom = @min(self.zoom * zoom_button_factor, zoom_max);
        self.center_on_tick(state);
    }
}

fn get_nav_buttons(self: *Self, state: anytype) [nav_button_count]NavButton {
    std.debug.assert(self.width > 0);

    const btn_h = button_height;
    const btn_y = self.y + button_top_offset;
    const small_w = button_small_width;
    const med_w = button_medium_width;
    const play_w = button_play_width;
    const gap = button_gap;
    const play_margin = button_play_margin;

    const center_x = self.x + @divTrunc(self.width, 2);
    const nav_total = small_w + gap + med_w + gap + med_w + gap + small_w + gap + play_margin + play_w + play_margin + gap + small_w + gap + med_w + gap + med_w + gap + small_w;
    const start_x = center_x - @divTrunc(nav_total, 2);

    var positions: [nav_button_count]i32 = undefined;
    positions[0] = start_x;
    positions[1] = positions[0] + small_w + gap;
    positions[2] = positions[1] + med_w + gap;
    positions[3] = positions[2] + med_w + gap;
    positions[4] = positions[3] + small_w + gap + play_margin;
    positions[5] = positions[4] + play_w + play_margin + gap;
    positions[6] = positions[5] + small_w + gap;
    positions[7] = positions[6] + med_w + gap;
    positions[8] = positions[7] + med_w + gap;

    const play_label: []const u8 = if (state.playing) "Pause" else "Play";

    const buttons = [nav_button_count]NavButton{
        .{ .x = positions[0], .y = btn_y, .width = small_w, .height = btn_h, .label = "<<", .action = .reset, .is_play = false },
        .{ .x = positions[1], .y = btn_y, .width = med_w, .height = btn_h, .label = "-100", .action = .step_back_100, .is_play = false },
        .{ .x = positions[2], .y = btn_y, .width = med_w, .height = btn_h, .label = "-10", .action = .step_back_10, .is_play = false },
        .{ .x = positions[3], .y = btn_y, .width = small_w, .height = btn_h, .label = "-1", .action = .step_back_1, .is_play = false },
        .{ .x = positions[4], .y = btn_y, .width = play_w, .height = btn_h, .label = play_label, .action = .play_pause, .is_play = true },
        .{ .x = positions[5], .y = btn_y, .width = small_w, .height = btn_h, .label = "+1", .action = .step_fwd_1, .is_play = false },
        .{ .x = positions[6], .y = btn_y, .width = med_w, .height = btn_h, .label = "+10", .action = .step_fwd_10, .is_play = false },
        .{ .x = positions[7], .y = btn_y, .width = med_w, .height = btn_h, .label = "+100", .action = .step_fwd_100, .is_play = false },
        .{ .x = positions[8], .y = btn_y, .width = small_w, .height = btn_h, .label = ">>", .action = .go_end, .is_play = false },
    };

    return buttons;
}

fn execute_nav_action(self: *Self, action: NavButton.Action, state: anytype) void {
    switch (action) {
        .reset => state.current_tick = 0,
        .step_back_100 => state.step(-100),
        .step_back_10 => state.step(-10),
        .step_back_1 => state.step(-1),
        .play_pause => {
            if (state.current_tick >= state.max_tick) {
                state.current_tick = 0;
            }
            state.playing = !state.playing;
        },
        .step_fwd_1 => state.step(1),
        .step_fwd_10 => state.step(10),
        .step_fwd_100 => state.step(100),
        .go_end => state.current_tick = state.max_tick,
    }
    self.center_on_tick(state);
}

fn center_on_tick(self: *Self, state: anytype) void {
    if (state.max_tick == 0) return;

    const max_tick_f = @as(f32, @floatFromInt(state.max_tick));
    const current_f = @as(f32, @floatFromInt(state.current_tick));
    const visible_range = max_tick_f / self.zoom;

    self.offset = current_f - visible_range * 0.5;
    self.offset = std.math.clamp(self.offset, 0, @max(0, max_tick_f - visible_range));
}

pub fn ensure_cursor_visible(self: *Self, state: anytype) void {
    if (state.max_tick == 0) return;

    const max_tick_f = @as(f32, @floatFromInt(state.max_tick));
    const current_f = @as(f32, @floatFromInt(state.current_tick));
    const visible_range = max_tick_f / self.zoom;

    const margin = visible_range * cursor_margin_ratio;

    if (current_f < self.offset + margin) {
        self.offset = @max(0, current_f - margin);
    } else if (current_f > self.offset + visible_range - margin) {
        self.offset = @min(max_tick_f - visible_range, current_f - visible_range + margin);
    }
}

pub fn draw(self: *Self, state: anytype) void {
    std.debug.assert(self.width > 0);
    std.debug.assert(self.height > 0);

    Theme.draw_panel(self.x, self.y, self.width, self.height);

    self.draw_controls_row(state);
    self.draw_timeline_canvas(state);
}

fn draw_controls_row(self: *Self, state: anytype) void {
    const buttons = self.get_nav_buttons(state);
    const mouse_x = c.GetMouseX();
    const mouse_y = c.GetMouseY();

    const btn_y = self.y + button_top_offset;

    if (state.fonts.loaded) {
        var buf: [32]u8 = undefined;

        c.DrawTextEx(state.fonts.regular, "Tick:", .{ .x = @floatFromInt(self.x + 20), .y = @floatFromInt(btn_y + 4) }, Theme.font_md, 0, Theme.gray500);
        const tick_text = std.fmt.bufPrintZ(&buf, "{d} / {d}", .{ state.current_tick, state.max_tick }) catch "0";
        c.DrawTextEx(state.fonts.regular, tick_text, .{ .x = @floatFromInt(self.x + 62), .y = @floatFromInt(btn_y + 4) }, Theme.font_md, 0, Theme.gray300);

        const speed_x = self.x + self.width - speed_control_offset;
        c.DrawTextEx(state.fonts.regular, "-", .{ .x = @floatFromInt(speed_x), .y = @floatFromInt(btn_y + 4) }, Theme.font_md, 0, Theme.gray400);
        const speed_text = std.fmt.bufPrintZ(&buf, "{d:.2}x", .{state.speed}) catch "1.0x";
        const speed_text_size = c.MeasureTextEx(state.fonts.regular, speed_text, Theme.font_md, 0);
        const speed_text_x = @as(f32, @floatFromInt(speed_x + 12)) + (@as(f32, @floatFromInt(speed_display_width)) - speed_text_size.x) / 2;
        c.DrawTextEx(state.fonts.regular, speed_text, .{ .x = speed_text_x, .y = @floatFromInt(btn_y + 4) }, Theme.font_md, 0, Theme.gray300);
        c.DrawTextEx(state.fonts.regular, "+", .{ .x = @floatFromInt(speed_x + 12 + speed_display_width), .y = @floatFromInt(btn_y + 4) }, Theme.font_md, 0, Theme.gray400);

        const zoom_x = self.x + self.width - zoom_control_offset;
        c.DrawTextEx(state.fonts.regular, "-", .{ .x = @floatFromInt(zoom_x), .y = @floatFromInt(btn_y + 4) }, Theme.font_md, 0, Theme.gray400);
        const zoom_text = std.fmt.bufPrintZ(&buf, "{d:.1}x", .{self.zoom}) catch "1.0x";
        const zoom_text_size = c.MeasureTextEx(state.fonts.regular, zoom_text, Theme.font_md, 0);
        const zoom_text_x = @as(f32, @floatFromInt(zoom_x + 12)) + (@as(f32, @floatFromInt(zoom_display_width)) - zoom_text_size.x) / 2;
        c.DrawTextEx(state.fonts.regular, zoom_text, .{ .x = zoom_text_x, .y = @floatFromInt(btn_y + 4) }, Theme.font_md, 0, Theme.gray300);
        c.DrawTextEx(state.fonts.regular, "+", .{ .x = @floatFromInt(zoom_x + 12 + zoom_display_width), .y = @floatFromInt(btn_y + 4) }, Theme.font_md, 0, Theme.gray400);
    }

    for (buttons) |btn| {
        const hovered = mouse_x >= btn.x and mouse_x <= btn.x + btn.width and
            mouse_y >= btn.y and mouse_y <= btn.y + btn.height;

        const bg = if (btn.is_play)
            Theme.gray300
        else if (hovered)
            Theme.dark600
        else
            Theme.dark700;

        const text_color = if (btn.is_play) Theme.dark900 else Theme.gray300;

        c.DrawRectangleRounded(
            .{ .x = @floatFromInt(btn.x), .y = @floatFromInt(btn.y), .width = @floatFromInt(btn.width), .height = @floatFromInt(btn.height) },
            0.25,
            8,
            bg,
        );

        if (state.fonts.loaded) {
            var label_buf: [8]u8 = undefined;
            const label_z = std.fmt.bufPrintZ(&label_buf, "{s}", .{btn.label}) catch continue;
            const text_size = c.MeasureTextEx(state.fonts.regular, label_z, Theme.font_sm, 0);
            const text_x = @as(f32, @floatFromInt(btn.x)) + (@as(f32, @floatFromInt(btn.width)) - text_size.x) / 2;
            const text_y = @as(f32, @floatFromInt(btn.y)) + (@as(f32, @floatFromInt(btn.height)) - text_size.y) / 2;
            c.DrawTextEx(state.fonts.regular, label_z, .{ .x = text_x, .y = text_y }, Theme.font_sm, 0, text_color);
        }
    }
}

fn draw_timeline_canvas(self: *Self, state: anytype) void {
    const canvas_x = self.x + canvas_padding;
    const canvas_y = self.y + canvas_top_offset;
    const canvas_w = self.width - canvas_padding * 2;
    const canvas_h = self.height - canvas_bottom_margin;

    c.DrawRectangleRounded(
        .{ .x = @floatFromInt(canvas_x), .y = @floatFromInt(canvas_y), .width = @floatFromInt(canvas_w), .height = @floatFromInt(canvas_h) },
        0.02,
        8,
        Theme.dark900,
    );

    if (state.recording) |recording| {
        self.draw_events(recording, state.max_tick, canvas_x, canvas_y, canvas_w, canvas_h);
        self.draw_cursor(state.current_tick, state.max_tick, canvas_x, canvas_y, canvas_w, canvas_h);
        self.draw_tick_markers(state, canvas_x, canvas_y, canvas_w, canvas_h);
    } else {
        if (state.fonts.loaded) {
            const text = "No recording loaded";
            const text_size = c.MeasureTextEx(state.fonts.regular, text, Theme.font_md, 0);
            const text_x = @as(f32, @floatFromInt(canvas_x)) + (@as(f32, @floatFromInt(canvas_w)) - text_size.x) / 2;
            const text_y = @as(f32, @floatFromInt(canvas_y)) + (@as(f32, @floatFromInt(canvas_h)) - text_size.y) / 2;
            c.DrawTextEx(state.fonts.regular, text, .{ .x = text_x, .y = text_y }, Theme.font_md, 0, Theme.gray600);
        }
    }
}

fn draw_events(self: *Self, recording: anytype, max_tick: u64, cx: i32, cy: i32, cw: i32, ch: i32) void {
    if (max_tick == 0) return;

    const width_f = @as(f32, @floatFromInt(cw));
    const max_tick_f = @as(f32, @floatFromInt(max_tick));
    const visible_range = max_tick_f / self.zoom;

    for (recording.events) |event| {
        const tick_f = @as(f32, @floatFromInt(event.tick));

        if (tick_f < self.offset or tick_f > self.offset + visible_range) continue;

        const rel_tick = tick_f - self.offset;
        const x = cx + @as(i32, @intFromFloat((rel_tick / visible_range) * width_f));

        const color = switch (event.kind) {
            .key_down, .key_up => Theme.green400,
            .binding_registered, .binding_unregistered => Theme.purple400,
            .blocked => Theme.red400,
            .allowed => Theme.cyan400,
            else => Theme.gray600,
        };

        c.DrawLine(x, cy + 4, x, cy + ch - 4, color);
    }
}

fn draw_cursor(self: *Self, current_tick: u64, max_tick: u64, cx: i32, cy: i32, cw: i32, ch: i32) void {
    if (max_tick == 0) return;

    const width_f = @as(f32, @floatFromInt(cw));
    const max_tick_f = @as(f32, @floatFromInt(max_tick));
    const current_f = @as(f32, @floatFromInt(current_tick));
    const visible_range = max_tick_f / self.zoom;

    if (current_f < self.offset or current_f > self.offset + visible_range) return;

    const rel_tick = current_f - self.offset;
    const x = cx + @as(i32, @intFromFloat((rel_tick / visible_range) * width_f));

    c.DrawRectangle(x - 1, cy, 3, ch, Theme.yellow400);

    const x_f = @as(f32, @floatFromInt(x));
    const y_f = @as(f32, @floatFromInt(cy));

    c.DrawTriangle(
        .{ .x = x_f - 8, .y = y_f },
        .{ .x = x_f + 8, .y = y_f },
        .{ .x = x_f, .y = y_f + 10 },
        Theme.yellow400,
    );

    c.DrawTriangle(
        .{ .x = x_f, .y = @as(f32, @floatFromInt(cy + ch)) - 10 },
        .{ .x = x_f + 8, .y = @as(f32, @floatFromInt(cy + ch)) },
        .{ .x = x_f - 8, .y = @as(f32, @floatFromInt(cy + ch)) },
        Theme.yellow400,
    );
}

fn draw_tick_markers(self: *Self, state: anytype, cx: i32, cy: i32, cw: i32, ch: i32) void {
    if (state.max_tick == 0) return;

    const max_tick_f = @as(f32, @floatFromInt(state.max_tick));
    const visible_range = max_tick_f / self.zoom;
    const width_f = @as(f32, @floatFromInt(cw));

    const step = visible_range / @as(f32, @floatFromInt(marker_count));

    var i: u32 = 0;
    while (i <= marker_count) : (i += 1) {
        const tick = self.offset + step * @as(f32, @floatFromInt(i));
        const x = cx + @as(i32, @intFromFloat((@as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(marker_count))) * width_f));

        c.DrawLine(x, cy + ch, x, cy + ch + 6, Theme.gray700);

        var buf: [16]u8 = undefined;
        const label = std.fmt.bufPrintZ(&buf, "{d}", .{@as(u64, @intFromFloat(@max(0, tick)))}) catch continue;

        if (state.fonts.loaded) {
            const text_size = c.MeasureTextEx(state.fonts.regular, label, Theme.font_sm, 0);
            c.DrawTextEx(state.fonts.regular, label, .{ .x = @as(f32, @floatFromInt(x)) - text_size.x / 2, .y = @as(f32, @floatFromInt(cy + ch + 10)) }, Theme.font_sm, 0, Theme.gray500);
        }
    }
}
