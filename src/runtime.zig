const std = @import("std");

const clipboard = @import("clipboard.zig");
const filter = @import("filter.zig");
const keyboard_module = @import("keyboard.zig");
const keycode = @import("keycode.zig");
const loop = @import("loop.zig");
const modifier = @import("modifier.zig");
const monitor_module = @import("monitor.zig");
const mouse_event = @import("event.zig").mouse;
const mouse_module = @import("mouse.zig");
const platform = @import("platform.zig");
const position_module = @import("position.zig");
const remote_module = @import("remote.zig");
const response_module = @import("response.zig");
const simulate_key = @import("simulate.zig").key;
const simulate_mouse = @import("simulate.zig").mouse;
const simulate_text = @import("simulate.zig").text;
const time = @import("time.zig");

const assert = std.debug.assert;

const Button = mouse_event.MouseEvent.Button;
const KeyboardCapacity = keyboard_module.KeyboardCapacity;
const Keycode = keycode.Keycode;
const Modifier = modifier.Set;
const Monitor = monitor_module.Monitor;
const MouseCapacity = mouse_module.MouseCapacity;
const Position = position_module.Position;
const Response = response_module.Response;

pub const Mode = platform.Mode;
pub const Options = platform.Options;

pub const PlatformError = error{
    DevicesMissing,
    EpollFailed,
    InputGroupMissing,
    SynthesisUnavailable,
    UinputInaccessible,
};

pub const RequestError = error{
    DisplayInvalid,
    RuntimeOpen,
};

const ClipboardError = clipboard.CapacityError || clipboard.PlatformError || clipboard.RequestError;

const TextError = simulate_text.CapacityError ||
    simulate_text.PlatformError ||
    simulate_text.RequestError;

