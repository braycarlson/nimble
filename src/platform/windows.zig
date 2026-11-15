const std = @import("std");

const clipboard = @import("windows/clipboard.zig");
const Deferred = @import("windows/deferred.zig");
const interface = @import("interface.zig");
const Keyboard = @import("windows/keyboard.zig");
const keycode = @import("../keycode.zig");
const Loop = @import("windows/loop.zig");
const modifier = @import("../modifier.zig");
const monitor = @import("windows/monitor.zig");
const MonitorList = @import("../monitor.zig").Monitor.List;
const Mouse = @import("windows/mouse.zig");
const mouse_event = @import("../event.zig").mouse;
const position_module = @import("../position.zig");
const Rescue = @import("windows/rescue.zig");
const Runtime = @import("windows/runtime.zig");
const simulate_key = @import("windows/simulate.zig").key;
const simulate_message = @import("windows/simulate.zig").message;
const simulate_mouse = @import("windows/simulate.zig").mouse;
const simulate_text = @import("windows/simulate.zig").text;
const state = @import("windows/state.zig");
const sync = @import("windows/sync.zig");
const time = @import("windows/time.zig");
const Timer = @import("windows/timer.zig");
const win32 = @import("windows/win32.zig");
const window = @import("windows/window.zig");

const assert = std.debug.assert;

const Button = mouse_event.MouseEvent.Button;
const HookError = interface.HookError;
const Keycode = keycode.Keycode;
const Mode = interface.Mode;
const Options = interface.Options;
const Position = position_module.Position;
const ReleaseCallback = interface.ReleaseCallback;
const Tick = interface.Tick;
const TimerId = interface.TimerId;

deferred: Deferred,
keyboard: Keyboard,
loop: Loop,
mouse: Mouse,
rescue: Rescue,
runtime: Runtime,
timer: Timer,

const Windows = @This();

pub const ClipboardError = clipboard.Error;
pub const Condition = sync.Condition;
pub const Error = error{RuntimeOpen};
pub const Mutex = sync.Mutex;
pub const RemoteClient = @import("windows/remote_client.zig");
pub const Snapshot = state.Snapshot;
pub const TextError = simulate_text.Error;
pub const WindowHandle = window.Handle;

pub const capabilities = interface.Capabilities{
    .clipboard = true,
    .injected_flag_exact = true,
    .monitor_query = true,
    .remote = true,
    .window_filter = true,
    .window_targeted_input = true,
};

pub const clipboard_text_bytes_max: u32 = clipboard.text_bytes_max;
pub const scroll_clicks_max: u32 = simulate_mouse.scroll_clicks_max;
pub const text_bytes_max: u32 = simulate_text.text_max;

var instance: std.atomic.Value(?*Windows) = .init(null);

comptime {
    assert(time.sleep_ms_max >= interface.sleep_ms_max);

    interface.assert_backend(Windows);
}

pub fn init(backend: *Windows, options: Options) Error!void {
    assert(options.is_valid());

    if (instance.cmpxchgStrong(null, backend, .seq_cst, .seq_cst) != null) {
        return error.RuntimeOpen;
    }

    backend.wire();
    backend.runtime.open(options);

    assert(instance.load(.seq_cst) == backend);
    assert(backend.runtime.is_open());
}

pub fn wire(backend: *Windows) void {
    backend.* = .{
        .deferred = .{ .procedure = deferred_fire },
        .keyboard = .{},
        .loop = .{},
        .mouse = .{},
        .rescue = .{},
        .runtime = .{},
        .timer = .{},
    };

    assert(!backend.runtime.is_open());
    assert(!backend.timer.is_armed());
}

pub fn deinit(backend: *Windows) void {
    assert(instance.load(.seq_cst) == backend);
    assert(!backend.keyboard.is_installed());
    assert(!backend.mouse.is_installed());

    backend.deferred.cancel();
    backend.runtime.close();

    instance.store(null, .seq_cst);
    backend.* = undefined;

    assert(instance.load(.seq_cst) == null);
}

