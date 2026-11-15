const std = @import("std");

const Clipboard = @import("linux/clipboard.zig");
const Hotplug = @import("linux/hotplug.zig");
const interface = @import("interface.zig");
const Keyboard = @import("linux/keyboard.zig");
const keycode = @import("../keycode.zig");
const Loop = @import("linux/loop.zig");
const modifier = @import("../modifier.zig");
const Monitor = @import("linux/monitor.zig");
const MonitorList = @import("../monitor.zig").Monitor.List;
const Mouse = @import("linux/mouse.zig");
const mouse_event = @import("../event.zig").mouse;
const position_module = @import("../position.zig");
const remote_client = @import("linux/remote.zig").client;
const Rescue = @import("linux/rescue.zig");
const Runtime = @import("linux/runtime.zig");
const simulate_key = @import("linux/simulate.zig").key;
const simulate_mouse = @import("linux/simulate.zig").mouse;
const simulate_text = @import("linux/simulate.zig").text;
const State = @import("linux/state.zig");
const Suspension = @import("linux/suspension.zig");
const sync = @import("linux/sync.zig");
const time = @import("linux/time.zig");
const Timer = @import("linux/timer.zig");

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

clipboard: Clipboard,
hotplug: Hotplug,
keyboard: Keyboard,
loop: Loop,
monitor: Monitor,
mouse: Mouse,
rescue: Rescue,
runtime: Runtime,
state: State,
suspension: Suspension,
timer: Timer,

const Linux = @This();

pub const ClipboardError = Clipboard.Error;
pub const Condition = sync.Condition;
pub const Error = Runtime.Error || error{RuntimeOpen};
pub const Mutex = sync.Mutex;
pub const RemoteClient = remote_client.Client;
pub const Snapshot = State.Snapshot;
pub const TextError = simulate_text.Error;

pub const capabilities = interface.Capabilities{
    .clipboard = true,
    .injected_flag_exact = false,
    .monitor_query = true,
    .remote = true,
    .window_filter = false,
    .window_targeted_input = false,
};

pub const clipboard_text_bytes_max: u32 = Clipboard.text_bytes_max;
pub const scroll_clicks_max: u32 = simulate_mouse.scroll_clicks_max;
pub const text_bytes_max: u32 = simulate_text.text_max;

var instance: std.atomic.Value(?*Linux) = .init(null);

comptime {
    assert(time.sleep_ms_max >= interface.sleep_ms_max);

    interface.assert_backend(Linux);
}

pub fn init(backend: *Linux, options: Options) Error!void {
    assert(options.is_valid());

    if (instance.cmpxchgStrong(null, backend, .seq_cst, .seq_cst) != null) {
        return error.RuntimeOpen;
    }

    errdefer instance.store(null, .seq_cst);

    backend.wire();

    try backend.runtime.open(options, on_terminal_stop);

    assert(instance.load(.seq_cst) == backend);
    assert(backend.runtime.is_open());
}

pub fn wire(backend: *Linux) void {
    backend.* = .{
        .clipboard = .{},
        .hotplug = .{},
        .keyboard = .{},
        .loop = .{ .peers = undefined },
        .monitor = .{},
        .mouse = .{},
        .rescue = .{},
        .runtime = .{ .peers = undefined },
        .state = .{},
        .suspension = .{},
        .timer = .{},
    };

    backend.loop.peers = .{
        .hotplug = &backend.hotplug,
        .keyboard = &backend.keyboard,
        .mouse = &backend.mouse,
        .rescue = &backend.rescue,
        .runtime = &backend.runtime,
        .timer = &backend.timer,
    };

    backend.runtime.peers = .{
        .clipboard = &backend.clipboard,
        .hotplug = &backend.hotplug,
        .monitor = &backend.monitor,
        .rescue = &backend.rescue,
        .state = &backend.state,
        .suspension = &backend.suspension,
        .timer = &backend.timer,
    };

    assert(!backend.runtime.is_open());
    assert(!backend.keyboard.is_installed());
}

