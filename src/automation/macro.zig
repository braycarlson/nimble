const std = @import("std");

const w32 = @import("win32").everything;

const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const key_sender = @import("../sender/key.zig");
const mouse_sender = @import("../sender/mouse.zig");
const message = @import("../sender/message.zig");
const slot_mod = @import("../registry/slot.zig");
const typer = @import("../sender/typer.zig");
const window = @import("../window.zig");

pub const action_max: u16 = 256;
pub const capacity_max: u8 = 32;
pub const name_max: u8 = 32;
pub const text_buffer_max: u16 = 1024;
pub const delay_default_ms: u32 = 10;
pub const delay_max_ms: u32 = 10000;
pub const repeat_max: u32 = 10000;
pub const scroll_amount_max: i32 = 1000;

pub const Error = error{
    AlreadyActive,
    BufferFull,
    InvalidName,
    NotActive,
    NotFound,
    RegistryFull,
    TextTooLong,
};

pub const ActionKind = enum(u8) {
    key_down = 0,
    key_up = 1,
    key_press = 2,
    mouse_move = 3,
    mouse_click = 4,
    mouse_down = 5,
    mouse_up = 6,
    mouse_scroll = 7,
    delay = 8,
    text = 9,

    pub fn is_valid(self: ActionKind) bool {
        const value = @intFromEnum(self);
        return value <= 9;
    }
};

