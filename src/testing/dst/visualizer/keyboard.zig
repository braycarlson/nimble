const std = @import("std");
const rl = @import("rl.zig");
const c = rl.c;
const Theme = @import("theme.zig");

const key_gap: i32 = 1;
const corner_radius: f32 = 0.1;
const max_events_per_update: usize = 65536;
const max_other_keys_buffer: usize = 128;

const KeyInfo = struct {
    keycode: u8,
    label: []const u8,
    w: f32 = 1.0,
};

const row_0 = [_]KeyInfo{
    .{ .keycode = 27, .label = "Es" },  .{ .keycode = 112, .label = "1" },  .{ .keycode = 113, .label = "2" },
    .{ .keycode = 114, .label = "3" },  .{ .keycode = 115, .label = "4" },  .{ .keycode = 116, .label = "5" },
    .{ .keycode = 117, .label = "6" },  .{ .keycode = 118, .label = "7" },  .{ .keycode = 119, .label = "8" },
    .{ .keycode = 120, .label = "9" },  .{ .keycode = 121, .label = "10" }, .{ .keycode = 122, .label = "11" },
    .{ .keycode = 123, .label = "12" },
};

const row_1 = [_]KeyInfo{
    .{ .keycode = 192, .label = "`" }, .{ .keycode = 49, .label = "1" },           .{ .keycode = 50, .label = "2" },
    .{ .keycode = 51, .label = "3" },  .{ .keycode = 52, .label = "4" },           .{ .keycode = 53, .label = "5" },
    .{ .keycode = 54, .label = "6" },  .{ .keycode = 55, .label = "7" },           .{ .keycode = 56, .label = "8" },
    .{ .keycode = 57, .label = "9" },  .{ .keycode = 48, .label = "0" },           .{ .keycode = 189, .label = "-" },
    .{ .keycode = 187, .label = "=" }, .{ .keycode = 8, .label = "Bk", .w = 1.4 },
};

const row_2 = [_]KeyInfo{
    .{ .keycode = 9, .label = "Tb", .w = 1.2 }, .{ .keycode = 81, .label = "Q" },   .{ .keycode = 87, .label = "W" },
    .{ .keycode = 69, .label = "E" },           .{ .keycode = 82, .label = "R" },   .{ .keycode = 84, .label = "T" },
    .{ .keycode = 89, .label = "Y" },           .{ .keycode = 85, .label = "U" },   .{ .keycode = 73, .label = "I" },
    .{ .keycode = 79, .label = "O" },           .{ .keycode = 80, .label = "P" },   .{ .keycode = 219, .label = "[" },
    .{ .keycode = 221, .label = "]" },          .{ .keycode = 220, .label = "\\" },
};

const row_3 = [_]KeyInfo{
    .{ .keycode = 20, .label = "Cp", .w = 1.4 }, .{ .keycode = 65, .label = "A" },  .{ .keycode = 83, .label = "S" },
    .{ .keycode = 68, .label = "D" },            .{ .keycode = 70, .label = "F" },  .{ .keycode = 71, .label = "G" },
    .{ .keycode = 72, .label = "H" },            .{ .keycode = 74, .label = "J" },  .{ .keycode = 75, .label = "K" },
    .{ .keycode = 76, .label = "L" },            .{ .keycode = 186, .label = ";" }, .{ .keycode = 222, .label = "'" },
    .{ .keycode = 13, .label = "En", .w = 1.6 },
};

const row_4 = [_]KeyInfo{
    .{ .keycode = 160, .label = "Sh", .w = 1.8 }, .{ .keycode = 90, .label = "Z" },  .{ .keycode = 88, .label = "X" },
    .{ .keycode = 67, .label = "C" },             .{ .keycode = 86, .label = "V" },  .{ .keycode = 66, .label = "B" },
    .{ .keycode = 78, .label = "N" },             .{ .keycode = 77, .label = "M" },  .{ .keycode = 188, .label = "," },
    .{ .keycode = 190, .label = "." },            .{ .keycode = 191, .label = "/" }, .{ .keycode = 161, .label = "Sh", .w = 2.0 },
};