pub fn deinit(backend: *Linux) void {
    assert(instance.load(.seq_cst) == backend);
    assert(backend.runtime.is_open());

    backend.runtime.close();

    instance.store(null, .seq_cst);
    backend.* = undefined;

    assert(instance.load(.seq_cst) == null);
}

fn on_terminal_stop(_: Suspension.Signal) callconv(.c) void {
    const backend = instance.load(.seq_cst) orelse unreachable;

    assert(backend.suspension.is_installed());

    backend.suspension.request();
}

pub fn now_ms(_: *const Linux) i64 {
    return time.now_ms();
}

pub fn sleep_ms(_: *Linux, duration_ms: u32) void {
    assert(duration_ms <= interface.sleep_ms_max);

    time.sleep_ms(duration_ms);
}

pub fn runtime_mode(backend: *const Linux) Mode {
    return backend.runtime.mode();
}

pub fn runtime_release_grab(backend: *Linux) void {
    backend.runtime.release_grab();

    assert(backend.runtime_mode() == .observe);
}

pub fn runtime_acquire_grab(backend: *Linux) void {
    backend.runtime.acquire_grab();
}

pub fn runtime_set_release_callback(backend: *Linux, callback: ?ReleaseCallback) void {
    backend.runtime.set_release_callback(callback);
}

pub fn loop_run(backend: *Linux) void {
    backend.loop.run();
}

pub fn loop_poll(backend: *Linux, timeout_ms: u32) bool {
    assert(timeout_ms <= std.math.maxInt(i32));

    return backend.loop.poll(timeout_ms);
}

pub fn loop_stop(backend: *Linux) void {
    backend.loop.stop();
}

pub fn keyboard_install(backend: *Linux, comptime Owner: type, owner: *Owner) HookError!void {
    try backend.keyboard.install(Owner, owner);

    assert(backend.keyboard.is_installed());
}

pub fn keyboard_remove(backend: *Linux) void {
    backend.keyboard.remove();

    assert(!backend.keyboard.is_installed());
}

pub fn mouse_install(backend: *Linux, comptime Owner: type, owner: *Owner) HookError!void {
    try backend.mouse.install(Owner, owner);

    assert(backend.mouse.is_installed());
}

pub fn mouse_remove(backend: *Linux) void {
    backend.mouse.remove();

    assert(!backend.mouse.is_installed());
}

pub fn key_press(backend: *Linux, code: Keycode) bool {
    return simulate_key.press(&backend.runtime.session.keyboard_out, code);
}

pub fn key_down(backend: *Linux, code: Keycode) bool {
    return simulate_key.key_down(&backend.runtime.session.keyboard_out, code);
}

pub fn key_up(backend: *Linux, code: Keycode) bool {
    return simulate_key.key_up(&backend.runtime.session.keyboard_out, code);
}

pub fn key_suppress(backend: *Linux, code: Keycode) bool {
    return simulate_key.suppress(&backend.runtime.session.keyboard_out, code);
}

pub fn key_dummy(backend: *Linux) bool {
    return simulate_key.dummy(&backend.runtime.session.keyboard_out);
}

pub fn key_combination(backend: *Linux, modifiers: *const modifier.Set, code: Keycode) bool {
    assert(modifiers.flags <= modifier.flag_all);

    return simulate_key.combination(&backend.runtime.session.keyboard_out, modifiers, code);
}

pub fn mouse_click(backend: *Linux, button: Button) bool {
    return simulate_mouse.click(&backend.runtime.session.mouse_out, button);
}

pub fn mouse_button_down(backend: *Linux, button: Button) bool {
    return simulate_mouse.button_down(&backend.runtime.session.mouse_out, button);
}

pub fn mouse_button_up(backend: *Linux, button: Button) bool {
    return simulate_mouse.button_up(&backend.runtime.session.mouse_out, button);
}

pub fn mouse_move_to(backend: *Linux, position: Position) bool {
    const out = &backend.runtime.session.mouse_out;

    return simulate_mouse.move_to(out, &backend.monitor, position);
}

