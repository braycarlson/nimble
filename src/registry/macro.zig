const std = @import("std");

const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const platform = @import("../platform.zig");
const slot_mod = @import("../registry/slot.zig");

const Mutex = @import("../sync.zig").Mutex;
const assert = std.debug.assert;
const Keycode = keycode.Keycode;
const simulate_key = platform.backend.simulate.key;
const simulate_mouse = platform.backend.simulate.mouse;
const simulate_text = platform.backend.simulate.text;

const targeted: bool = platform.capabilities.window_targeted_input;

const Target = if (targeted) ?platform.backend.window.Handle else void;

fn current_target() Target {
    if (comptime !targeted) {
        return {};
    }

    return platform.backend.window.get_focused();
}

fn release_target_modifiers(target: Target) void {
    if (comptime !targeted) {
        return;
    }

    if (target) |handle| {
        _ = platform.backend.message.release_modifiers(handle);
    }
}

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

    pub fn is_valid(kind: ActionKind) bool {
        const value = @intFromEnum(kind);

        return value <= 9;
    }
};

pub const Action = struct {
    kind: ActionKind = .key_press,
    key: Keycode = .silent,
    modifiers: modifier.Set = .{},
    button: simulate_mouse.Button = .left,
    x: i32 = 0,
    y: i32 = 0,
    scroll_amount: i32 = 0,
    delay_ms: u32 = 0,
    text_start: u16 = 0,
    text_len: u8 = 0,

    pub fn is_valid(action: *const Action) bool {
        if (!action.kind.is_valid()) {
            return false;
        }

        return switch (action.kind) {
            .key_down, .key_up, .key_press => true,
            .mouse_move => true,
            .mouse_click, .mouse_down, .mouse_up => action.button.is_valid(),
            .mouse_scroll => action.scroll_amount >= -scroll_amount_max and
                action.scroll_amount <= scroll_amount_max,
            .delay => action.delay_ms <= delay_max_ms,
            .text => action.text_len > 0,
        };
    }

    pub fn key_down(k: Keycode) Action {
        const result = Action{ .kind = .key_down, .key = k };

        assert(result.is_valid());

        return result;
    }

    pub fn key_up(k: Keycode) Action {
        const result = Action{ .kind = .key_up, .key = k };

        assert(result.is_valid());

        return result;
    }

    pub fn key_press(k: Keycode) Action {
        const result = Action{ .kind = .key_press, .key = k };

        assert(result.is_valid());

        return result;
    }

    pub fn mouse_move(x: i32, y: i32) Action {
        const result = Action{ .kind = .mouse_move, .x = x, .y = y };

        assert(result.is_valid());

        return result;
    }

    pub fn mouse_click(button: simulate_mouse.Button) Action {
        assert(button.is_valid());

        const result = Action{ .kind = .mouse_click, .button = button };

        assert(result.is_valid());

        return result;
    }

    pub fn mouse_down(button: simulate_mouse.Button) Action {
        assert(button.is_valid());

        const result = Action{ .kind = .mouse_down, .button = button };

        assert(result.is_valid());

        return result;
    }

    pub fn mouse_up(button: simulate_mouse.Button) Action {
        assert(button.is_valid());

        const result = Action{ .kind = .mouse_up, .button = button };

        assert(result.is_valid());

        return result;
    }

    pub fn mouse_scroll(amount: i32) Action {
        assert(amount >= -scroll_amount_max);
        assert(amount <= scroll_amount_max);

        const result = Action{ .kind = .mouse_scroll, .scroll_amount = amount };

        assert(result.is_valid());

        return result;
    }

    pub fn delay(ms: u32) Action {
        assert(ms <= delay_max_ms);

        const result = Action{ .kind = .delay, .delay_ms = ms };

        assert(result.is_valid());

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

    pub fn get_id(macro: *const Macro) u32 {
        return macro.id;
    }

    pub fn is_active(macro: *const Macro) bool {
        return macro.active;
    }

    pub fn is_valid(macro: *const Macro) bool {
        if (!macro.active) {
            return true;
        }

        const valid_name = macro.name_len > 0 and macro.name_len <= name_max;
        const valid_actions = macro.action_count <= action_max;
        const valid_text = macro.text_len <= text_buffer_max;
        const valid_repeat = macro.repeat_count <= repeat_max;
        const valid_delay = macro.delay_between_ms <= delay_max_ms;
        const valid_id = macro.id >= 1;

        const valid_fields = valid_name and valid_actions and valid_text;
        const valid_limits = valid_repeat and valid_delay and valid_id;

        if (!valid_fields or !valid_limits) {
            return false;
        }

        return macro.validate_actions();
    }

    fn validate_actions(macro: *const Macro) bool {
        var i: u16 = 0;

        while (i < macro.action_count) : (i += 1) {
            if (!macro.actions[i].is_valid()) {
                return false;
            }

            if (macro.actions[i].kind == .text) {
                const start = macro.actions[i].text_start;
                const len = macro.actions[i].text_len;

                if (start + @as(u16, len) > macro.text_len) {
                    return false;
                }
            }
        }

        return true;
    }

    pub fn get_name(macro: *const Macro) []const u8 {
        assert(macro.name_len <= name_max);

        return macro.name[0..macro.name_len];
    }

    pub fn get_text(macro: *const Macro, action: *const Action) []const u8 {
        assert(action.kind == .text);
        assert(action.text_start < text_buffer_max);
        assert(action.text_start + @as(u16, action.text_len) <= macro.text_len);

        const start = action.text_start;
        const end = start + @as(u16, action.text_len);

        assert(end <= text_buffer_max);

        return macro.text_buffer[start..end];
    }

    pub fn remaining_action_capacity(macro: *const Macro) u16 {
        assert(macro.action_count <= action_max);

        return action_max - macro.action_count;
    }

    pub fn remaining_text_capacity(macro: *const Macro) u16 {
        assert(macro.text_len <= text_buffer_max);

        return text_buffer_max - macro.text_len;
    }

    pub fn add_action(macro: *Macro, action: Action) Error!void {
        assert(action.is_valid());
        assert(macro.action_count <= action_max);

        if (macro.action_count >= action_max) {
            return Error.BufferFull;
        }

        const slot = macro.action_count;

        macro.actions[slot] = action;
        macro.action_count += 1;

        assert(macro.action_count >= 1);
        assert(macro.action_count <= action_max);
        assert(macro.actions[slot].is_valid());
    }

    pub fn add_text(macro: *Macro, text: []const u8) Error!void {
        assert(text.len > 0);
        assert(macro.action_count <= action_max);
        assert(macro.text_len <= text_buffer_max);

        if (macro.action_count >= action_max) {
            return Error.BufferFull;
        }

        if (text.len > 255) {
            return Error.TextTooLong;
        }

        const text_len_u8: u8 = @intCast(text.len);
        const text_len_u16: u16 = @intCast(text.len);

        if (macro.text_len + text_len_u16 > text_buffer_max) {
            return Error.BufferFull;
        }

        const start = macro.text_len;
        const end = start + text_len_u16;

        assert(end <= text_buffer_max);
        assert(start < end);

        @memcpy(macro.text_buffer[start..end], text[0..text_len_u16]);

        macro.text_len = end;

        const action = Action{
            .kind = .text,
            .text_start = start,
            .text_len = text_len_u8,
        };

        assert(action.is_valid());

        macro.actions[macro.action_count] = action;
        macro.action_count += 1;

        assert(macro.text_len <= text_buffer_max);
        assert(macro.action_count <= action_max);
    }

    pub fn add_line(macro: *Macro, text: []const u8) Error!void {
        assert(macro.action_count <= action_max);
        assert(macro.text_len <= text_buffer_max);

        if (macro.action_count >= action_max) {
            return Error.BufferFull;
        }

        const text_len_max: u16 = 254;

        if (text.len > text_len_max) {
            return Error.TextTooLong;
        }

        const text_len_u16: u16 = @intCast(text.len);
        const len_total: u16 = text_len_u16 + 1;

        if (macro.text_len + len_total > text_buffer_max) {
            return Error.BufferFull;
        }

        const start = macro.text_len;

        assert(start + text_len_u16 < text_buffer_max);

        @memcpy(macro.text_buffer[start .. start + text_len_u16], text[0..text_len_u16]);
        macro.text_buffer[start + text_len_u16] = '\n';

        macro.text_len += len_total;

        const action = Action{
            .kind = .text,
            .text_start = start,
            .text_len = @intCast(len_total),
        };

        assert(action.is_valid());

        macro.actions[macro.action_count] = action;
        macro.action_count += 1;

        assert(macro.text_len <= text_buffer_max);
        assert(macro.action_count <= action_max);
    }

    pub fn add_newline(macro: *Macro) Error!void {
        try macro.add_text("\n");
    }

    pub fn clear_actions(macro: *Macro) void {
        assert(macro.action_count <= action_max);
        assert(macro.text_len <= text_buffer_max);

        macro.action_count = 0;
        macro.text_len = 0;

        assert(macro.action_count == 0);
        assert(macro.text_len == 0);
    }
};

pub fn MacroRegistryType(comptime capacity: u8) type {
    if (capacity == 0) {
        @compileError("MacroRegistryType capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("MacroRegistryType capacity exceeds maximum");
    }

    return struct {
        const Instance = @This();

        const Slot = slot_mod.SlotManagerType(Macro, capacity);

        slot: Slot = Slot.init(),

        recording: bool = false,
        recording_slot: ?u8 = null,
        record_start: i64 = 0,

        playing: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        playing_slot: ?u8 = null,
        play_index: u16 = 0,
        play_repeat: u32 = 0,
        play_thread: ?std.Thread = null,

        mutex: Mutex = .{},

        pub fn init() Instance {
            return Instance{};
        }

        pub fn is_valid(instance: *const Instance) bool {
            return instance.slot.is_valid();
        }

        pub fn create(instance: *Instance, name: []const u8) Error!u32 {
            assert(instance.is_valid());

            if (name.len == 0 or name.len > name_max) {
                return Error.InvalidName;
            }

            instance.mutex.lock();
            defer instance.mutex.unlock();

            const allocation = instance.slot.allocate() orelse return Error.RegistryFull;

            assert(allocation.slot < capacity);
            assert(allocation.id >= 1);

            const name_len: u8 = @intCast(name.len);

            var macro = Macro{
                .id = allocation.id,
                .active = true,
                .name_len = name_len,
            };

            @memcpy(macro.name[0..name_len], name);

            assert(macro.is_valid());

            instance.slot.entries[allocation.slot] = macro;

            return allocation.id;
        }

        pub fn get(instance: *Instance, id: u32) ?*Macro {
            assert(instance.is_valid());
            assert(id >= 1);

            return instance.slot.get_by_id(id);
        }

        pub fn find_by_name(instance: *Instance, name: []const u8) ?*Macro {
            assert(instance.is_valid());

            var i: u8 = 0;

            while (i < capacity) : (i += 1) {
                const entry = &instance.slot.entries[i];

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

        pub fn delete(instance: *Instance, id: u32) Error!void {
            assert(instance.is_valid());
            assert(id >= 1);

            instance.mutex.lock();
            defer instance.mutex.unlock();

            const freed = instance.slot.free_by_id(id) orelse return Error.NotFound;

            assert(freed < capacity);
        }

        pub fn play(instance: *Instance, id: u32) Error!void {
            assert(instance.is_valid());
            assert(id >= 1);

            instance.mutex.lock();
            defer instance.mutex.unlock();

            if (instance.playing.load(.seq_cst)) {
                return Error.AlreadyActive;
            }

            if (instance.play_thread) |thread| {
                thread.join();
                instance.play_thread = null;
            }

            assert(instance.play_thread == null);

            const slot = instance.slot.find_by_id(id) orelse return Error.NotFound;

            instance.playing.store(true, .seq_cst);
            instance.playing_slot = @intCast(slot);

            instance.play_thread = std.Thread.spawn(.{}, play_thread_fn, .{instance}) catch {
                instance.playing.store(false, .seq_cst);
                instance.playing_slot = null;
                return Error.NotActive;
            };
        }

        pub fn play_by_name(instance: *Instance, name: []const u8) bool {
            assert(instance.is_valid());

            if (name.len == 0 or name.len > name_max) {
                return false;
            }

            instance.mutex.lock();

            const macro = instance.find_by_name(name) orelse {
                instance.mutex.unlock();

                return false;
            };

            const id = macro.get_id();

            instance.mutex.unlock();

            assert(id >= 1);

            instance.play(id) catch return false;

            return true;
        }

        pub fn stop(instance: *Instance) void {
            assert(instance.is_valid());

            instance.mutex.lock();

            instance.playing.store(false, .seq_cst);

            const thread = instance.play_thread;
            instance.play_thread = null;

            instance.mutex.unlock();

            if (thread) |t| {
                t.join();
            }
        }

        pub fn is_playing(instance: *Instance) bool {
            return instance.playing.load(.seq_cst);
        }

        fn play_thread_fn(instance: *Instance) void {
            instance.mutex.lock();

            const slot = instance.playing_slot orelse {
                instance.playing.store(false, .seq_cst);
                instance.playing_slot = null;
                instance.mutex.unlock();
                return;
            };

            assert(instance.slot.entries[slot].is_valid());

            const macro = instance.slot.entries[slot];

            instance.mutex.unlock();

            const repeats: u32 = if (macro.repeat_count == 0) 1 else macro.repeat_count;
            const delay_between = macro.delay_between_ms;

            var r: u32 = 0;

            while (r < repeats) : (r += 1) {
                instance.mutex.lock();

                if (!instance.playing.load(.seq_cst)) {
                    instance.playing_slot = null;
                    instance.mutex.unlock();
                    return;
                }

                instance.mutex.unlock();

                instance.execute_macro(&macro);

                if (!instance.playing.load(.seq_cst)) {
                    break;
                }

                if (delay_between > 0 and r < repeats - 1) {
                    platform.backend.time.sleep_ms(delay_between);
                }
            }

            instance.mutex.lock();
            instance.playing.store(false, .seq_cst);
            instance.playing_slot = null;
            instance.mutex.unlock();
        }

        fn execute_macro(instance: *Instance, macro: *const Macro) void {
            assert(macro.is_valid());
            assert(macro.action_count <= action_max);

            const target = current_target();

            release_target_modifiers(target);

            var i: u16 = 0;

            while (i < macro.action_count) : (i += 1) {
                if (!instance.playing.load(.seq_cst)) {
                    return;
                }

                assert(i < action_max);

                const action = &macro.actions[i];

                assert(action.is_valid());

                execute_action(action, macro, target);
            }
        }

        pub fn clear(instance: *Instance) void {
            assert(instance.is_valid());

            instance.stop();

            instance.mutex.lock();
            defer instance.mutex.unlock();

            if (instance.recording) {
                instance.recording = false;
                instance.recording_slot = null;
            }

            instance.slot.clear();

            assert(!instance.recording);
            assert(!instance.playing.load(.seq_cst));
            assert(instance.is_valid());
        }
    };
}

fn execute_action(action: *const Action, macro: *const Macro, target: Target) void {
    assert(action.is_valid());
    assert(macro.is_valid());

    switch (action.kind) {
        .key_down => execute_key_down(action, target),
        .key_up => execute_key_up(action, target),
        .key_press => execute_key_press(action, target),
        .mouse_move => execute_mouse_move(action),
        .mouse_click => execute_mouse_click(action),
        .mouse_down => execute_mouse_down(action),
        .mouse_up => execute_mouse_up(action),
        .mouse_scroll => execute_mouse_scroll(action),
        .delay => execute_delay(action),
        .text => execute_text(action, macro, target),
    }
}

fn execute_key_down(action: *const Action, target: Target) void {
    assert(action.kind == .key_down);

    if (comptime targeted) {
        if (target) |handle| {
            _ = platform.backend.message.send_key(handle, action.key, true);

            return;
        }
    }

    _ = simulate_key.key_down(action.key);
}

fn execute_key_up(action: *const Action, target: Target) void {
    assert(action.kind == .key_up);

    if (comptime targeted) {
        if (target) |handle| {
            _ = platform.backend.message.send_key(handle, action.key, false);

            return;
        }
    }

    _ = simulate_key.key_up(action.key);
}

fn execute_key_press(action: *const Action, target: Target) void {
    assert(action.kind == .key_press);

    if (action.modifiers.any()) {
        _ = simulate_key.combination(&action.modifiers, action.key);

        return;
    }

    if (comptime targeted) {
        if (target) |handle| {
            _ = platform.backend.message.send_key_press(handle, action.key);

            return;
        }
    }

    _ = simulate_key.press(action.key);
}

fn execute_mouse_move(action: *const Action) void {
    assert(action.kind == .mouse_move);

    _ = simulate_mouse.move_to(action.x, action.y);
}

fn execute_mouse_click(action: *const Action) void {
    assert(action.kind == .mouse_click);
    assert(action.button.is_valid());

    _ = simulate_mouse.click(action.button);
}

fn execute_mouse_down(action: *const Action) void {
    assert(action.kind == .mouse_down);
    assert(action.button.is_valid());

    _ = simulate_mouse.button_down(action.button);
}

fn execute_mouse_up(action: *const Action) void {
    assert(action.kind == .mouse_up);
    assert(action.button.is_valid());

    _ = simulate_mouse.button_up(action.button);
}

fn execute_mouse_scroll(action: *const Action) void {
    assert(action.kind == .mouse_scroll);
    assert(action.scroll_amount >= -scroll_amount_max);
    assert(action.scroll_amount <= scroll_amount_max);

    if (action.scroll_amount > 0) {
        _ = simulate_mouse.scroll_up(@intCast(action.scroll_amount));
    }

    if (action.scroll_amount < 0) {
        _ = simulate_mouse.scroll_down(@intCast(-action.scroll_amount));
    }
}

fn execute_delay(action: *const Action) void {
    assert(action.kind == .delay);
    assert(action.delay_ms <= delay_max_ms);

    if (action.delay_ms > 0) {
        platform.backend.time.sleep_ms(action.delay_ms);
    }
}

fn execute_text(action: *const Action, macro: *const Macro, target: Target) void {
    assert(action.kind == .text);
    assert(action.text_start < text_buffer_max);
    assert(action.text_start + @as(u16, action.text_len) <= macro.text_len);

    const text = macro.get_text(action);

    if (comptime targeted) {
        if (target) |handle| {
            execute_text_via_message(text, handle);

            return;
        }
    }

    execute_text_via_simulate(text);
}

fn execute_text_via_message(text: []const u8, handle: platform.backend.window.Handle) void {
    const message = platform.backend.message;

    for (text) |char| {
        if (char == '\r') {
            continue;
        }

        if (char == '\n') {
            _ = message.send_key_press(handle, Keycode.enter);
            continue;
        }

        _ = message.send_char(handle, char);
    }
}

fn execute_text_via_simulate(text: []const u8) void {
    assert(text.len <= simulate_text.text_max);

    _ = simulate_text.send(text) catch return;
}

const testing = std.testing;

test "a key down action is valid" {
    try testing.expect(ActionKind.key_down.is_valid());
}

test "a key up action is valid" {
    try testing.expect(ActionKind.key_up.is_valid());
}

test "a key press action is valid" {
    try testing.expect(ActionKind.key_press.is_valid());
}

test "a mouse move action is valid" {
    try testing.expect(ActionKind.mouse_move.is_valid());
}

test "a mouse click action is valid" {
    try testing.expect(ActionKind.mouse_click.is_valid());
}

test "a mouse down action is valid" {
    try testing.expect(ActionKind.mouse_down.is_valid());
}

test "a mouse up action is valid" {
    try testing.expect(ActionKind.mouse_up.is_valid());
}

test "a mouse scroll action is valid" {
    try testing.expect(ActionKind.mouse_scroll.is_valid());
}

test "a delay action is valid" {
    try testing.expect(ActionKind.delay.is_valid());
}

test "a text action is valid" {
    try testing.expect(ActionKind.text.is_valid());
}

test "the action kinds are stable" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(ActionKind.key_down));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(ActionKind.key_up));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(ActionKind.key_press));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(ActionKind.mouse_move));
    try testing.expectEqual(@as(u8, 4), @intFromEnum(ActionKind.mouse_click));
    try testing.expectEqual(@as(u8, 5), @intFromEnum(ActionKind.mouse_down));
    try testing.expectEqual(@as(u8, 6), @intFromEnum(ActionKind.mouse_up));
    try testing.expectEqual(@as(u8, 7), @intFromEnum(ActionKind.mouse_scroll));
    try testing.expectEqual(@as(u8, 8), @intFromEnum(ActionKind.delay));
    try testing.expectEqual(@as(u8, 9), @intFromEnum(ActionKind.text));
}