const row_5 = [_]KeyInfo{
    .{ .keycode = 162, .label = "Ct", .w = 1.2 }, .{ .keycode = 91, .label = "Wi" },            .{ .keycode = 164, .label = "Al" },
    .{ .keycode = 32, .label = "", .w = 4.5 },    .{ .keycode = 165, .label = "Al" },           .{ .keycode = 92, .label = "Wi" },
    .{ .keycode = 93, .label = "Mn" },            .{ .keycode = 163, .label = "Ct", .w = 1.2 },
};

const nav_0 = [_]KeyInfo{ .{ .keycode = 44, .label = "Pr" }, .{ .keycode = 145, .label = "Sc" }, .{ .keycode = 19, .label = "Pa" } };
const nav_1 = [_]KeyInfo{ .{ .keycode = 45, .label = "In" }, .{ .keycode = 36, .label = "Hm" }, .{ .keycode = 33, .label = "PU" } };
const nav_2 = [_]KeyInfo{ .{ .keycode = 46, .label = "De" }, .{ .keycode = 35, .label = "En" }, .{ .keycode = 34, .label = "PD" } };
const arrow_0 = [_]KeyInfo{.{ .keycode = 38, .label = "^" }};
const arrow_1 = [_]KeyInfo{ .{ .keycode = 37, .label = "<" }, .{ .keycode = 40, .label = "v" }, .{ .keycode = 39, .label = ">" } };

const num_0 = [_]KeyInfo{ .{ .keycode = 144, .label = "NL" }, .{ .keycode = 111, .label = "/" }, .{ .keycode = 106, .label = "*" }, .{ .keycode = 109, .label = "-" } };
const num_1 = [_]KeyInfo{ .{ .keycode = 103, .label = "7" }, .{ .keycode = 104, .label = "8" }, .{ .keycode = 105, .label = "9" }, .{ .keycode = 107, .label = "+" } };
const num_2 = [_]KeyInfo{ .{ .keycode = 100, .label = "4" }, .{ .keycode = 101, .label = "5" }, .{ .keycode = 102, .label = "6" } };
const num_3 = [_]KeyInfo{ .{ .keycode = 97, .label = "1" }, .{ .keycode = 98, .label = "2" }, .{ .keycode = 99, .label = "3" } };
const num_4 = [_]KeyInfo{ .{ .keycode = 96, .label = "0", .w = 2.0 }, .{ .keycode = 110, .label = "." } };

const media = [_]KeyInfo{
    .{ .keycode = 173, .label = "Mt" }, .{ .keycode = 174, .label = "V-" }, .{ .keycode = 175, .label = "V+" },
    .{ .keycode = 176, .label = "Nx" }, .{ .keycode = 177, .label = "Pv" }, .{ .keycode = 178, .label = "St" },
    .{ .keycode = 179, .label = "Pl" }, .{ .keycode = 166, .label = "Bk" }, .{ .keycode = 167, .label = "Fw" },
    .{ .keycode = 168, .label = "Rf" }, .{ .keycode = 170, .label = "Sr" }, .{ .keycode = 171, .label = "Fv" },
    .{ .keycode = 172, .label = "Hm" },
};

const modifier_keycodes = [_]u8{ 160, 161, 162, 163, 164, 165, 91, 92 };

