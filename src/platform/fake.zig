const std = @import("std");

const Clipboard = @import("fake/clipboard.zig");
const interface = @import("interface.zig");
const Keyboard = @import("fake/keyboard.zig");
const keycode = @import("../keycode.zig");
const Loop = @import("fake/loop.zig");
const modifier = @import("../modifier.zig");
const Monitor = @import("fake/monitor.zig");
const MonitorList = @import("../monitor.zig").Monitor.List;
const Mouse = @import("fake/mouse.zig");
const mouse_event = @import("../event.zig").mouse;
const position_module = @import("../position.zig");
const record_module = @import("fake/record.zig");
const Runtime = @import("fake/runtime.zig");
const State = @import("fake/state.zig");
const Time = @import("fake/time.zig");
const Timer = @import("fake/timer.zig");
const Window = @import("fake/window.zig");

const assert = std.debug.assert;

const Button = mouse_event.MouseEvent.Button;
const HookError = interface.HookError;
const Keycode = keycode.Keycode;
const Mode = interface.Mode;
const Options = interface.Options;
const Position = position_module.Position;
const RecordType = record_module.RecordType;
const ReleaseCallback = interface.ReleaseCallback;
const Tick = interface.Tick;
const TimerId = interface.TimerId;

clipboard: Clipboard,
keyboard: Keyboard,
loop: Loop,
monitor: Monitor,
mouse: Mouse,
record: Record,
runtime: Runtime,
state: State,
time: Time,
timer: Timer,
window: Window,

const Fake = @This();

pub const ClipboardError = Clipboard.Error;
pub const Error = error{};
pub const Record = RecordType(record_count_max);
pub const RemoteClient = @import("fake/remote_client.zig");
pub const Snapshot = State.Snapshot;
pub const TextError = error{ SendFailed, TextTooLong };
pub const WindowHandle = Window.Handle;

pub const capabilities = interface.Capabilities{
    .clipboard = true,
    .injected_flag_exact = true,
    .monitor_query = true,
    .remote = true,
    .window_filter = true,
    .window_targeted_input = true,
};

pub const clipboard_text_bytes_max: u32 = Clipboard.text_bytes_max;
pub const scroll_clicks_max: u32 = 32;
pub const text_bytes_max: u32 = 256;

const ctrl = modifier.Set.from(.{ .ctrl = true });
const iteration_count_max: u32 = Loop.capacity;
const record_count_max: u16 = 4096;
const text_delay_ms_default: u32 = 1;

const modifier_codes = [_]Keycode{
    .control_left,
    .control_right,
    .alt_left,
    .alt_right,
    .shift_left,
    .shift_right,
    .super_left,
    .super_right,
};

comptime {
    assert(scroll_clicks_max > 0);
    assert(text_bytes_max > 0);
    assert(text_bytes_max <= record_module.text_bytes_max);
    assert(iteration_count_max == Loop.capacity);
    assert(modifier_codes.len == modifier.Set.kind_count * 2);

    interface.assert_backend(Fake);
}

pub fn init(fake: *Fake, options: Options) Error!void {
    assert(options.is_valid());

    fake.* = .{
        .clipboard = .{},
        .keyboard = .{},
        .loop = .{},
        .monitor = .{},
        .mouse = .{},
        .record = .{},
        .runtime = .init(options),
        .state = .{},
        .time = .{},
        .timer = .{},
        .window = .{},
    };

    assert(fake.runtime_mode() == options.mode);
    assert(fake.record.len() == 0);
}

pub fn deinit(fake: *Fake) void {
    assert(fake.runtime.options.is_valid());

    fake.* = undefined;
}

pub fn now_ms(fake: *const Fake) i64 {
    return fake.time.now_ms();
}

pub fn sleep_ms(fake: *Fake, duration_ms: u32) void {
    assert(duration_ms <= interface.sleep_ms_max);

    fake.time.sleep_ms(duration_ms);
}

pub fn runtime_mode(fake: *const Fake) Mode {
    return fake.runtime.mode();
}