pub fn mouse_move_relative(backend: *Linux, offset: Position) bool {
    const out = &backend.runtime.session.mouse_out;

    return simulate_mouse.move_relative(out, &backend.monitor, offset);
}

pub fn mouse_get_position(backend: *Linux) Position {
    return simulate_mouse.get_position(&backend.monitor);
}

pub fn mouse_scroll_up(backend: *Linux, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    return simulate_mouse.scroll_up(&backend.runtime.session.mouse_out, clicks);
}

pub fn mouse_scroll_down(backend: *Linux, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    return simulate_mouse.scroll_down(&backend.runtime.session.mouse_out, clicks);
}

pub fn mouse_scroll_left(backend: *Linux, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    return simulate_mouse.scroll_left(&backend.runtime.session.mouse_out, clicks);
}

pub fn mouse_scroll_right(backend: *Linux, clicks: u32) bool {
    assert(clicks >= 1);
    assert(clicks <= scroll_clicks_max);

    return simulate_mouse.scroll_right(&backend.runtime.session.mouse_out, clicks);
}

pub fn text_send(backend: *Linux, text: []const u8) TextError!u32 {
    assert(text.len <= text_bytes_max);

    return simulate_text.send(&backend.runtime.session.keyboard_out, text);
}

pub fn text_send_with_delay(backend: *Linux, text: []const u8, delay_ms: u32) TextError!u32 {
    assert(text.len <= text_bytes_max);
    assert(delay_ms <= interface.sleep_ms_max);

    const out = &backend.runtime.session.keyboard_out;

    return simulate_text.send_with_delay(out, text, delay_ms);
}

pub fn timer_start(backend: *Linux, interval_ms: u32, tick: Tick, context: *anyopaque) ?TimerId {
    assert(interval_ms >= interface.timer_interval_ms_min);
    assert(interval_ms <= interface.timer_interval_ms_max);

    return backend.timer.start(interval_ms, tick, context);
}

pub fn timer_stop(backend: *Linux, id: TimerId) bool {
    assert(id != 0);

    return backend.timer.stop(id);
}

pub fn state_capture(backend: *const Linux) Snapshot {
    return backend.state.capture();
}

pub fn state_is_key_down_at(_: *const Linux, snapshot: *const Snapshot, code: Keycode) bool {
    return State.is_key_down_at(snapshot, code);
}

pub fn monitor_enumerate(backend: *Linux, list: *MonitorList) void {
    backend.monitor.enumerate(list);
}

pub fn clipboard_set(backend: *Linux, text: []const u8) ClipboardError!void {
    assert(text.len >= 1);
    assert(text.len <= clipboard_text_bytes_max);

    return backend.clipboard.set(text);
}

pub fn clipboard_paste(backend: *Linux) bool {
    return Clipboard.paste(&backend.runtime.session.keyboard_out);
}

pub fn clipboard_replace(backend: *Linux, select_count: u32, text: []const u8) ClipboardError!void {
    assert(select_count >= 1);
    assert(text.len >= 1);

    const out = &backend.runtime.session.keyboard_out;

    return backend.clipboard.replace(out, select_count, text);
}

const testing = std.testing;

test "a second runtime in one process is refused" {
    var first: Linux = undefined;
    var second: Linux = undefined;

    instance.store(&first, .seq_cst);
    defer instance.store(null, .seq_cst);

    try testing.expectError(error.RuntimeOpen, second.init(.{}));
    try testing.expect(instance.load(.seq_cst) == &first);
}

test "a wired backend holds its components closed" {
    var backend: Linux = undefined;

    backend.wire();

    try testing.expect(!backend.runtime.is_open());
    try testing.expectEqual(Mode.observe, backend.runtime_mode());
    try testing.expect(backend.loop.peers.runtime == &backend.runtime);
    try testing.expect(backend.runtime.peers.timer == &backend.timer);
}

test "every Linux declaration compiles" {
    testing.refAllDecls(Linux);
    testing.refAllDecls(Linux.RemoteClient);
}