pub const Action = struct {
    kind: ActionKind = .key_press,
    key: u8 = 0,
    modifiers: modifier.Set = .{},
    button: mouse_sender.Button = .left,
    x: i32 = 0,
    y: i32 = 0,
    scroll_amount: i32 = 0,
    delay_ms: u32 = 0,
    text_start: u16 = 0,
    text_len: u8 = 0,

    pub fn is_valid(self: *const Action) bool {
        if (!self.kind.is_valid()) {
            return false;
        }

        return switch (self.kind) {
            .key_down, .key_up, .key_press => self.key >= 0x01 and self.key <= 0xFE,
            .mouse_move => true,
            .mouse_click, .mouse_down, .mouse_up => self.button.is_valid(),
            .mouse_scroll => self.scroll_amount >= -scroll_amount_max and self.scroll_amount <= scroll_amount_max,
            .delay => self.delay_ms <= delay_max_ms,
            .text => self.text_len > 0,
        };
    }

    pub fn key_down(k: u8) Action {
        std.debug.assert(k >= 0x01 and k <= 0xFE);

        const result = Action{ .kind = .key_down, .key = k };

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn key_up(k: u8) Action {
        std.debug.assert(k >= 0x01 and k <= 0xFE);

        const result = Action{ .kind = .key_up, .key = k };

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn key_press(k: u8) Action {
        std.debug.assert(k >= 0x01 and k <= 0xFE);

        const result = Action{ .kind = .key_press, .key = k };

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn mouse_move(x: i32, y: i32) Action {
        const result = Action{ .kind = .mouse_move, .x = x, .y = y };

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn mouse_click(button: mouse_sender.Button) Action {
        std.debug.assert(button.is_valid());

        const result = Action{ .kind = .mouse_click, .button = button };

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn mouse_down(button: mouse_sender.Button) Action {
        std.debug.assert(button.is_valid());

        const result = Action{ .kind = .mouse_down, .button = button };

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn mouse_up(button: mouse_sender.Button) Action {
        std.debug.assert(button.is_valid());

        const result = Action{ .kind = .mouse_up, .button = button };

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn mouse_scroll(amount: i32) Action {
        std.debug.assert(amount >= -scroll_amount_max);
        std.debug.assert(amount <= scroll_amount_max);

        const result = Action{ .kind = .mouse_scroll, .scroll_amount = amount };

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn delay(ms: u32) Action {
        std.debug.assert(ms <= delay_max_ms);

        const result = Action{ .kind = .delay, .delay_ms = ms };

        std.debug.assert(result.is_valid());

        return result;
    }
};

pub const Macro = struct {
    name: [name_max]u8 = [_]u8{0} ** name_max,
    name_len: u8 = 0,
    actions: [action_max]Action = [_]Action{.{}} ** action_max,
    action_count: u16 = 0,
    text_buffer: [text_buffer_max]u8 = [_]u8{0} ** text_buffer_max,
    text_len: u16 = 0,
    id: u32 = 0,
    active: bool = false,
    repeat_count: u32 = 1,
    delay_between_ms: u32 = 0,

    pub fn get_id(self: *const Macro) u32 {
        return self.id;
    }

    pub fn is_active(self: *const Macro) bool {
        return self.active;
    }

    pub fn is_valid(self: *const Macro) bool {
        if (!self.active) {
            return true;
        }

        const valid_name = self.name_len > 0 and self.name_len <= name_max;
        const valid_actions = self.action_count <= action_max;
        const valid_text = self.text_len <= text_buffer_max;
        const valid_repeat = self.repeat_count <= repeat_max;
        const valid_delay = self.delay_between_ms <= delay_max_ms;
        const valid_id = self.id >= 1;

        if (!valid_name or !valid_actions or !valid_text or !valid_repeat or !valid_delay or !valid_id) {
            return false;
        }

        return self.validate_actions();
    }

    fn validate_actions(self: *const Macro) bool {
        var i: u16 = 0;

        while (i < self.action_count) : (i += 1) {
            if (!self.actions[i].is_valid()) {
                return false;
            }

            if (self.actions[i].kind == .text) {
                const start = self.actions[i].text_start;
                const len = self.actions[i].text_len;

                if (start + @as(u16, len) > self.text_len) {
                    return false;
                }
            }
        }

        return true;
    }

    pub fn get_name(self: *const Macro) []const u8 {
        std.debug.assert(self.name_len <= name_max);

        return self.name[0..self.name_len];
    }

    pub fn get_text(self: *const Macro, action: *const Action) []const u8 {
        std.debug.assert(action.kind == .text);
        std.debug.assert(action.text_start < text_buffer_max);
        std.debug.assert(action.text_start + @as(u16, action.text_len) <= self.text_len);

        const start = action.text_start;
        const end = start + @as(u16, action.text_len);

        std.debug.assert(end <= text_buffer_max);

        return self.text_buffer[start..end];
    }

    pub fn remaining_action_capacity(self: *const Macro) u16 {
        std.debug.assert(self.action_count <= action_max);

        return action_max - self.action_count;
    }

    pub fn remaining_text_capacity(self: *const Macro) u16 {
        std.debug.assert(self.text_len <= text_buffer_max);

        return text_buffer_max - self.text_len;
    }

    pub fn add_action(self: *Macro, action: Action) Error!void {
        std.debug.assert(action.is_valid());
        std.debug.assert(self.action_count <= action_max);

        if (self.action_count >= action_max) {
            return Error.BufferFull;
        }

        const slot = self.action_count;

        self.actions[slot] = action;
        self.action_count += 1;

        std.debug.assert(self.action_count >= 1);
        std.debug.assert(self.action_count <= action_max);
        std.debug.assert(self.actions[slot].is_valid());
    }

    pub fn add_text(self: *Macro, text: []const u8) Error!void {
        std.debug.assert(text.len > 0);
        std.debug.assert(self.action_count <= action_max);
        std.debug.assert(self.text_len <= text_buffer_max);

        if (self.action_count >= action_max) {
            return Error.BufferFull;
        }

        if (text.len > 255) {
            return Error.TextTooLong;
        }

        const text_len_u8: u8 = @intCast(text.len);
        const text_len_u16: u16 = @intCast(text.len);

        if (self.text_len + text_len_u16 > text_buffer_max) {
            return Error.BufferFull;
        }

        const start = self.text_len;
        const end = start + text_len_u16;

        std.debug.assert(end <= text_buffer_max);
        std.debug.assert(start < end);

        @memcpy(self.text_buffer[start..end], text[0..text_len_u16]);

        self.text_len = end;

        const action = Action{
            .kind = .text,
            .text_start = start,
            .text_len = text_len_u8,
        };

        std.debug.assert(action.is_valid());

        self.actions[self.action_count] = action;
        self.action_count += 1;

        std.debug.assert(self.text_len <= text_buffer_max);
        std.debug.assert(self.action_count <= action_max);
    }

    pub fn add_line(self: *Macro, text: []const u8) Error!void {
        std.debug.assert(self.action_count <= action_max);
        std.debug.assert(self.text_len <= text_buffer_max);

        if (self.action_count >= action_max) {
            return Error.BufferFull;
        }

        const max_text_len: u16 = 254;
        const text_len_u16: u16 = if (text.len > max_text_len) max_text_len else @intCast(text.len);
        const total_len: u16 = text_len_u16 + 1;

        if (total_len > 255) {
            return Error.TextTooLong;
        }

        if (self.text_len + total_len > text_buffer_max) {
            return Error.BufferFull;
        }

        const start = self.text_len;

        std.debug.assert(start + text_len_u16 < text_buffer_max);

        @memcpy(self.text_buffer[start .. start + text_len_u16], text[0..text_len_u16]);
        self.text_buffer[start + text_len_u16] = '\n';

        self.text_len += total_len;

        const action = Action{
            .kind = .text,
            .text_start = start,
            .text_len = @intCast(total_len),
        };

        std.debug.assert(action.is_valid());

        self.actions[self.action_count] = action;
        self.action_count += 1;

        std.debug.assert(self.text_len <= text_buffer_max);
        std.debug.assert(self.action_count <= action_max);
    }

    pub fn add_newline(self: *Macro) Error!void {
        try self.add_text("\n");
    }

    pub fn clear_actions(self: *Macro) void {
        std.debug.assert(self.action_count <= action_max);
        std.debug.assert(self.text_len <= text_buffer_max);

        self.action_count = 0;
        self.text_len = 0;

        std.debug.assert(self.action_count == 0);
        std.debug.assert(self.text_len == 0);
    }
};

pub fn MacroRegistry(comptime capacity: u8) type {
    if (capacity == 0) {
        @compileError("MacroRegistry capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("MacroRegistry capacity exceeds maximum");
    }

    return struct {
        const Self = @This();

        const Slot = slot_mod.SlotManager(Macro, capacity);

        slot: Slot = Slot.init(),

        recording: bool = false,
        recording_slot: ?u8 = null,
        record_start: i64 = 0,

        playing: bool = false,
        playing_slot: ?u8 = null,
        play_index: u16 = 0,
        play_repeat: u32 = 0,
        play_thread: ?std.Thread = null,

        mutex: std.Thread.Mutex = .{},

        pub fn init() Self {
            return Self{};
        }

        pub fn is_valid(self: *const Self) bool {
            return self.slot.is_valid();
        }

        pub fn create(self: *Self, name: []const u8) Error!u32 {
            std.debug.assert(self.is_valid());

            if (name.len == 0 or name.len > name_max) {
                return Error.InvalidName;
            }

            self.mutex.lock();
            defer self.mutex.unlock();

            const allocation = self.slot.allocate() orelse return Error.RegistryFull;

            std.debug.assert(allocation.slot < capacity);
            std.debug.assert(allocation.id >= 1);

            const name_len: u8 = @intCast(name.len);

            var macro = Macro{
                .id = allocation.id,
                .active = true,
                .name_len = name_len,
            };

            @memcpy(macro.name[0..name_len], name);

            std.debug.assert(macro.is_valid());

            self.slot.entries[allocation.slot] = macro;

            return allocation.id;
        }

        pub fn get(self: *Self, id: u32) ?*Macro {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            return self.slot.get_by_id(id);
        }

        pub fn find_by_name(self: *Self, name: []const u8) ?*Macro {
            std.debug.assert(self.is_valid());

            var i: u8 = 0;

            while (i < capacity) : (i += 1) {
                const entry = &self.slot.entries[i];

                if (!entry.active) {
                    continue;
                }

                if (entry.name_len != name.len) {
                    continue;
                }

                if (std.mem.eql(u8, entry.name[0..entry.name_len], name)) {
                    return entry;
                }
            }

            return null;
        }

        pub fn delete(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            self.mutex.lock();
            defer self.mutex.unlock();

            const freed = self.slot.free_by_id(id) orelse return Error.NotFound;

            std.debug.assert(freed < capacity);
        }

        pub fn play(self: *Self, id: u32) Error!void {
            std.debug.assert(self.is_valid());
            std.debug.assert(id >= 1);

            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.playing) {
                return Error.AlreadyActive;
            }

            const slot = self.slot.find_by_id(id) orelse return Error.NotFound;

            self.playing = true;
            self.playing_slot = @intCast(slot);

            self.play_thread = std.Thread.spawn(.{}, play_thread_fn, .{self}) catch {
                self.playing = false;
                self.playing_slot = null;
                return Error.NotActive;
            };
        }

        pub fn stop(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.mutex.lock();

            if (!self.playing) {
                self.mutex.unlock();
                return;
            }

            self.playing = false;

            const thread = self.play_thread;
            self.play_thread = null;

            self.mutex.unlock();

            if (thread) |t| {
                t.join();
            }
        }

        pub fn is_playing(self: *Self) bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            return self.playing;
        }

        fn play_thread_fn(self: *Self) void {
            self.mutex.lock();

            const slot = self.playing_slot orelse {
                self.playing = false;
                self.playing_slot = null;
                self.mutex.unlock();
                return;
            };

            const macro = &self.slot.entries[slot];

            std.debug.assert(macro.is_valid());

            const repeats: u32 = if (macro.repeat_count == 0) 1 else macro.repeat_count;
            const delay_between = macro.delay_between_ms;

            self.mutex.unlock();

            var r: u32 = 0;

            while (r < repeats) : (r += 1) {
                self.mutex.lock();

                if (!self.playing) {
                    self.playing_slot = null;
                    self.mutex.unlock();
                    return;
                }

                self.mutex.unlock();

                self.execute_macro(macro);

                if (delay_between > 0 and r < repeats - 1) {
                    std.Thread.sleep(delay_between * std.time.ns_per_ms);
                }
            }

            self.mutex.lock();
            self.playing = false;
            self.playing_slot = null;
            self.mutex.unlock();
        }

        fn execute_macro(self: *Self, macro: *const Macro) void {
            _ = self;

            std.debug.assert(macro.is_valid());
            std.debug.assert(macro.action_count <= action_max);

            const hwnd = window.get_focused();

            if (hwnd) |h| {
                message.release_modifiers(h);
            }

            var i: u16 = 0;

            while (i < macro.action_count) : (i += 1) {
                std.debug.assert(i < action_max);

                const action = &macro.actions[i];

                std.debug.assert(action.is_valid());

                execute_action(action, macro, hwnd);
            }
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.stop();

            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.recording) {
                self.recording = false;
                self.recording_slot = null;
            }

            self.slot.clear();

            std.debug.assert(!self.recording);
            std.debug.assert(!self.playing);
            std.debug.assert(self.is_valid());
        }
    };
}

fn execute_action(action: *const Action, macro: *const Macro, hwnd: ?w32.HWND) void {
    std.debug.assert(action.is_valid());
    std.debug.assert(macro.is_valid());

    switch (action.kind) {
        .key_down => execute_key_down(action, hwnd),
        .key_up => execute_key_up(action, hwnd),
        .key_press => execute_key_press(action, hwnd),
        .mouse_move => execute_mouse_move(action),
        .mouse_click => execute_mouse_click(action),
        .mouse_down => execute_mouse_down(action),
        .mouse_up => execute_mouse_up(action),
        .mouse_scroll => execute_mouse_scroll(action),
        .delay => execute_delay(action),
        .text => execute_text(action, macro, hwnd),
    }
}

fn execute_key_down(action: *const Action, hwnd: ?w32.HWND) void {
    std.debug.assert(action.kind == .key_down);

    if (hwnd) |h| {
        message.send_key(h, action.key, true);
    } else {
        _ = key_sender.key_down(action.key);
    }
}

fn execute_key_up(action: *const Action, hwnd: ?w32.HWND) void {
    std.debug.assert(action.kind == .key_up);

    if (hwnd) |h| {
        message.send_key(h, action.key, false);
    } else {
        _ = key_sender.key_up(action.key);
    }
}

fn execute_key_press(action: *const Action, hwnd: ?w32.HWND) void {
    std.debug.assert(action.kind == .key_press);

    if (action.modifiers.any()) {
        _ = key_sender.combination(&action.modifiers, action.key);
    } else if (hwnd) |h| {
        message.send_key_press(h, action.key);
    } else {
        _ = key_sender.press(action.key);
    }
}

fn execute_mouse_move(action: *const Action) void {
    std.debug.assert(action.kind == .mouse_move);

    _ = mouse_sender.move_to(action.x, action.y);
}

fn execute_mouse_click(action: *const Action) void {
    std.debug.assert(action.kind == .mouse_click);
    std.debug.assert(action.button.is_valid());

    _ = mouse_sender.click(action.button);
}

fn execute_mouse_down(action: *const Action) void {
    std.debug.assert(action.kind == .mouse_down);
    std.debug.assert(action.button.is_valid());

    _ = mouse_sender.button_down(action.button);
}

fn execute_mouse_up(action: *const Action) void {
    std.debug.assert(action.kind == .mouse_up);
    std.debug.assert(action.button.is_valid());

    _ = mouse_sender.button_up(action.button);
}

fn execute_mouse_scroll(action: *const Action) void {
    std.debug.assert(action.kind == .mouse_scroll);
    std.debug.assert(action.scroll_amount >= -scroll_amount_max);
    std.debug.assert(action.scroll_amount <= scroll_amount_max);

    if (action.scroll_amount > 0) {
        _ = mouse_sender.scroll_up(@intCast(action.scroll_amount));
    }

    if (action.scroll_amount < 0) {
        _ = mouse_sender.scroll_down(@intCast(-action.scroll_amount));
    }
}

fn execute_delay(action: *const Action) void {
    std.debug.assert(action.kind == .delay);
    std.debug.assert(action.delay_ms <= delay_max_ms);

    if (action.delay_ms > 0) {
        std.Thread.sleep(action.delay_ms * std.time.ns_per_ms);
    }
}

fn execute_text(action: *const Action, macro: *const Macro, hwnd: ?w32.HWND) void {
    std.debug.assert(action.kind == .text);
    std.debug.assert(action.text_start < text_buffer_max);
    std.debug.assert(action.text_start + @as(u16, action.text_len) <= macro.text_len);

    const text = macro.get_text(action);

    if (hwnd) |h| {
        execute_text_via_message(text, h);
    } else {
        execute_text_via_typer(text);
    }
}

fn execute_text_via_message(text: []const u8, hwnd: w32.HWND) void {
    for (text) |char| {
        if (char == '\r') {
            continue;
        }

        if (char == '\n') {
            message.send_key_press(hwnd, keycode.@"return");
            continue;
        }

        message.send_char(hwnd, char);
    }
}

fn execute_text_via_typer(text: []const u8) void {
    _ = typer.send(text) catch {};
}