const vk_names: [256][]const u8 = .{
    "R00", "LMB", "RMB", "Cxl", "MMB", "X1",  "X2",  "R07",
    "Bks", "Tab", "R0A", "R0B", "Clr", "Ent", "R0E", "R0F",
    "Shf", "Ctl", "Alt", "Pau", "Cap", "Kan", "IM1", "Jnj",
    "Fnl", "Hnj", "R1A", "Esc", "Cvt", "NCv", "Acp", "MCh",
    "Spc", "PgU", "PgD", "End", "Hom", "Lft", "Up",  "Rgt",
    "Dn",  "Sel", "Prt", "Exe", "PSc", "Ins", "Del", "Hlp",
    "0",   "1",   "2",   "3",   "4",   "5",   "6",   "7",
    "8",   "9",   "R3A", "R3B", "R3C", "R3D", "R3E", "R3F",
    "R40", "A",   "B",   "C",   "D",   "E",   "F",   "G",
    "H",   "I",   "J",   "K",   "L",   "M",   "N",   "O",
    "P",   "Q",   "R",   "S",   "T",   "U",   "V",   "W",
    "X",   "Y",   "Z",   "LWn", "RWn", "App", "R5E", "Slp",
    "Nm0", "Nm1", "Nm2", "Nm3", "Nm4", "Nm5", "Nm6", "Nm7",
    "Nm8", "Nm9", "Nm*", "Nm+", "Sep", "Nm-", "Nm.", "Nm/",
    "F1",  "F2",  "F3",  "F4",  "F5",  "F6",  "F7",  "F8",
    "F9",  "F10", "F11", "F12", "F13", "F14", "F15", "F16",
    "F17", "F18", "F19", "F20", "F21", "F22", "F23", "F24",
    "UI1", "UI2", "UI3", "UI4", "UI5", "UI6", "UI7", "UI8",
    "NmL", "ScL", "O92", "O93", "O94", "O95", "O96", "R97",
    "R98", "R99", "R9A", "R9B", "R9C", "R9D", "R9E", "R9F",
    "LSh", "RSh", "LCt", "RCt", "LAl", "RAl", "BBk", "BFw",
    "BRf", "BSt", "BSr", "BFv", "BHm", "Mut", "Vl-", "Vl+",
    "Nxt", "Prv", "Stp", "Ply", "Mal", "MSl", "Ap1", "Ap2",
    "RB8", "RB9", "O1",  "O+",  "O,",  "O-",  "O.",  "O2",
    "O3",  "RC1", "RC2", "RC3", "RC4", "RC5", "RC6", "RC7",
    "RC8", "RC9", "RCA", "RCB", "RCC", "RCD", "RCE", "RCF",
    "RD0", "RD1", "RD2", "RD3", "RD4", "RD5", "RD6", "RD7",
    "RD8", "RD9", "RDA", "O4",  "O5",  "O6",  "O7",  "O8",
    "OE0", "OE1", "OE2", "OE3", "OE4", "Prc", "Pkt", "OE7",
    "RE8", "OE9", "OEA", "OEB", "OEC", "OED", "OEE", "OEF",
    "OF0", "OF1", "OF2", "OF3", "OF4", "OF5", "Att", "CrS",
    "ExS", "EOF", "Ply", "Zom", "RFC", "PA1", "Clr", "Non",
};

const all_rows = [_][]const KeyInfo{ &row_0, &row_1, &row_2, &row_3, &row_4, &row_5, &nav_0, &nav_1, &nav_2, &arrow_0, &arrow_1, &num_0, &num_1, &num_2, &num_3, &num_4, &media };

const all_visual_keycodes = blk: {
    var keycodes: [256]bool = [_]bool{false} ** 256;
    for (all_rows) |row| {
        for (row) |k| keycodes[k.keycode] = true;
    }
    break :blk keycodes;
};

x: i32,
y: i32,
width: i32,
height: i32,
key_states: [256]bool,

const Self = @This();

pub fn init(x: i32, y: i32, width: i32, height: i32) Self {
    std.debug.assert(width > 0);
    std.debug.assert(height > 0);

    return .{ .x = x, .y = y, .width = width, .height = height, .key_states = [_]bool{false} ** 256 };
}

pub fn update_from_recording(self: *Self, recording: anytype, current_tick: u64) void {
    std.debug.assert(recording.events.len <= max_events_per_update or recording.events.len > 0);

    @memset(&self.key_states, false);

    var events_processed: usize = 0;
    for (recording.events) |event| {
        if (event.tick > current_tick) break;
        if (events_processed >= max_events_per_update) break;

        switch (event.kind) {
            .key_down => self.key_states[event.keycode] = true,
            .key_up => self.key_states[event.keycode] = false,
            else => {},
        }
        events_processed += 1;
    }
}