fn keyboard_hook(
    code: c_int,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(.c) win32.LRESULT {
    const backend = instance.load(.seq_cst) orelse unreachable;

    assert(backend.runtime.is_open());

    return backend.keyboard.procedure(&backend.rescue, &backend.runtime, code, wparam, lparam);
}

fn mouse_hook(
    code: c_int,
    wparam: win32.WPARAM,
    lparam: win32.LPARAM,
) callconv(.c) win32.LRESULT {
    const backend = instance.load(.seq_cst) orelse unreachable;

    assert(backend.runtime.is_open());

    return backend.mouse.procedure(&backend.rescue, &backend.runtime, code, wparam, lparam);
}

fn timer_fire(_: ?win32.HWND, _: u32, _: usize, _: u32) callconv(.c) void {
    const backend = instance.load(.seq_cst) orelse unreachable;

    assert(backend.timer.is_armed());

    backend.timer.fire();
}

fn deferred_fire(_: ?win32.HWND, _: u32, _: usize, _: u32) callconv(.c) void {
    const backend = instance.load(.seq_cst) orelse unreachable;

    assert(backend.deferred.procedure != null);

    backend.deferred.fire();
}

pub fn now_ms(_: *const Windows) i64 {
    return time.now_ms();
}

pub fn sleep_ms(backend: *Windows, duration_ms: u32) void {
    assert(duration_ms <= interface.sleep_ms_max);

    time.sleep_ms(&backend.loop, duration_ms);
}

pub fn runtime_mode(backend: *const Windows) Mode {
    return backend.runtime.mode();
}

pub fn runtime_release_grab(backend: *Windows) void {
    backend.runtime.release_grab();

    assert(backend.runtime_mode() == .observe);
}

pub fn runtime_acquire_grab(backend: *Windows) void {
    backend.runtime.acquire_grab();
}

pub fn runtime_set_release_callback(backend: *Windows, callback: ?ReleaseCallback) void {
    backend.runtime.set_release_callback(callback);
}

pub fn loop_run(backend: *Windows) void {
    backend.loop.run(&backend.runtime);
}

pub fn loop_poll(backend: *Windows, timeout_ms: u32) bool {
    assert(timeout_ms <= std.math.maxInt(i32));

    return backend.loop.poll(&backend.runtime, timeout_ms);
}

pub fn loop_stop(backend: *Windows) void {
    backend.loop.stop();
}

pub fn keyboard_install(backend: *Windows, comptime Owner: type, owner: *Owner) HookError!void {
    try backend.keyboard.install(Owner, owner, keyboard_hook, &backend.loop);

    assert(backend.keyboard.is_installed());
}

pub fn keyboard_remove(backend: *Windows) void {
    backend.keyboard.remove(&backend.loop);

    assert(!backend.keyboard.is_installed());
}

pub fn mouse_install(backend: *Windows, comptime Owner: type, owner: *Owner) HookError!void {
    try backend.mouse.install(Owner, owner, mouse_hook, &backend.loop);

    assert(backend.mouse.is_installed());
}

pub fn mouse_remove(backend: *Windows) void {
    backend.mouse.remove(&backend.loop);

    assert(!backend.mouse.is_installed());
}

pub fn key_press(_: *Windows, code: Keycode) bool {
    return simulate_key.press(code);
}

pub fn key_down(_: *Windows, code: Keycode) bool {
    return simulate_key.key_down(code);
}

pub fn key_up(_: *Windows, code: Keycode) bool {
    return simulate_key.key_up(code);
}

pub fn key_suppress(_: *Windows, code: Keycode) bool {
    return simulate_key.suppress(code);
}

pub fn key_dummy(_: *Windows) bool {
    return simulate_key.dummy();
}

pub fn key_combination(_: *Windows, modifiers: *const modifier.Set, code: Keycode) bool {
    assert(modifiers.flags <= modifier.flag_all);

    return simulate_key.combination(modifiers, code);
}

pub fn mouse_click(_: *Windows, button: Button) bool {
    return simulate_mouse.click(button);
}

pub fn mouse_button_down(_: *Windows, button: Button) bool {
    return simulate_mouse.button_down(button);
}

pub fn mouse_button_up(_: *Windows, button: Button) bool {
    return simulate_mouse.button_up(button);
}

pub fn mouse_move_to(_: *Windows, position: Position) bool {
    return simulate_mouse.move_to(position);
}

pub fn mouse_move_relative(_: *Windows, offset: Position) bool {
    return simulate_mouse.move_relative(offset);
}

pub fn mouse_get_position(_: *Windows) Position {
    return simulate_mouse.get_position();
}

pub fn mouse_scroll_up(_: *Windows, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    return simulate_mouse.scroll_up(clicks);
}

pub fn mouse_scroll_down(_: *Windows, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    return simulate_mouse.scroll_down(clicks);
}

pub fn mouse_scroll_left(_: *Windows, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    return simulate_mouse.scroll_left(clicks);
}

pub fn mouse_scroll_right(_: *Windows, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    return simulate_mouse.scroll_right(clicks);
}

pub fn text_send(backend: *Windows, text: []const u8) TextError!u32 {
    assert(text.len <= text_bytes_max);

    return simulate_text.send(&backend.loop, text);
}

pub fn text_send_with_delay(backend: *Windows, text: []const u8, delay_ms: u32) TextError!u32 {
    assert(text.len <= text_bytes_max);
    assert(delay_ms <= interface.sleep_ms_max);

    return simulate_text.send_with_delay(&backend.loop, text, delay_ms);
}

pub fn timer_start(backend: *Windows, interval_ms: u32, tick: Tick, context: *anyopaque) ?TimerId {
    assert(interval_ms >= interface.timer_interval_ms_min);
    assert(interval_ms <= interface.timer_interval_ms_max);

    return backend.timer.start(interval_ms, tick, context, timer_fire);
}

pub fn timer_stop(backend: *Windows, id: TimerId) bool {
    assert(id != 0);

    return backend.timer.stop(id);
}

pub fn state_capture(_: *const Windows) Snapshot {
    return state.capture();
}

pub fn state_is_key_down_at(_: *const Windows, snapshot: *const Snapshot, code: Keycode) bool {
    return state.is_key_down_at(snapshot, code);
}

pub fn window_foreground(_: *const Windows) ?WindowHandle {
    return window.foreground();
}

pub fn window_get_focused(_: *const Windows) ?WindowHandle {
    return window.get_focused();
}

pub fn window_is_fullscreen(_: *const Windows, handle: WindowHandle) bool {
    return window.is_fullscreen(handle);
}

pub fn window_is_maximized(_: *const Windows, handle: WindowHandle) bool {
    return window.is_maximized(handle);
}

pub fn window_class_matches(_: *const Windows, handle: WindowHandle, target: []const u8) bool {
    assert(target.len >= 1);

    return window.class_matches(handle, target);
}

pub fn window_title_matches(_: *const Windows, handle: WindowHandle, target: []const u8) bool {
    assert(target.len >= 1);

    return window.title_matches(handle, target);
}

pub fn monitor_enumerate(_: *Windows, list: *MonitorList) void {
    monitor.enumerate(list);
}

pub fn clipboard_set(_: *Windows, text: []const u8) ClipboardError!void {
    assert(text.len >= 1);
    assert(text.len <= clipboard_text_bytes_max);

    return clipboard.set(text);
}

pub fn clipboard_paste(_: *Windows) bool {
    return clipboard.paste();
}

pub fn clipboard_replace(_: *Windows, select_count: u32, text: []const u8) ClipboardError!void {
    assert(select_count >= 1);
    assert(text.len >= 1);

    return clipboard.replace(select_count, text);
}

pub fn message_send_key(_: *Windows, handle: WindowHandle, code: Keycode, down: bool) bool {
    return simulate_message.send_key(handle, code, down);
}

pub fn message_send_key_press(_: *Windows, handle: WindowHandle, code: Keycode) bool {
    return simulate_message.send_key_press(handle, code);
}

pub fn message_send_char(_: *Windows, handle: WindowHandle, character: u16) bool {
    return simulate_message.send_char(handle, character);
}

pub fn message_release_modifiers(_: *Windows, handle: WindowHandle) bool {
    return simulate_message.release_modifiers(handle);
}

const testing = std.testing;

const pump_ms_max: i64 = 1000;
const pump_message_max: u32 = 64;

const Recorder = struct {
    order: [Deferred.entry_count_max + 1]u32 = @splat(0),
    count: u32 = 0,

    fn run(entry: *const Deferred.Entry) void {
        const recorder: *Recorder = @ptrCast(@alignCast(entry.owner));

        recorder.order[recorder.count] = entry.id;
        recorder.count += 1;
    }
};

fn pump(recorder: *const Recorder, count: u32, duration_ms: i64) void {
    assert(duration_ms <= pump_ms_max);

    const start_ms = time.now_ms();

    var message: win32.MSG = std.mem.zeroes(win32.MSG);

    while (time.now_ms() - start_ms < duration_ms) {
        if (recorder.count >= count) break;

        var dispatched: u32 = 0;

        while (dispatched < pump_message_max) : (dispatched += 1) {
            if (win32.PeekMessageW(&message, null, 0, 0, win32.PM_REMOVE) == 0) break;

            _ = win32.DispatchMessageW(&message);
        }

        win32.Sleep(5);
    }
}

test "a second runtime in one process is refused" {
    var first: Windows = undefined;
    var second: Windows = undefined;

    instance.store(&first, .seq_cst);
    defer instance.store(null, .seq_cst);

    try testing.expectError(error.RuntimeOpen, second.init(.{}));
    try testing.expect(instance.load(.seq_cst) == &first);
}

test "a deferred entry runs once the message loop turns, not when it is pushed" {
    var backend: Windows = undefined;
    var recorder = Recorder{};

    backend.wire();

    instance.store(&backend, .seq_cst);
    defer instance.store(null, .seq_cst);

    backend.deferred.push(.{ .run = Recorder.run, .owner = &recorder, .id = 7 });

    try testing.expectEqual(@as(u32, 0), recorder.count);

    pump(&recorder, 1, pump_ms_max);

    try testing.expectEqual(@as(u32, 1), recorder.count);
    try testing.expectEqual(@as(u32, 7), recorder.order[0]);
}

test "deferred entries run in the order they were pushed" {
    var backend: Windows = undefined;
    var recorder = Recorder{};

    backend.wire();

    instance.store(&backend, .seq_cst);
    defer instance.store(null, .seq_cst);

    backend.deferred.push(.{ .run = Recorder.run, .owner = &recorder, .id = 1 });
    backend.deferred.push(.{ .run = Recorder.run, .owner = &recorder, .id = 2 });
    backend.deferred.push(.{ .run = Recorder.run, .owner = &recorder, .id = 3 });

    pump(&recorder, 3, pump_ms_max);

    try testing.expectEqualSlices(u32, &.{ 1, 2, 3 }, recorder.order[0..recorder.count]);
}

test "a full deferred queue drops what does not fit" {
    testing.log_level = .err;

    var backend: Windows = undefined;
    var recorder = Recorder{};
    var id: u32 = 0;

    backend.wire();

    instance.store(&backend, .seq_cst);
    defer instance.store(null, .seq_cst);

    while (id <= Deferred.entry_count_max) : (id += 1) {
        backend.deferred.push(.{ .run = Recorder.run, .owner = &recorder, .id = id });
    }

    pump(&recorder, Deferred.entry_count_max + 1, 200);

    const last = Deferred.entry_count_max - 1;

    try testing.expectEqual(@as(u32, Deferred.entry_count_max), recorder.count);
    try testing.expectEqual(@as(u32, last), recorder.order[last]);
}

test "every Windows declaration compiles" {
    testing.refAllDecls(Windows);
    testing.refAllDecls(Windows.RemoteClient);
}
