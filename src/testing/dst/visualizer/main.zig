const std = @import("std");
const rl = @import("rl.zig");
const c = rl.c;

const Timeline = @import("timeline.zig");
const Sidebar = @import("sidebar.zig");
const Plots = @import("plots.zig");
const Keyboard = @import("keyboard.zig");
const Recording = @import("recording.zig");
const Theme = @import("theme.zig");

const sidebar_width: i32 = 340;
const header_height: i32 = 56;
const content_padding: i32 = 16;
const timeline_height: i32 = 180;
const keyboard_height: i32 = 450;
const welcome_panel_width: i32 = 640;
const welcome_panel_height: i32 = 400;
const welcome_button_width: i32 = 340;
const welcome_button_height: i32 = 56;
const default_window_width: i32 = 1280;
const default_window_height: i32 = 720;
const target_fps: i32 = 60;
const ticks_per_second_base: f32 = 60.0;
const speed_min: f32 = 0.25;
const speed_max: f32 = 16.0;

const Fonts = struct {
    small: c.Font,
    regular: c.Font,
    medium: c.Font,
    large: c.Font,
    mono_small: c.Font,
    mono: c.Font,
    loaded: bool,

    const base_size: i32 = 48;
    const large_size: i32 = 64;

    pub fn init() Fonts {
        const small = c.LoadFontEx("C:\\Windows\\Fonts\\segoeui.ttf", base_size, null, 0);
        const regular = c.LoadFontEx("C:\\Windows\\Fonts\\segoeui.ttf", base_size, null, 0);
        const medium = c.LoadFontEx("C:\\Windows\\Fonts\\segoeuib.ttf", base_size, null, 0);
        const large = c.LoadFontEx("C:\\Windows\\Fonts\\segoeuib.ttf", large_size, null, 0);
        const mono_small = c.LoadFontEx("C:\\Windows\\Fonts\\consola.ttf", base_size, null, 0);
        const mono = c.LoadFontEx("C:\\Windows\\Fonts\\consola.ttf", base_size, null, 0);

        const loaded = regular.texture.id != 0;

        if (loaded) {
            c.SetTextureFilter(small.texture, c.TEXTURE_FILTER_BILINEAR);
            c.SetTextureFilter(regular.texture, c.TEXTURE_FILTER_BILINEAR);
            c.SetTextureFilter(medium.texture, c.TEXTURE_FILTER_BILINEAR);
            c.SetTextureFilter(large.texture, c.TEXTURE_FILTER_BILINEAR);
            c.SetTextureFilter(mono_small.texture, c.TEXTURE_FILTER_BILINEAR);
            c.SetTextureFilter(mono.texture, c.TEXTURE_FILTER_BILINEAR);
        }

        return .{
            .small = small,
            .regular = regular,
            .medium = medium,
            .large = large,
            .mono_small = mono_small,
            .mono = mono,
            .loaded = loaded,
        };
    }

    pub fn deinit(self: *Fonts) void {
        if (self.loaded) {
            c.UnloadFont(self.small);
            c.UnloadFont(self.regular);
            c.UnloadFont(self.medium);
            c.UnloadFont(self.large);
            c.UnloadFont(self.mono_small);
            c.UnloadFont(self.mono);
        }
    }
};

