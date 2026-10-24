const std = @import("std");

const builder_keyboard = @import("builder/keyboard.zig");
const chord_registry = @import("registry/chord.zig");
const clipboard_module = @import("clipboard.zig");
const command_registry = @import("registry/command.zig");
const filter_module = @import("filter.zig");
const key_event = @import("event/key.zig");
const key_registry = @import("registry/key.zig");
const keyboard_module = @import("keyboard.zig");
const keycode_module = @import("keycode.zig");
const loop_module = @import("loop.zig");
const macro_registry = @import("registry/macro.zig");
const middleware_base = @import("middleware/base.zig");
const middleware_blocklist = @import("middleware/blocklist.zig");
const middleware_logging = @import("middleware/logging.zig");
const middleware_remap = @import("middleware/remap.zig");
const modifier_module = @import("modifier.zig");
const monitor_module = @import("monitor.zig");
const mouse_event = @import("event/mouse.zig");
const mouse_module = @import("mouse.zig");
const mouse_registry = @import("registry/mouse.zig");
const oneshot_registry = @import("registry/oneshot.zig");
const platform = @import("platform.zig");
const position_module = @import("position.zig");
const remote_module = @import("remote.zig");
const repeat_registry = @import("registry/repeat.zig");
const response_module = @import("response.zig");
const runtime_module = @import("runtime.zig");
const sequence_registry = @import("registry/sequence.zig");
const simulate_key = @import("simulate/key.zig");
const simulate_mouse = @import("simulate/mouse.zig");
const simulate_text = @import("simulate/text.zig");
const sync = @import("sync.zig");
const time_module = @import("time.zig");
const timer_registry = @import("registry/timer.zig");
const toggle_registry = @import("registry/toggle.zig");
const window_filter = @import("filter/window.zig");

const capabilities = platform.capabilities;

const clipboard_errors = if (capabilities.clipboard) clipboard_module else NoErrors;
const remote_errors = if (capabilities.remote) remote_module else NoErrors;

const NoErrors = struct {
    pub const CapacityError = error{};
    pub const PlatformError = error{};
    pub const RequestError = error{};
};

pub const CapacityError = clipboard_errors.CapacityError ||
    keyboard_module.CapacityError ||
    middleware_base.CapacityError ||
    middleware_blocklist.CapacityError ||
    middleware_remap.CapacityError ||
    mouse_module.CapacityError ||
    remote_errors.CapacityError ||
    simulate_text.CapacityError;

pub const Error = CapacityError || PlatformError || RequestError;
pub const Key = key_event.Key;
pub const KeyboardCapacity = keyboard_module.KeyboardCapacity;
pub const KeyboardOptions = keyboard_module.KeyboardOptions;
pub const KeyboardType = keyboard_module.KeyboardType;
pub const Keycode = keycode_module.Keycode;
pub const Modifier = modifier_module.Set;

pub const Monitor = if (capabilities.monitor_query)
    monitor_module.Monitor
else
    unavailable("Monitor", "monitor_query");

pub const MouseCapacity = mouse_module.MouseCapacity;
pub const MouseEvent = mouse_event.MouseEvent;
pub const MouseOptions = mouse_module.MouseOptions;
pub const MouseType = mouse_module.MouseType;
pub const Mutex = sync.Mutex;

pub const PlatformError = clipboard_errors.PlatformError ||
    keyboard_module.PlatformError ||
    mouse_module.PlatformError ||
    remote_errors.PlatformError ||
    runtime_module.PlatformError ||
    simulate_text.PlatformError;

pub const Position = position_module.Position;

pub const RequestError = clipboard_errors.RequestError ||
    keyboard_module.RequestError ||
    middleware_base.RequestError ||
    middleware_blocklist.RequestError ||
    middleware_remap.RequestError ||
    mouse_module.RequestError ||
    remote_errors.RequestError ||
    runtime_module.RequestError ||
    simulate_text.RequestError;

pub const Response = response_module.Response;

pub const WindowFilter = if (capabilities.window_filter)
    filter_module.Active
else
    unavailable("WindowFilter", "window_filter");

