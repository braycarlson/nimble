const std = @import("std");
const rl = @import("rl.zig");
const c = rl.c;
const Theme = @import("theme.zig");

const plot_count: usize = 3;
const max_history: usize = 65536;
const plot_gap: i32 = 16;
const canvas_padding: i32 = 16;
const header_height: i32 = 48;
const canvas_margin: i32 = 64;
const canvas_inner_padding: i32 = 8;

const plot_colors = [plot_count]c.Color{ Theme.gray400, Theme.gray400, Theme.gray400 };
const plot_labels = [plot_count][]const u8{ "Key Events", "Blocks", "Allows" };

x: i32,
y: i32,
width: i32,
height: i32,
history: [plot_count][max_history]u32,
history_len: [plot_count]usize,

const Self = @This();

pub fn init(x: i32, y: i32, width: i32, height: i32) Self {
    std.debug.assert(width > 0);
    std.debug.assert(height > 0);

    return .{
        .x = x,
        .y = y,
        .width = width,
        .height = height,
        .history = [_][max_history]u32{[_]u32{0} ** max_history} ** plot_count,
        .history_len = [_]usize{0} ** plot_count,
    };
}

pub fn update_from_recording(self: *Self, recording: anytype, current_tick: u64) void {
    var counts = [_]u32{0} ** plot_count;

    for (0..plot_count) |i| {
        self.history_len[i] = 0;
    }

    var last_tick: u64 = 0;

    for (recording.events) |event| {
        if (event.tick > current_tick) break;

        while (last_tick < event.tick and last_tick < max_history) : (last_tick += 1) {
            for (0..plot_count) |i| {
                if (self.history_len[i] < max_history) {
                    self.history[i][self.history_len[i]] = counts[i];
                    self.history_len[i] += 1;
                }
            }
        }

        switch (event.kind) {
            .key_down, .key_up => counts[0] += 1,
            .binding_blocked, .binding_replaced, .blocked => counts[1] += 1,
            .binding_triggered, .allowed => counts[2] += 1,
            else => {},
        }
    }

    while (last_tick <= current_tick and last_tick < max_history) : (last_tick += 1) {
        for (0..plot_count) |i| {
            if (self.history_len[i] < max_history) {
                self.history[i][self.history_len[i]] = counts[i];
                self.history_len[i] += 1;
            }
        }
    }

    for (0..plot_count) |i| {
        std.debug.assert(self.history_len[i] <= max_history);
    }
}

pub fn draw(self: *Self, state: anytype) void {
    std.debug.assert(self.width > 0);
    std.debug.assert(self.height > 0);

    if (state.recording == null) return;

    self.update_from_recording(state.recording.?, state.current_tick);

    const plot_width = @divTrunc(self.width - plot_gap * 2, @as(i32, plot_count));

    for (0..plot_count) |i| {
        const px = self.x + @as(i32, @intCast(i)) * (plot_width + plot_gap);
        self.draw_plot(px, plot_labels[i], i, plot_width, state);
    }
}

fn draw_plot(self: *Self, x: i32, label: []const u8, plot_index: usize, plot_width: i32, state: anytype) void {
    std.debug.assert(plot_index < plot_count);
    std.debug.assert(plot_width > 0);

    Theme.draw_panel(x, self.y, plot_width, self.height);

    var label_buf: [32]u8 = undefined;
    const label_z = std.fmt.bufPrintZ(&label_buf, "{s}", .{label}) catch return;

    if (state.fonts.loaded) {
        c.DrawTextEx(state.fonts.medium, label_z, .{ .x = @floatFromInt(x + 20), .y = @floatFromInt(self.y + 16) }, Theme.font_md, 0, Theme.gray300);
    }

    const history = &self.history[plot_index];
    const len = self.history_len[plot_index];

    var val_buf: [16]u8 = undefined;
    const current_val = if (len > 0) history[len - 1] else 0;
    const val_z = std.fmt.bufPrintZ(&val_buf, "{d}", .{current_val}) catch return;

    if (state.fonts.loaded) {
        c.DrawTextEx(state.fonts.regular, val_z, .{ .x = @floatFromInt(x + plot_width - 80), .y = @floatFromInt(self.y + 16) }, Theme.font_lg, 0, Theme.gray300);
    }

    const canvas_x = x + canvas_padding;
    const canvas_y = self.y + header_height;
    const canvas_w = plot_width - canvas_padding * 2;
    const canvas_h = self.height - canvas_margin;

    c.DrawRectangleRounded(
        .{ .x = @floatFromInt(canvas_x), .y = @floatFromInt(canvas_y), .width = @floatFromInt(canvas_w), .height = @floatFromInt(canvas_h) },
        0.03,
        8,
        Theme.dark900,
    );

    if (len < 2) return;

    var max_val: u32 = 1;
    for (0..len) |i| {
        if (history[i] > max_val) max_val = history[i];
    }

    std.debug.assert(max_val > 0);

    const color = plot_colors[plot_index];
    const width_f = @as(f32, @floatFromInt(canvas_w - canvas_inner_padding * 2));
    const height_f = @as(f32, @floatFromInt(canvas_h - canvas_inner_padding * 2));
    const len_f = @as(f32, @floatFromInt(len));
    const max_f = @as(f32, @floatFromInt(max_val));

    var prev_x: i32 = canvas_x + canvas_inner_padding;
    var prev_y: i32 = canvas_y + canvas_h - canvas_inner_padding;

    for (0..len) |i| {
        const val_f = @as(f32, @floatFromInt(history[i]));
        const i_f = @as(f32, @floatFromInt(i));

        const px_f = (i_f / len_f) * width_f;
        const py_f = height_f - (val_f / max_f) * (height_f - canvas_inner_padding);

        const curr_x = canvas_x + canvas_inner_padding + @as(i32, @intFromFloat(px_f));
        const curr_y = canvas_y + canvas_inner_padding + @as(i32, @intFromFloat(py_f));

        if (i > 0) {
            c.DrawLine(prev_x, prev_y, curr_x, curr_y, color);
        }

        prev_x = curr_x;
        prev_y = curr_y;
    }
}