pub fn draw(self: *Self, state: anytype) void {
    std.debug.assert(self.width > 0);
    std.debug.assert(self.height > 0);

    Theme.draw_panel(self.x, self.y, self.width, self.height);

    if (state.recording) |recording| {
        self.update_from_recording(recording, state.current_tick);
    }

    var visual_down: u32 = 0;
    for (all_rows) |row| {
        for (row) |k| {
            if (self.key_states[k.keycode]) visual_down += 1;
        }
    }

    var other: [max_other_keys_buffer]u8 = undefined;
    var oc: usize = 0;
    var other_total: u32 = 0;
    for (0..256) |i| {
        if (self.key_states[i] and !all_visual_keycodes[i]) {
            other_total += 1;
            if (oc < max_other_keys_buffer) {
                other[oc] = @intCast(i);
                oc += 1;
            }
        }
    }

    if (state.fonts.loaded) {
        c.DrawTextEx(state.fonts.medium, "Keyboard State", .{ .x = @floatFromInt(self.x + 20), .y = @floatFromInt(self.y + 16) }, Theme.font_md, 0, Theme.gray300);
        var buf: [32]u8 = undefined;
        const count_text = std.fmt.bufPrintZ(&buf, "{d} keys down", .{visual_down + other_total}) catch "0 keys down";
        c.DrawTextEx(state.fonts.regular, count_text, .{ .x = @floatFromInt(self.x + self.width - 110), .y = @floatFromInt(self.y + 16) }, Theme.font_md, 0, Theme.gray300);
    }

    const hdr: i32 = 48;
    const other_h: i32 = 20;
    const kb_h = self.height - hdr - other_h - 4;
    const rows: i32 = 8;
    const row_h = @divTrunc(kb_h, rows);
    const padding: i32 = 16;
    const total_cols: i32 = 23;
    const key_w = @divTrunc(self.width - padding * 2, total_cols);

    const mx = self.x + padding;
    const nx = mx + key_w * 15 + 2;
    const px = nx + key_w * 4 + 2;
    const sy = self.y + hdr;

    self.draw_row(&media, mx, sy, key_w, row_h, state);
    self.draw_row(&row_0, mx, sy + row_h, key_w, row_h, state);
    self.draw_row(&row_1, mx, sy + row_h * 2, key_w, row_h, state);
    self.draw_row(&row_2, mx, sy + row_h * 3, key_w, row_h, state);
    self.draw_row(&row_3, mx, sy + row_h * 4, key_w, row_h, state);
    self.draw_row(&row_4, mx, sy + row_h * 5, key_w, row_h, state);
    self.draw_row(&row_5, mx, sy + row_h * 6, key_w, row_h, state);

    self.draw_row(&nav_0, nx, sy + row_h, key_w, row_h, state);
    self.draw_row(&nav_1, nx, sy + row_h * 2, key_w, row_h, state);
    self.draw_row(&nav_2, nx, sy + row_h * 3, key_w, row_h, state);
    self.draw_row(&arrow_0, nx + key_w, sy + row_h * 5, key_w, row_h, state);
    self.draw_row(&arrow_1, nx, sy + row_h * 6, key_w, row_h, state);

    self.draw_row(&num_0, px, sy + row_h, key_w, row_h, state);
    self.draw_row(&num_1, px, sy + row_h * 2, key_w, row_h, state);
    self.draw_row(&num_2, px, sy + row_h * 3, key_w, row_h, state);
    self.draw_row(&num_3, px, sy + row_h * 4, key_w, row_h, state);
    self.draw_row(&num_4, px, sy + row_h * 5, key_w, row_h, state);

    const other_y = self.y + self.height - other_h - 2;
    const arrow_right_end = nx + key_w * 3;
    const label_space = 50;
    const first_key_col = @divTrunc(label_space + key_w - 1, key_w);
    const other_start_x = mx + first_key_col * key_w;
    const max_other_keys = @divTrunc(arrow_right_end - other_start_x, key_w);
    self.draw_other_row(&other, oc, other_total, mx, other_y, key_w, other_h, max_other_keys, other_start_x, state);
}