pub const clipboard = if (capabilities.clipboard) struct {
    pub const CapacityError = clipboard_module.CapacityError;
    pub const PlatformError = clipboard_module.PlatformError;
    pub const RequestError = clipboard_module.RequestError;

    pub const paste = clipboard_module.paste;
    pub const replace = clipboard_module.replace;
    pub const set = clipboard_module.set;
} else unavailable("clipboard", "clipboard");

pub const loop = struct {
    pub const poll = loop_module.poll;
    pub const run = loop_module.run;
    pub const stop = loop_module.stop;
};

pub const middleware = struct {
    pub const BlockListMiddlewareType = middleware_blocklist.BlockListMiddlewareType;
    pub const LoggingMiddleware = middleware_logging.LoggingMiddleware;
    pub const Next = middleware_base.Next;
    pub const RemapMiddlewareType = middleware_remap.RemapMiddlewareType;
};

pub const mock = struct {
    pub const monitor = platform.mock.monitor;
    pub const record = platform.mock.record;
    pub const reset = platform.mock.reset;
};

pub const remote = if (capabilities.remote) struct {
    pub const CapacityError = remote_module.CapacityError;
    pub const Client = remote_module.Client;
    pub const PlatformError = remote_module.PlatformError;
    pub const RequestError = remote_module.RequestError;
} else unavailable("remote", "remote");

pub const runtime = struct {
    pub const Mode = runtime_module.Mode;
    pub const Options = runtime_module.Options;
    pub const PlatformError = runtime_module.PlatformError;
    pub const RequestError = runtime_module.RequestError;

    pub const acquire_grab = runtime_module.acquire_grab;
    pub const close = runtime_module.close;
    pub const is_open = runtime_module.is_open;
    pub const mode = runtime_module.mode;
    pub const open = runtime_module.open;
    pub const release_grab = runtime_module.release_grab;
    pub const set_release_callback = runtime_module.set_release_callback;
};

pub const simulate = struct {
    pub const key = struct {
        pub const combination = simulate_key.combination;
        pub const down = simulate_key.down;
        pub const press = simulate_key.press;
        pub const up = simulate_key.up;
    };

    pub const mouse = struct {
        pub const button_down = simulate_mouse.button_down;
        pub const button_up = simulate_mouse.button_up;
        pub const click = simulate_mouse.click;
        pub const move_relative = simulate_mouse.move_relative;
        pub const move_to = simulate_mouse.move_to;
        pub const position = simulate_mouse.position;
        pub const scroll_down = simulate_mouse.scroll_down;
        pub const scroll_left = simulate_mouse.scroll_left;
        pub const scroll_right = simulate_mouse.scroll_right;
        pub const scroll_up = simulate_mouse.scroll_up;
    };

    pub const text = struct {
        pub const CapacityError = simulate_text.CapacityError;
        pub const PlatformError = simulate_text.PlatformError;
        pub const RequestError = simulate_text.RequestError;

        pub const send = simulate_text.send;
        pub const send_with_delay = simulate_text.send_with_delay;
    };
};

pub const time = struct {
    pub const now_ms = time_module.now_ms;
    pub const sleep_ms = time_module.sleep_ms;
};