test "a default action is empty" {
    const action = Action{};

    try testing.expectEqual(ActionKind.key_press, action.kind);
    try testing.expectEqual(Keycode.silent, action.key);
    try testing.expect(action.modifiers.none());
}

test "a key down action carries its key" {
    const action = Action.key_down(.a);

    try testing.expect(action.is_valid());
    try testing.expectEqual(ActionKind.key_down, action.kind);
    try testing.expectEqual(.a, action.key);
}

test "a key up action carries its key" {
    const action = Action.key_up(.b);

    try testing.expect(action.is_valid());
    try testing.expectEqual(ActionKind.key_up, action.kind);
    try testing.expectEqual(.b, action.key);
}

test "a key press action carries its key" {
    const action = Action.key_press(.c);

    try testing.expect(action.is_valid());
    try testing.expectEqual(ActionKind.key_press, action.kind);
    try testing.expectEqual(.c, action.key);
}

test "a mouse move action carries its position" {
    const action = Action.mouse_move(100, 200);

    try testing.expect(action.is_valid());
    try testing.expectEqual(ActionKind.mouse_move, action.kind);
    try testing.expectEqual(@as(i32, 100), action.x);
    try testing.expectEqual(@as(i32, 200), action.y);
}

test "a mouse scroll action carries its amount" {
    const action = Action.mouse_scroll(120);

    try testing.expect(action.is_valid());
    try testing.expectEqual(ActionKind.mouse_scroll, action.kind);
    try testing.expectEqual(@as(i32, 120), action.scroll_amount);
}