pub fn runtime_release_grab(fake: *Fake) void {
    fake.runtime.release_grab();

    assert(fake.runtime_mode() == .observe);
}

pub fn runtime_acquire_grab(fake: *Fake) void {
    fake.runtime.acquire_grab();

    if (fake.runtime.grab_wanted) assert(fake.runtime_mode() == .grab);
}

pub fn runtime_set_release_callback(fake: *Fake, callback: ?ReleaseCallback) void {
    fake.runtime.set_release_callback(callback);
}

pub fn loop_run(fake: *Fake) void {
    fake.loop.stopped = false;

    var iteration: u32 = 0;

    while (iteration < iteration_count_max) : (iteration += 1) {
        if (!fake.loop_poll(0)) {
            break;
        }
    }

    assert(iteration < iteration_count_max);
}

pub fn loop_poll(fake: *Fake, timeout_ms: u32) bool {
    assert(timeout_ms <= std.math.maxInt(i32));

    if (fake.loop.stopped) return false;

    if (timeout_ms > 0) {
        fake.time.advance(timeout_ms);
    }

    _ = fake.timer.fire_due(fake.time.now_ms());

    const event = fake.loop.next() orelse return false;

    switch (event) {
        .key => |key| {
            if (key.down) {
                fake.state.set_down(key.value);
            } else {
                fake.state.set_up(key.value);
            }

            fake.loop.record_response(fake.keyboard.feed(&key));
        },
        .mouse => |value| fake.loop.record_response(fake.mouse.feed(&value)),
        .advance_ms => |duration| {
            fake.time.advance(duration);

            _ = fake.timer.fire_due(fake.time.now_ms());
        },
    }

    return true;
}

pub fn loop_stop(fake: *Fake) void {
    fake.loop.stop();

    assert(fake.loop.stopped);
}

pub fn keyboard_install(fake: *Fake, comptime Owner: type, owner: *Owner) HookError!void {
    try fake.keyboard.install(Owner, owner);

    assert(fake.keyboard.is_installed());
}

pub fn keyboard_remove(fake: *Fake) void {
    fake.keyboard.remove();

    assert(!fake.keyboard.is_installed());
}

pub fn mouse_install(fake: *Fake, comptime Owner: type, owner: *Owner) HookError!void {
    try fake.mouse.install(Owner, owner);

    assert(fake.mouse.is_installed());
}

pub fn mouse_remove(fake: *Fake) void {
    fake.mouse.remove();

    assert(!fake.mouse.is_installed());
}

pub fn key_press(fake: *Fake, code: Keycode) bool {
    fake.record.push(.{ .kind = .key_press, .code = code });

    return true;
}

pub fn key_down(fake: *Fake, code: Keycode) bool {
    fake.state.set_down(code);
    fake.record.push(.{ .kind = .key_down, .code = code, .down = true });

    return true;
}

pub fn key_up(fake: *Fake, code: Keycode) bool {
    fake.state.set_up(code);
    fake.record.push(.{ .kind = .key_up, .code = code, .down = false });

    return true;
}

pub fn key_suppress(fake: *Fake, code: Keycode) bool {
    fake.record.push(.{ .kind = .key_dummy });
    fake.record.push(.{ .kind = .key_up, .code = code, .down = false });

    return true;
}

pub fn key_dummy(fake: *Fake) bool {
    fake.record.push(.{ .kind = .key_dummy });

    return true;
}

pub fn key_combination(fake: *Fake, modifiers: *const modifier.Set, code: Keycode) bool {
    assert(modifiers.flags <= modifier.flag_all);

    fake.record.push(.{ .kind = .key_combination, .code = code, .modifiers = modifiers.* });

    return true;
}

pub fn mouse_click(fake: *Fake, button: Button) bool {
    const down = fake.mouse_button_down(button);
    const up = fake.mouse_button_up(button);

    return down and up;
}

pub fn mouse_button_down(fake: *Fake, button: Button) bool {
    assert(button.is_valid());

    fake.record.push(.{ .kind = .mouse_down, .button = @backingInt(button), .down = true });

    return true;
}