pub const State = struct {
    recording: ?Recording.Data,
    current_tick: u64,
    max_tick: u64,
    playing: bool,
    speed: f32,
    tick_accumulator: f32,
    width: i32,
    height: i32,
    content_width: i32,
    content_height: i32,
    timeline: Timeline,
    sidebar: Sidebar,
    plots: Plots,
    keyboard: Keyboard,
    mode: Mode,
    fonts: Fonts,

    pub const Mode = enum {
        input,
        hook,
        stress,
    };

    pub fn init(width: i32, height: i32) State {
        std.debug.assert(width > 0);
        std.debug.assert(height > 0);

        const cw = width - sidebar_width - content_padding * 3;
        const ch = height - header_height - content_padding * 2;

        const plots_height = ch - timeline_height - keyboard_height - content_padding * 2;
        const timeline_y = height - timeline_height - content_padding;

        std.debug.assert(cw > 0);
        std.debug.assert(ch > 0);
        std.debug.assert(plots_height > 0);

        return .{
            .recording = null,
            .current_tick = 0,
            .max_tick = 0,
            .playing = false,
            .speed = 1.0,
            .tick_accumulator = 0.0,
            .width = width,
            .height = height,
            .content_width = cw,
            .content_height = ch,
            .keyboard = Keyboard.init(content_padding, header_height + content_padding, cw, keyboard_height),
            .plots = Plots.init(content_padding, header_height + content_padding + keyboard_height + content_padding, cw, plots_height),
            .timeline = Timeline.init(content_padding, timeline_y, cw, timeline_height),
            .sidebar = Sidebar.init(width - sidebar_width - content_padding, header_height + content_padding, sidebar_width, ch),
            .mode = .input,
            .fonts = Fonts.init(),
        };
    }

    pub fn deinit(self: *State, allocator: std.mem.Allocator) void {
        if (self.recording) |*rec| {
            rec.deinit(allocator);
        }
        self.fonts.deinit();
    }

    pub fn load_recording(self: *State, allocator: std.mem.Allocator, path: []const u8) !void {
        std.debug.assert(path.len > 0);

        if (self.recording) |*rec| {
            rec.deinit(allocator);
        }

        self.recording = try Recording.load(allocator, path);
        self.max_tick = self.recording.?.header.total_ticks;
        self.current_tick = 0;
        self.playing = false;
        self.tick_accumulator = 0.0;

        std.debug.assert(self.recording != null);
    }

    pub fn step(self: *State, delta: i64) void {
        const new_tick = @as(i64, @intCast(self.current_tick)) + delta;
        self.current_tick = @intCast(@max(0, @min(new_tick, @as(i64, @intCast(self.max_tick)))));

        std.debug.assert(self.current_tick <= self.max_tick);
    }

    pub fn update(self: *State, dt: f32) void {
        std.debug.assert(dt >= 0);
        std.debug.assert(self.speed >= speed_min);
        std.debug.assert(self.speed <= speed_max);

        if (!self.playing) return;
        if (self.recording == null) return;

        const ticks_per_second = ticks_per_second_base * self.speed;
        self.tick_accumulator += ticks_per_second * dt;

        if (self.tick_accumulator >= 1.0) {
            const advance = @as(u64, @intFromFloat(self.tick_accumulator));
            self.tick_accumulator -= @as(f32, @floatFromInt(advance));
            self.current_tick = @min(self.current_tick + advance, self.max_tick);

            self.timeline.ensure_cursor_visible(self);
        }

        if (self.current_tick >= self.max_tick) {
            self.playing = false;
        }

        std.debug.assert(self.current_tick <= self.max_tick);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    c.SetConfigFlags(c.FLAG_MSAA_4X_HINT | c.FLAG_WINDOW_RESIZABLE);
    c.InitWindow(default_window_width, default_window_height, "DST Visualizer");
    c.MaximizeWindow();
    defer c.CloseWindow();

    const screen_width = c.GetScreenWidth();
    const screen_height = c.GetScreenHeight();

    std.debug.assert(screen_width > 0);
    std.debug.assert(screen_height > 0);

    c.SetTargetFPS(target_fps);

    var state = State.init(screen_width, screen_height);
    defer state.deinit(allocator);

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len > 1) {
        state.load_recording(allocator, args[1]) catch |err| {
            std.debug.print("Failed to load recording: {}\n", .{err});
        };
    }

    while (!c.WindowShouldClose()) {
        handle_input(&state, allocator);
        state.update(c.GetFrameTime());
        render(&state);
    }
}

fn is_key_repeat(key: c_int) bool {
    return c.IsKeyPressed(key) or c.IsKeyPressedRepeat(key);
}