test "a mouse scroll action carries a negative amount" {
    const action = Action.mouse_scroll(-120);

    try testing.expect(action.is_valid());
    try testing.expectEqual(@as(i32, -120), action.scroll_amount);
}

test "a delay action carries its duration" {
    const action = Action.delay(500);

    try testing.expect(action.is_valid());
    try testing.expectEqual(ActionKind.delay, action.kind);
    try testing.expectEqual(@as(u32, 500), action.delay_ms);
}

test "an action carries the text it is built with" {
    const action = Action{
        .kind = .text,
        .text_start = 0,
        .text_len = 10,
    };

    try testing.expect(action.is_valid());
}

test "an action carries the modifiers it is built with" {
    const action = Action{
        .kind = .key_press,
        .key = .s,
        .modifiers = modifier.Set.from(.{ .ctrl = true }),
    };

    try testing.expect(action.is_valid());
    try testing.expect(action.modifiers.ctrl());
}

test "macro constants" {
    try testing.expect(action_max >= 1);
    try testing.expect(capacity_max >= 1);
    try testing.expect(name_max >= 1);
    try testing.expect(text_buffer_max >= 1);
    try testing.expect(delay_default_ms > 0);
    try testing.expect(delay_max_ms >= delay_default_ms);
    try testing.expect(repeat_max >= 1);
}

test "play_by_name returns false for an unknown name" {
    var registry = MacroRegistryType(4).init();

    try testing.expect(!registry.play_by_name("missing"));
}

test "play_by_name returns false for an out of range name length" {
    var registry = MacroRegistryType(4).init();

    const name_long = "a" ** (name_max + 1);

    try testing.expect(!registry.play_by_name(""));
    try testing.expect(!registry.play_by_name(name_long));
}

test "find_by_name locates a macro that was created" {
    var registry = MacroRegistryType(4).init();

    const id = try registry.create("copy_all");

    const found = registry.find_by_name("copy_all") orelse unreachable;

    try testing.expectEqual(id, found.get_id());
    try testing.expect(registry.find_by_name("other") == null);
}