pub fn RuntimeType(comptime Platform: type) type {
    comptime platform.assert_backend(Platform);

    return struct {
        platform: Platform,

        const Runtime = @This();

        pub const Client = remote_module.ClientType(Platform);
        pub const Mode = platform.Mode;
        pub const Options = platform.Options;

        pub const WindowFilter = if (Platform.capabilities.window_filter)
            filter.WindowFilter
        else
            @compileError("nimble: WindowFilter requires the window_filter capability");

        pub const scroll_clicks_max: u32 = Platform.scroll_clicks_max;
        pub const text_bytes_max: u32 = Platform.text_bytes_max;

        pub fn KeyboardType(comptime capacity: KeyboardCapacity) type {
            return keyboard_module.KeyboardType(Platform, capacity);
        }

        pub fn MouseType(comptime capacity: MouseCapacity) type {
            return mouse_module.MouseType(Platform, capacity);
        }

        pub fn init(
            runtime: *Runtime,
            options: platform.Options,
        ) (PlatformError || RequestError)!void {
            assert(options.is_valid());

            try runtime.platform.init(options);

            assert(runtime.mode() == options.mode);
        }

        pub fn deinit(runtime: *Runtime) void {
            assert(runtime.mode().is_valid());

            runtime.platform.deinit();
            runtime.* = undefined;
        }

        pub fn mode(runtime: *const Runtime) platform.Mode {
            const result = runtime.platform.runtime_mode();

            assert(result.is_valid());

            return result;
        }

        pub fn release_grab(runtime: *Runtime) void {
            runtime.platform.runtime_release_grab();

            assert(runtime.mode() == .observe);
        }

        pub fn acquire_grab(runtime: *Runtime) void {
            runtime.platform.runtime_acquire_grab();

            assert(runtime.mode().is_valid());
        }

        pub fn set_release_callback(
            runtime: *Runtime,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner) void,
        ) void {
            const Trampoline = struct {
                fn invoke(context: *anyopaque) void {
                    const typed: *Owner = @ptrCast(@alignCast(context));

                    callback(typed);
                }
            };

            runtime.platform.runtime_set_release_callback(.{
                .context = owner,
                .invoke = Trampoline.invoke,
            });
        }

        pub fn clear_release_callback(runtime: *Runtime) void {
            runtime.platform.runtime_set_release_callback(null);
        }

        pub fn run(runtime: *Runtime) void {
            loop.run(Platform, &runtime.platform);
        }

        pub fn poll(runtime: *Runtime, timeout_ms: u32) bool {
            return loop.poll(Platform, &runtime.platform, timeout_ms);
        }

        pub fn stop(runtime: *Runtime) void {
            loop.stop(Platform, &runtime.platform);
        }

        pub fn now_ms(runtime: *const Runtime) i64 {
            return time.now_ms(Platform, &runtime.platform);
        }

        pub fn sleep_ms(runtime: *Runtime, duration_ms: u32) void {
            assert(duration_ms <= time.sleep_ms_max);

            time.sleep_ms(Platform, &runtime.platform, duration_ms);
        }

        pub fn key_combination(runtime: *Runtime, modifiers: Modifier, value: Keycode) bool {
            assert(modifiers.flags <= modifier.flag_all);

            return simulate_key.combination(Platform, &runtime.platform, modifiers, value);
        }

        pub fn key_down(runtime: *Runtime, value: Keycode) bool {
            return simulate_key.down(Platform, &runtime.platform, value);
        }

        pub fn key_press(runtime: *Runtime, value: Keycode) bool {
            return simulate_key.press(Platform, &runtime.platform, value);
        }

        pub fn key_up(runtime: *Runtime, value: Keycode) bool {
            return simulate_key.up(Platform, &runtime.platform, value);
        }

        pub fn mouse_button_down(runtime: *Runtime, button: Button) bool {
            return simulate_mouse.button_down(Platform, &runtime.platform, button);
        }

        pub fn mouse_button_up(runtime: *Runtime, button: Button) bool {
            return simulate_mouse.button_up(Platform, &runtime.platform, button);
        }

        pub fn mouse_click(runtime: *Runtime, button: Button) bool {
            return simulate_mouse.click(Platform, &runtime.platform, button);
        }

        pub fn mouse_move_relative(runtime: *Runtime, offset: Position) bool {
            return simulate_mouse.move_relative(Platform, &runtime.platform, offset);
        }

        pub fn mouse_move_to(runtime: *Runtime, target: Position) bool {
            return simulate_mouse.move_to(Platform, &runtime.platform, target);
        }

        pub fn mouse_position(runtime: *Runtime) Position {
            return simulate_mouse.position(Platform, &runtime.platform);
        }

        pub fn mouse_scroll_down(runtime: *Runtime, clicks: u32) bool {
            assert(clicks >= 1);
            assert(clicks <= Platform.scroll_clicks_max);

            return simulate_mouse.scroll_down(Platform, &runtime.platform, clicks);
        }

        pub fn mouse_scroll_left(runtime: *Runtime, clicks: u32) bool {
            assert(clicks >= 1);
            assert(clicks <= Platform.scroll_clicks_max);

            return simulate_mouse.scroll_left(Platform, &runtime.platform, clicks);
        }

        pub fn mouse_scroll_right(runtime: *Runtime, clicks: u32) bool {
            assert(clicks >= 1);
            assert(clicks <= Platform.scroll_clicks_max);

            return simulate_mouse.scroll_right(Platform, &runtime.platform, clicks);
        }

        pub fn mouse_scroll_up(runtime: *Runtime, clicks: u32) bool {
            assert(clicks >= 1);
            assert(clicks <= Platform.scroll_clicks_max);

            return simulate_mouse.scroll_up(Platform, &runtime.platform, clicks);
        }

        pub fn text_send(runtime: *Runtime, text: []const u8) TextError!u32 {
            return simulate_text.send(Platform, &runtime.platform, text);
        }

        pub fn text_send_with_delay(
            runtime: *Runtime,
            text: []const u8,
            delay_ms: u32,
        ) TextError!u32 {
            return simulate_text.send_with_delay(Platform, &runtime.platform, text, delay_ms);
        }

        pub fn clipboard_paste(runtime: *Runtime) bool {
            return clipboard.paste(Platform, &runtime.platform);
        }

        pub fn clipboard_replace(
            runtime: *Runtime,
            select_count: u32,
            text: []const u8,
        ) ClipboardError!void {
            assert(select_count >= 1);
            assert(text.len >= 1);

            return clipboard.replace(Platform, &runtime.platform, select_count, text);
        }

        pub fn clipboard_set(runtime: *Runtime, text: []const u8) ClipboardError!void {
            assert(text.len >= 1);

            return clipboard.set(Platform, &runtime.platform, text);
        }

        pub fn monitor_enumerate(runtime: *Runtime, list: *Monitor.List) void {
            monitor_module.enumerate(Platform, &runtime.platform, list);
        }
    };
}