fn handle_input(state: *State, allocator: std.mem.Allocator) void {
    if (c.IsKeyPressed(c.KEY_SPACE)) {
        if (state.current_tick >= state.max_tick) {
            state.current_tick = 0;
        }
        state.playing = !state.playing;
        state.timeline.ensure_cursor_visible(state);
    }

    if (is_key_repeat(c.KEY_LEFT)) {
        const amount: i64 = if (c.IsKeyDown(c.KEY_LEFT_SHIFT)) 10 else 1;
        state.step(-amount);
        state.timeline.ensure_cursor_visible(state);
    }

    if (is_key_repeat(c.KEY_RIGHT)) {
        const amount: i64 = if (c.IsKeyDown(c.KEY_LEFT_SHIFT)) 10 else 1;
        state.step(amount);
        state.timeline.ensure_cursor_visible(state);
    }

    if (c.IsKeyPressed(c.KEY_HOME)) {
        state.current_tick = 0;
        state.timeline.ensure_cursor_visible(state);
    }

    if (c.IsKeyPressed(c.KEY_END)) {
        state.current_tick = state.max_tick;
        state.timeline.ensure_cursor_visible(state);
    }

    if (is_key_repeat(c.KEY_UP)) {
        state.speed = if (state.speed < 1.0) state.speed + 0.25 else @min(state.speed + 1.0, speed_max);
    }

    if (is_key_repeat(c.KEY_DOWN)) {
        state.speed = if (state.speed <= 1.0) @max(state.speed - 0.25, speed_min) else state.speed - 1.0;
    }

    if (c.IsKeyPressed(c.KEY_ONE)) state.mode = .input;
    if (c.IsKeyPressed(c.KEY_TWO)) state.mode = .hook;
    if (c.IsKeyPressed(c.KEY_THREE)) state.mode = .stress;

    if (c.IsFileDropped()) {
        const files = c.LoadDroppedFiles();
        defer c.UnloadDroppedFiles(files);

        if (files.count > 0) {
            const path = std.mem.span(files.paths[0]);
            state.load_recording(allocator, path) catch {};
        }
    }

    state.timeline.handle_input(state);
}

fn render(state: *State) void {
    c.BeginDrawing();
    defer c.EndDrawing();

    c.ClearBackground(Theme.dark900);

    if (state.recording == null) {
        draw_welcome(state);
        return;
    }

    draw_header(state);

    if (state.mode == .input) {
        state.keyboard.draw(state);
    }

    state.plots.draw(state);
    state.timeline.draw(state);
    state.sidebar.draw(state);
}

fn draw_header(state: *State) void {
    std.debug.assert(state.width > 0);

    c.DrawRectangle(0, 0, state.width, header_height, Theme.dark800);
    c.DrawLine(0, header_height, state.width, header_height, Theme.gray700);

    const title = switch (state.mode) {
        .input => "Input",
        .hook => "Hook",
        .stress => "Stress",
    };

    var buf: [64]u8 = undefined;

    if (state.fonts.loaded) {
        c.DrawTextEx(state.fonts.medium, title, .{ .x = 24, .y = 14 }, Theme.font_xl, 0, Theme.gray300);

        if (state.recording) |rec| {
            const center_x = @divTrunc(state.width, 2);
            c.DrawTextEx(state.fonts.regular, "Seed:", .{ .x = @floatFromInt(center_x - 50), .y = @floatFromInt(18) }, Theme.font_lg, 0, Theme.gray500);
            const seed_val = std.fmt.bufPrintZ(&buf, "{d}", .{rec.header.seed}) catch "0";
            c.DrawTextEx(state.fonts.regular, seed_val, .{ .x = @floatFromInt(center_x), .y = @floatFromInt(18) }, Theme.font_lg, 0, Theme.gray300);
        }

        draw_status_badge(state, state.width - 100, 18);
    } else {
        c.DrawText(title, 24, 16, 24, Theme.gray300);
    }
}