pub fn mouse_button_up(fake: *Fake, button: Button) bool {
    assert(button.is_valid());

    fake.record.push(.{ .kind = .mouse_up, .button = @backingInt(button), .down = false });

    return true;
}

pub fn mouse_move_to(fake: *Fake, position: Position) bool {
    fake.monitor.set_cursor_position(position);
    fake.record.push(.{ .kind = .mouse_move, .x = position.x, .y = position.y });

    return true;
}

pub fn mouse_move_relative(fake: *Fake, offset: Position) bool {
    const current = fake.monitor.get_cursor_position();

    return fake.mouse_move_to(.{ .x = current.x + offset.x, .y = current.y + offset.y });
}

pub fn mouse_get_position(fake: *Fake) Position {
    return fake.monitor.get_cursor_position();
}

pub fn mouse_scroll_up(fake: *Fake, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    fake.record.push(.{ .kind = .mouse_scroll, .amount = @intCast(clicks) });

    return true;
}

pub fn mouse_scroll_down(fake: *Fake, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    fake.record.push(.{ .kind = .mouse_scroll, .amount = -@as(i32, @intCast(clicks)) });

    return true;
}

pub fn mouse_scroll_left(fake: *Fake, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    fake.record.push(.{ .kind = .mouse_scroll, .x = -@as(i32, @intCast(clicks)) });

    return true;
}

pub fn mouse_scroll_right(fake: *Fake, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    fake.record.push(.{ .kind = .mouse_scroll, .x = @intCast(clicks) });

    return true;
}

pub fn text_send(fake: *Fake, text: []const u8) TextError!u32 {
    assert(text.len <= text_bytes_max);

    return fake.text_send_with_delay(text, text_delay_ms_default);
}

pub fn text_send_with_delay(fake: *Fake, text: []const u8, delay_ms: u32) TextError!u32 {
    assert(delay_ms <= interface.sleep_ms_max);
    assert(text.len <= text_bytes_max);

    if (text.len > text_bytes_max) {
        return error.TextTooLong;
    }

    fake.record.push_text(.text_send, text);
    fake.time.advance(delay_ms);

    const result: u32 = @intCast(text.len);

    assert(result <= text_bytes_max);

    return result;
}

pub fn timer_start(fake: *Fake, interval_ms: u32, tick: Tick, context: *anyopaque) ?TimerId {
    assert(interval_ms >= interface.timer_interval_ms_min);
    assert(interval_ms <= interface.timer_interval_ms_max);

    return fake.timer.start(fake.time.now_ms(), interval_ms, tick, context);
}

pub fn timer_stop(fake: *Fake, id: TimerId) bool {
    assert(id != 0);

    return fake.timer.stop(id);
}

pub fn state_capture(fake: *const Fake) Snapshot {
    return fake.state.capture();
}

pub fn state_is_key_down_at(_: *const Fake, snapshot: *const Snapshot, code: Keycode) bool {
    return snapshot.is_key_down(code);
}

pub fn window_foreground(fake: *const Fake) ?WindowHandle {
    return fake.window.foreground();
}

pub fn window_get_focused(fake: *const Fake) ?WindowHandle {
    return fake.window.foreground();
}

pub fn window_is_fullscreen(fake: *const Fake, handle: WindowHandle) bool {
    assert(handle != Window.handle_none);

    return fake.window.is_fullscreen(handle);
}

pub fn window_is_maximized(fake: *const Fake, handle: WindowHandle) bool {
    assert(handle != Window.handle_none);

    return fake.window.is_maximized(handle);
}

pub fn window_class_matches(fake: *const Fake, handle: WindowHandle, target: []const u8) bool {
    assert(handle != Window.handle_none);
    assert(target.len >= 1);

    return fake.window.class_matches(handle, target);
}

pub fn window_title_matches(fake: *const Fake, handle: WindowHandle, target: []const u8) bool {
    assert(handle != Window.handle_none);
    assert(target.len >= 1);

    return fake.window.title_matches(handle, target);
}