pub fn clamp(mode: Mode, response: Response) Response {
    assert(mode.is_valid());
    assert(response.is_valid());

    if (mode == .observe) {
        return .pass;
    }

    return response;
}

const testing = std.testing;

const FakeRuntime = RuntimeType(platform.Fake);

fn runtime_create(options: Options) !*FakeRuntime {
    const runtime = try testing.allocator.create(FakeRuntime);
    errdefer testing.allocator.destroy(runtime);

    try runtime.init(options);

    return runtime;
}

fn runtime_destroy(runtime: *FakeRuntime) void {
    runtime.deinit();

    testing.allocator.destroy(runtime);
}

test Mode {
    const runtime = try runtime_create(.{ .mode = .observe });
    defer runtime_destroy(runtime);

    try testing.expectEqual(Mode.observe, runtime.mode());
    try testing.expectEqual(Response.pass, clamp(runtime.mode(), .consume));
}

test Options {
    const defaults = Options{};

    try testing.expectEqual(Mode.observe, defaults.mode);
    try testing.expect(defaults.synthesis);
    try testing.expect(defaults.rescue);
    try testing.expect(defaults.wayland_display == null);
    try testing.expect(defaults.is_valid());
}

test RuntimeType {
    const runtime = try runtime_create(.{ .mode = .grab });
    defer runtime_destroy(runtime);

    try testing.expectEqual(Mode.grab, runtime.mode());
    try testing.expectEqual(Mode.grab, runtime.platform.runtime.mode());
    try testing.expect(!runtime.platform.keyboard.is_installed());
}

test "a runtime that is released reports observe mode" {
    const runtime = try runtime_create(.{});
    defer runtime_destroy(runtime);

    runtime.release_grab();

    try testing.expectEqual(Mode.observe, runtime.mode());
}

test "a grab mode runtime switches modes as it is released" {
    const runtime = try runtime_create(.{ .mode = .grab });
    defer runtime_destroy(runtime);

    try testing.expectEqual(Mode.grab, runtime.mode());

    runtime.release_grab();

    try testing.expectEqual(Mode.observe, runtime.mode());
}

test "release_grab" {
    const runtime = try runtime_create(.{ .mode = .grab });
    defer runtime_destroy(runtime);

    runtime.release_grab();

    try testing.expectEqual(Mode.observe, runtime.mode());
    try testing.expectEqual(Response.pass, clamp(runtime.mode(), .consume));
}

test "acquire_grab" {
    const runtime = try runtime_create(.{ .mode = .grab });
    defer runtime_destroy(runtime);

    runtime.release_grab();
    runtime.acquire_grab();

    try testing.expectEqual(Mode.grab, runtime.mode());
    try testing.expectEqual(Response.consume, clamp(runtime.mode(), .consume));
}

test "set_release_callback" {
    const Counter = struct {
        count: u32 = 0,

        fn on_released(counter: *@This()) void {
            counter.count += 1;
        }
    };

    var counter = Counter{};

    const runtime = try runtime_create(.{ .mode = .grab });
    defer runtime_destroy(runtime);

    runtime.set_release_callback(Counter, &counter, Counter.on_released);
    defer runtime.clear_release_callback();

    runtime.release_grab();

    try testing.expectEqual(@as(u32, 1), counter.count);
}

test "observe mode cannot eat input" {
    const runtime = try runtime_create(.{});
    defer runtime_destroy(runtime);

    try testing.expectEqual(Mode.observe, runtime.mode());
    try testing.expectEqual(Response.pass, clamp(runtime.mode(), .pass));
    try testing.expectEqual(Response.pass, clamp(runtime.mode(), .consume));
}

test "the public runtime speaks the backend vocabulary" {
    try testing.expectEqual(platform.Mode, Mode);
    try testing.expectEqual(platform.Options, Options);
    try testing.expectEqual(FakeRuntime.Mode, Mode);
    try testing.expectEqual(FakeRuntime.Options, Options);
}