fn draw_row(self: *Self, row: []const KeyInfo, sx: i32, y: i32, bw: i32, rh: i32, state: anytype) void {
    std.debug.assert(bw > 0);
    std.debug.assert(rh > 0);

    var x = sx;
    const kh = rh - key_gap;
    for (row) |key| {
        const kw = @as(i32, @intFromFloat(@as(f32, @floatFromInt(bw)) * key.w)) - key_gap;
        const down = self.key_states[key.keycode];
        const is_mod = self.is_modifier(key.keycode);
        const bg = if (down) (if (is_mod) Theme.purple500 else Theme.green500) else Theme.dark600;
        const tc = if (down) Theme.white else Theme.gray400;

        c.DrawRectangleRounded(.{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(kw), .height = @floatFromInt(kh) }, corner_radius, 4, bg);

        if (key.label.len > 0 and state.fonts.loaded) {
            var lb: [8]u8 = undefined;
            const lz = std.fmt.bufPrintZ(&lb, "{s}", .{key.label}) catch {
                x += @as(i32, @intFromFloat(@as(f32, @floatFromInt(bw)) * key.w));
                continue;
            };
            const ts = c.MeasureTextEx(state.fonts.small, lz, Theme.font_sm, 0);
            c.DrawTextEx(state.fonts.small, lz, .{ .x = @as(f32, @floatFromInt(x)) + (@as(f32, @floatFromInt(kw)) - ts.x) / 2, .y = @as(f32, @floatFromInt(y)) + (@as(f32, @floatFromInt(kh)) - ts.y) / 2 }, Theme.font_sm, 0, tc);
        }
        x += @as(i32, @intFromFloat(@as(f32, @floatFromInt(bw)) * key.w));
    }
}

fn draw_other_row(self: *Self, keys: []const u8, count: usize, total: u32, sx: i32, y: i32, bw: i32, rh: i32, max_keys: i32, start_x: i32, state: anytype) void {
    _ = self;
    std.debug.assert(bw > 0);
    std.debug.assert(rh > 0);

    const kw = bw - key_gap;
    const kh = rh - key_gap;

    if (state.fonts.loaded) {
        const label_size = c.MeasureTextEx(state.fonts.small, "Other:", Theme.font_sm, 0);
        const label_y = @as(f32, @floatFromInt(y)) + (@as(f32, @floatFromInt(kh)) - label_size.y) / 2;
        c.DrawTextEx(state.fonts.small, "Other:", .{ .x = @floatFromInt(sx), .y = label_y }, Theme.font_sm, 0, Theme.gray500);
    }

    if (count == 0) return;

    var x = start_x;

    const max_display: usize = @intCast(@max(0, max_keys));
    const display_count = @min(count, max_display);

    for (0..display_count) |i| {
        c.DrawRectangleRounded(.{ .x = @floatFromInt(x), .y = @floatFromInt(y), .width = @floatFromInt(kw), .height = @floatFromInt(kh) }, corner_radius, 4, Theme.green500);
        if (state.fonts.loaded) {
            var lb: [8]u8 = undefined;
            const lz = std.fmt.bufPrintZ(&lb, "{s}", .{vk_names[keys[i]]}) catch continue;
            const ts = c.MeasureTextEx(state.fonts.small, lz, Theme.font_sm, 0);
            c.DrawTextEx(state.fonts.small, lz, .{ .x = @as(f32, @floatFromInt(x)) + (@as(f32, @floatFromInt(kw)) - ts.x) / 2, .y = @as(f32, @floatFromInt(y)) + (@as(f32, @floatFromInt(kh)) - ts.y) / 2 }, Theme.font_sm, 0, Theme.white);
        }
        x += bw;
    }

    const remaining = total - @as(u32, @intCast(display_count));
    if (remaining > 0 and state.fonts.loaded) {
        var buf: [24]u8 = undefined;
        const more_text = std.fmt.bufPrintZ(&buf, "+ {d} other keys", .{remaining}) catch return;
        const more_size = c.MeasureTextEx(state.fonts.small, more_text, Theme.font_sm, 0);
        const more_y = @as(f32, @floatFromInt(y)) + (@as(f32, @floatFromInt(kh)) - more_size.y) / 2;
        c.DrawTextEx(state.fonts.small, more_text, .{ .x = @floatFromInt(x + 8), .y = more_y }, Theme.font_sm, 0, Theme.gray400);
    }
}

fn is_modifier(_: *Self, keycode: u8) bool {
    for (modifier_keycodes) |m| if (keycode == m) return true;
    return false;
}