fn draw_status_badge(state: *State, x: i32, y: i32) void {
    const passed = if (state.recording) |rec| rec.stats.invariant_violations == 0 else true;

    const text_color = if (passed) Theme.green400 else Theme.red400;
    const dot_color = if (passed) Theme.green400 else Theme.red400;
    const label = if (passed) "Passed" else "Failed";

    c.DrawCircle(x, y + 12, 5, dot_color);

    if (state.fonts.loaded) {
        c.DrawTextEx(state.fonts.regular, label, .{ .x = @floatFromInt(x + 14), .y = @floatFromInt(y) }, Theme.font_lg, 0, text_color);
    } else {
        c.DrawText(label, x + 14, y, 24, text_color);
    }
}

fn draw_welcome(state: *State) void {
    std.debug.assert(state.width > 0);
    std.debug.assert(state.height > 0);

    const center_x: f32 = @as(f32, @floatFromInt(state.width)) / 2;
    const center_y: f32 = @as(f32, @floatFromInt(state.height)) / 2;

    const panel_half_w: f32 = @as(f32, welcome_panel_width) / 2;
    const panel_half_h: f32 = @as(f32, welcome_panel_height) / 2;

    c.DrawRectangleRounded(.{ .x = center_x - panel_half_w, .y = center_y - panel_half_h, .width = welcome_panel_width, .height = welcome_panel_height }, 0.03, 8, Theme.dark800);

    if (state.fonts.loaded) {
        const title = "DST Visualizer";
        const title_width = c.MeasureTextEx(state.fonts.large, title, Theme.font_xxl, 0).x;
        c.DrawTextEx(state.fonts.large, title, .{ .x = center_x - title_width / 2, .y = center_y - 150 }, Theme.font_xxl, 0, Theme.white);

        const subtitle = "Deterministic Simulation Testing";
        const sub_width = c.MeasureTextEx(state.fonts.regular, subtitle, Theme.font_lg, 0).x;
        c.DrawTextEx(state.fonts.regular, subtitle, .{ .x = center_x - sub_width / 2, .y = center_y - 90 }, Theme.font_lg, 0, Theme.gray400);

        const drop_text = "Drop a recording file to begin";
        const drop_width = c.MeasureTextEx(state.fonts.regular, drop_text, Theme.font_lg, 0).x;
        c.DrawTextEx(state.fonts.regular, drop_text, .{ .x = center_x - drop_width / 2, .y = center_y - 20 }, Theme.font_lg, 0, Theme.gray500);

        const arg_text = "or pass a path as command line argument";
        const arg_width = c.MeasureTextEx(state.fonts.regular, arg_text, Theme.font_md, 0).x;
        c.DrawTextEx(state.fonts.regular, arg_text, .{ .x = center_x - arg_width / 2, .y = center_y + 15 }, Theme.font_md, 0, Theme.gray600);

        const btn_half_w: f32 = @as(f32, welcome_button_width) / 2;
        c.DrawRectangleRounded(.{ .x = center_x - btn_half_w, .y = center_y + 70, .width = welcome_button_width, .height = welcome_button_height }, 0.3, 8, Theme.blue600);
        const btn_text = "Load Recording (.json)";
        const btn_width = c.MeasureTextEx(state.fonts.regular, btn_text, Theme.font_lg, 0).x;
        c.DrawTextEx(state.fonts.regular, btn_text, .{ .x = center_x - btn_width / 2, .y = center_y + 86 }, Theme.font_lg, 0, Theme.white);

        const cmd_text = "zig build input -- --output=recording.json";
        const cmd_width = c.MeasureTextEx(state.fonts.regular, cmd_text, Theme.font_md, 0).x;
        c.DrawTextEx(state.fonts.regular, cmd_text, .{ .x = center_x - cmd_width / 2, .y = center_y + 150 }, Theme.font_md, 0, Theme.gray600);
    } else {
        c.DrawText("DST Visualizer", @intFromFloat(center_x - 120), @intFromFloat(center_y - 60), 36, Theme.white);
        c.DrawText("Drop a recording file to begin", @intFromFloat(center_x - 150), @intFromFloat(center_y), 18, Theme.gray500);
    }
}