pub const limits = struct {
    pub const binding_count_max = key_registry.capacity_max;
    pub const chord_count_max = chord_registry.capacity_max;
    pub const chord_keys_max = chord_registry.sequence_max;
    pub const chord_timeout_ms_default = chord_registry.timeout_default_ms;
    pub const chord_timeout_ms_max = chord_registry.timeout_ms_max;
    pub const chord_timeout_ms_min = chord_registry.timeout_ms_min;
    pub const clipboard_text_bytes_max = clipboard_module.text_bytes_max;
    pub const command_count_max = command_registry.capacity_max;
    pub const command_name_bytes_max = command_registry.name_max;
    pub const macro_action_count_max = macro_registry.action_max;
    pub const macro_count_max = macro_registry.capacity_max;
    pub const macro_name_bytes_max = macro_registry.name_max;
    pub const macro_step_count_max = builder_keyboard.macro_step_count_max;
    pub const macro_text_bytes_max = macro_registry.text_buffer_max;
    pub const macro_text_step_bytes_max = macro_registry.text_step_bytes_max;
    pub const monitor_count_max = monitor_module.monitor_count_max;
    pub const mouse_binding_count_max = mouse_registry.capacity_max;
    pub const oneshot_count_max = oneshot_registry.capacity_max;
    pub const remote_binding_count_max = remote_module.binding_count_max;
    pub const remote_chord_keys_max = remote_module.chord_keys_max;
    pub const remote_delay_ms_max = remote_module.delay_ms_max;
    pub const remote_filter_patterns_max = remote_module.filter_patterns_max;
    pub const remote_scroll_clicks_max = remote_module.scroll_clicks_max;
    pub const remote_sequence_bytes_max = remote_module.sequence_bytes_max;
    pub const remote_text_bytes_max = remote_module.text_bytes_max;
    pub const repeat_count_max = repeat_registry.capacity_max;
    pub const repeat_delay_ms_max = repeat_registry.delay_ms_initial_max;
    pub const repeat_interval_ms_max = repeat_registry.interval_ms_max;
    pub const repeat_interval_ms_min = repeat_registry.interval_ms_min;
    pub const scroll_clicks_max = simulate_mouse.scroll_clicks_max;
    pub const sequence_bytes_max = sequence_registry.length_max;
    pub const sequence_count_max = sequence_registry.capacity_max;
    pub const sleep_ms_max = time_module.sleep_ms_max;
    pub const text_bytes_max = simulate_text.text_bytes_max;
    pub const text_delay_ms_max = simulate_text.delay_ms_max;
    pub const timer_count_max = timer_registry.capacity_max;
    pub const timer_interval_ms_max = timer_registry.interval_ms_max;
    pub const timer_interval_ms_min = timer_registry.interval_ms_min;
    pub const toggle_count_max = toggle_registry.capacity_max;
    pub const window_filter_bytes_max = window_filter.length_max;
};

fn unavailable(comptime feature: []const u8, comptime capability: []const u8) noreturn {
    @compileError("nimble: " ++ feature ++ " requires the " ++ capability ++
        " capability, which this backend does not provide");
}

const testing = std.testing;

const Ignore = struct {
    fn on_key(_: *Ignore, _: *const Key) Response {
        return .pass;
    }
};

test Error {
    platform.mock.reset();

    const Keyboard = KeyboardType(.{ .binding_count_max = 1 });
    const keyboard = try testing.allocator.create(Keyboard);
    defer testing.allocator.destroy(keyboard);

    try keyboard.init(.{});
    defer keyboard.deinit();

    var ignore = Ignore{};

    _ = try keyboard.bind("A").on(Ignore, &ignore, Ignore.on_key);

    const sized: CapacityError = error.BindingsExhausted;
    const asked: RequestError = error.BindingDuplicate;
    const failure: Error = sized;

    try testing.expectError(sized, keyboard.bind("B").on(Ignore, &ignore, Ignore.on_key));
    try testing.expectError(asked, keyboard.bind("A").on(Ignore, &ignore, Ignore.on_key));
    try testing.expectError(failure, keyboard.bind("C").on(Ignore, &ignore, Ignore.on_key));
}

test limits {
    const Widest = KeyboardType(.{ .binding_count_max = limits.binding_count_max });

    try testing.expect(@sizeOf(Widest) > 0);
    try testing.expect(limits.remote_chord_keys_max <= limits.chord_keys_max);
    try testing.expect(limits.remote_sequence_bytes_max <= limits.sequence_bytes_max);
    try testing.expect(limits.remote_scroll_clicks_max <= limits.scroll_clicks_max);
    try testing.expect(limits.remote_text_bytes_max <= limits.text_bytes_max);
    try testing.expect(limits.chord_timeout_ms_min <= limits.chord_timeout_ms_default);
    try testing.expect(limits.chord_timeout_ms_default <= limits.chord_timeout_ms_max);
}

test "the root surface resolves on the mock backend" {
    testing.refAllDecls(@This());
    testing.refAllDecls(clipboard);
    testing.refAllDecls(limits);
    testing.refAllDecls(loop);
    testing.refAllDecls(middleware);
    testing.refAllDecls(remote);
    testing.refAllDecls(runtime);
    testing.refAllDecls(simulate.key);
    testing.refAllDecls(simulate.mouse);
    testing.refAllDecls(simulate.text);
    testing.refAllDecls(time);
}
