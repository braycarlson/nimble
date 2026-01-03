const std = @import("std");
const rl = @import("rl.zig");
const c = rl.c;
const Theme = @import("theme.zig");
const Recording = @import("recording.zig");

const stats_panel_height: i32 = 240;
const events_panel_gap: i32 = 16;
const panel_padding: i32 = 20;
const stat_row_height: i32 = 42;
const stat_row_inner_height: i32 = 38;
const stat_row_padding: i32 = 16;
const event_row_height: i32 = 40;
const event_row_inner_height: i32 = 36;
const max_events_displayed: u32 = 10;
const header_offset: i32 = 44;

x: i32,
y: i32,
width: i32,
height: i32,
scroll: i32,

const Self = @This();

const StatItem = struct {
    label: []const u8,
    value: u64,
};

pub fn init(x: i32, y: i32, width: i32, height: i32) Self {
    std.debug.assert(width > 0);
    std.debug.assert(height > 0);

    return .{
        .x = x,
        .y = y,
        .width = width,
        .height = height,
        .scroll = 0,
    };
}

pub fn draw(self: *Self, state: anytype) void {
    std.debug.assert(self.width > 0);
    std.debug.assert(self.height > 0);

    Theme.draw_panel(self.x, self.y, self.width, stats_panel_height);

    var y_offset = self.y + panel_padding;

    if (state.fonts.loaded) {
        c.DrawTextEx(state.fonts.medium, "Statistics", .{ .x = @floatFromInt(self.x + panel_padding), .y = @floatFromInt(y_offset) }, Theme.font_lg, 0, Theme.gray300);
    }
    y_offset += header_offset;

    if (state.recording) |recording| {
        y_offset = self.draw_stats(y_offset, recording, state);
    } else {
        if (state.fonts.loaded) {
            c.DrawTextEx(state.fonts.regular, "No data", .{ .x = @floatFromInt(self.x + panel_padding), .y = @floatFromInt(y_offset) }, Theme.font_md, 0, Theme.gray600);
        }
    }

    const events_y = self.y + stats_panel_height + events_panel_gap;
    const events_height = self.height - stats_panel_height - events_panel_gap;
    Theme.draw_panel(self.x, events_y, self.width, events_height);

    if (state.fonts.loaded) {
        c.DrawTextEx(state.fonts.medium, "Events at Tick", .{ .x = @floatFromInt(self.x + panel_padding), .y = @floatFromInt(events_y + panel_padding) }, Theme.font_lg, 0, Theme.gray300);

        var buf: [16]u8 = undefined;
        const tick_text = std.fmt.bufPrintZ(&buf, "{d}", .{state.current_tick}) catch "0";
        c.DrawTextEx(state.fonts.regular, tick_text, .{ .x = @floatFromInt(self.x + 185), .y = @floatFromInt(events_y + panel_padding) }, Theme.font_lg, 0, Theme.gray300);
    }

    if (state.recording) |recording| {
        self.draw_events(events_y + 64, recording, state);
    }
}

fn draw_stats(self: *Self, start_y: i32, recording: anytype, state: anytype) i32 {
    var y = start_y;
    const stats = Recording.compute_stats_at_tick(recording.events, state.current_tick);

    const items = self.get_stat_items_for_mode(stats, state.mode);

    for (items) |item| {
        self.draw_stat_row(y, item.label, item.value, state);
        y += stat_row_height;
    }

    return y;
}

fn get_stat_items_for_mode(_: *Self, stats: Recording.Stats, mode: anytype) [4]StatItem {
    return switch (mode) {
        .input => [4]StatItem{
            .{ .label = "Key Events", .value = stats.key_events },
            .{ .label = "Bindings", .value = stats.bindings_registered },
            .{ .label = "Blocks", .value = stats.blocks },
            .{ .label = "Allows", .value = stats.allows },
        },
        .hook => [4]StatItem{
            .{ .label = "Callbacks", .value = stats.total_callbacks },
            .{ .label = "Timeouts", .value = stats.timeouts_triggered },
            .{ .label = "Reinstalls", .value = stats.reinstall_attempts },
            .{ .label = "Faults", .value = stats.faults_injected },
        },
        .stress => [4]StatItem{
            .{ .label = "Stress Ticks", .value = stats.stress_ticks },
            .{ .label = "Inputs Dropped", .value = stats.inputs_dropped },
            .{ .label = "Queue Depth", .value = stats.max_queue_depth },
            .{ .label = "Violations", .value = stats.invariant_violations },
        },
    };
}

fn draw_stat_row(self: *Self, y: i32, label: []const u8, value: u64, state: anytype) void {
    Theme.draw_panel_inner(self.x + stat_row_padding, y, self.width - stat_row_padding * 2, stat_row_inner_height);

    var label_buf: [32]u8 = undefined;
    const label_z = std.fmt.bufPrintZ(&label_buf, "{s}", .{label}) catch return;

    var val_buf: [16]u8 = undefined;
    const val_z = std.fmt.bufPrintZ(&val_buf, "{d}", .{value}) catch return;

    if (state.fonts.loaded) {
        c.DrawTextEx(state.fonts.regular, label_z, .{ .x = @floatFromInt(self.x + 28), .y = @floatFromInt(y + 9) }, Theme.font_md, 0, Theme.gray400);
        c.DrawTextEx(state.fonts.regular, val_z, .{ .x = @floatFromInt(self.x + self.width - 90), .y = @floatFromInt(y + 9) }, Theme.font_md, 0, Theme.gray300);
    }
}

fn draw_events(self: *Self, start_y: i32, recording: anytype, state: anytype) void {
    var y = start_y;
    var count: u32 = 0;

    for (recording.events) |event| {
        if (event.tick != state.current_tick) continue;
        if (count >= max_events_displayed) break;

        Theme.draw_panel_inner(self.x + stat_row_padding, y, self.width - stat_row_padding * 2, event_row_inner_height);

        var buf: [48]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{s}", .{@tagName(event.kind)}) catch continue;

        const color = get_event_color(event.kind);

        if (state.fonts.loaded) {
            c.DrawTextEx(state.fonts.regular, text, .{ .x = @floatFromInt(self.x + 28), .y = @floatFromInt(y + 8) }, Theme.font_md, 0, color);
        }

        y += event_row_height;
        count += 1;
    }

    if (count == 0) {
        Theme.draw_panel_inner(self.x + stat_row_padding, y, self.width - stat_row_padding * 2, event_row_inner_height);

        if (state.fonts.loaded) {
            c.DrawTextEx(state.fonts.regular, "No events at this tick", .{ .x = @floatFromInt(self.x + 28), .y = @floatFromInt(y + 8) }, Theme.font_md, 0, Theme.gray600);
        }
    }
}

fn get_event_color(kind: Recording.Event.Kind) c.Color {
    return switch (kind) {
        .key_down, .key_up => Theme.green400,
        .binding_triggered, .allowed => Theme.cyan400,
        .binding_blocked, .binding_replaced, .blocked => Theme.red400,
        .binding_registered, .binding_unregistered => Theme.purple400,
        .fault_injected => Theme.orange400,
        .invariant_violated, .state_divergence => Theme.red500,
        .snapshot, .tick => Theme.gray500,
        else => Theme.gray600,
    };
}