pub fn monitor_enumerate(fake: *Fake, list: *MonitorList) void {
    assert(list.count == 0);
    assert(fake.runtime.options.is_valid());

    Monitor.enumerate(list);
}

pub fn clipboard_set(fake: *Fake, text: []const u8) ClipboardError!void {
    assert(text.len >= 1);

    try fake.clipboard.set(text);

    fake.record.push_text(.clipboard_set, text);
}

pub fn clipboard_paste(fake: *Fake) bool {
    return fake.key_combination(&ctrl, .v);
}

pub fn clipboard_replace(fake: *Fake, select_count: u32, text: []const u8) ClipboardError!void {
    assert(select_count > 0);
    assert(text.len > 0);

    if (select_count > Clipboard.select_count_max) {
        return error.CountInvalid;
    }

    if (!fake.key_down(.shift_left)) return error.SendFailed;

    for (0..select_count) |_| {
        if (!fake.key_press(.arrow_left)) return error.SendFailed;
    }

    if (!fake.key_up(.shift_left)) return error.SendFailed;

    try fake.clipboard_set(text);

    if (!fake.clipboard_paste()) {
        return error.SendFailed;
    }
}

pub fn message_send_key(fake: *Fake, handle: WindowHandle, code: Keycode, down: bool) bool {
    assert(handle != Window.handle_none);

    fake.record.push(.{ .kind = .message_key, .code = code, .down = down });

    return true;
}

pub fn message_send_key_press(fake: *Fake, handle: WindowHandle, code: Keycode) bool {
    assert(handle != Window.handle_none);

    const down = fake.message_send_key(handle, code, true);
    const up = fake.message_send_key(handle, code, false);

    return down and up;
}

pub fn message_send_char(fake: *Fake, handle: WindowHandle, character: u16) bool {
    assert(handle != Window.handle_none);

    fake.record.push(.{ .kind = .message_char, .amount = character });

    return true;
}

pub fn message_release_modifiers(fake: *Fake, handle: WindowHandle) bool {
    assert(handle != Window.handle_none);

    for (modifier_codes) |code| {
        _ = fake.message_send_key(handle, code, false);
    }

    return true;
}

const testing = std.testing;

test init {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{ .mode = .grab });
    defer fake.deinit();

    _ = fake.key_press(.a);
    fake.monitor.set_cursor_position(.{ .x = 40, .y = 30 });
    fake.time.advance(500);

    try testing.expectEqual(@as(u16, 1), fake.record.len());
    try testing.expect(fake.mouse_get_position().eql(.{ .x = 40, .y = 30 }));
    try testing.expectEqual(@as(i64, 500), fake.now_ms());
    try testing.expectEqual(Mode.grab, fake.runtime_mode());
}

test "text longer than the record keeps is stored whole and recorded as a prefix" {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    const lengths = [_]u16{ record_module.text_bytes_max + 1, Clipboard.text_bytes_max };

    for (lengths) |text_length| {
        var text: [Clipboard.text_bytes_max]u8 = @splat('n');
        var buffer: [Clipboard.text_bytes_max]u8 = undefined;

        try fake.clipboard_set(text[0..text_length]);
        try testing.expectEqual(@as(usize, text_length), (try fake.clipboard.get(&buffer)).len);

        const entry = fake.record.last() orelse return error.MissingEntry;

        try testing.expectEqual(@as(usize, record_module.text_bytes_max), entry.body().len);
    }
}

test "replacing selects the old text before pasting the new" {
    const fake = try testing.allocator.create(Fake);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    try fake.clipboard_replace(3, "abc");

    const refused = fake.clipboard_replace(Clipboard.select_count_max + 1, "x");

    try testing.expectEqual(@as(u16, 3), fake.record.count_of(.key_press));
    try testing.expectError(error.CountInvalid, refused);
}

test "every Fake declaration compiles" {
    testing.refAllDecls(Fake);
    testing.refAllDecls(Fake.RemoteClient);
}
