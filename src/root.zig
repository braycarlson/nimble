const std = @import("std");

const builder_keyboard = @import("builder.zig").keyboard;
const chord_registry = @import("registry.zig").chord;
const clipboard_module = @import("clipboard.zig");
const command_registry = @import("registry.zig").command;
const filter_module = @import("filter.zig");
const key_event = @import("event.zig").key;
const key_registry = @import("registry.zig").key;
const keyboard_module = @import("keyboard.zig");
const keycode_module = @import("keycode.zig");
const macro_registry = @import("registry.zig").macro;
const middleware_blocklist = @import("middleware.zig").blocklist;
const middleware_logging = @import("middleware.zig").logging;
const middleware_module = @import("middleware.zig");
const middleware_remap = @import("middleware.zig").remap;
const modifier_module = @import("modifier.zig");
const monitor_module = @import("monitor.zig");
const mouse_event = @import("event.zig").mouse;
const mouse_module = @import("mouse.zig");
const mouse_registry = @import("registry.zig").mouse;
const oneshot_registry = @import("registry.zig").oneshot;
const platform = @import("platform.zig");
const position_module = @import("position.zig");
const remote_module = @import("remote.zig");
const repeat_registry = @import("registry.zig").repeat;
const response_module = @import("response.zig");
const runtime_module = @import("runtime.zig");
const sequence_registry = @import("registry.zig").sequence;
const simulate_text = @import("simulate.zig").text;
const sync = @import("sync.zig");
const time_module = @import("time.zig");
const timer_registry = @import("registry.zig").timer;
const toggle_registry = @import("registry.zig").toggle;
const window_filter = @import("filter.zig").window;

const capabilities = platform.Native.capabilities;

const clipboard_errors = if (capabilities.clipboard) clipboard_module else NoErrors;
const remote_errors = if (capabilities.remote) remote_module else NoErrors;

const NoErrors = struct {
    pub const CapacityError = error{};
    pub const PlatformError = error{};
    pub const RequestError = error{};
};

pub const CapacityError = clipboard_errors.CapacityError ||
    keyboard_module.CapacityError ||
    middleware_module.CapacityError ||
    middleware_blocklist.CapacityError ||
    middleware_remap.CapacityError ||
    mouse_module.CapacityError ||
    remote_errors.CapacityError ||
    simulate_text.CapacityError;

pub const Error = CapacityError || PlatformError || RequestError;
pub const Fake = platform.Fake;
pub const Key = key_event.Key;
pub const KeyboardCapacity = keyboard_module.KeyboardCapacity;
pub const KeyboardOptions = keyboard_module.KeyboardOptions;
pub const KeyboardType = Runtime.KeyboardType;
pub const Keycode = keycode_module.Keycode;
pub const Modifier = modifier_module.Set;

pub const Monitor = if (capabilities.monitor_query)
    monitor_module.Monitor
else
    unavailable("Monitor", "monitor_query");

pub const MouseCapacity = mouse_module.MouseCapacity;
pub const MouseEvent = mouse_event.MouseEvent;
pub const MouseOptions = mouse_module.MouseOptions;
pub const MouseType = Runtime.MouseType;
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
    middleware_module.RequestError ||
    middleware_blocklist.RequestError ||
    middleware_remap.RequestError ||
    mouse_module.RequestError ||
    remote_errors.RequestError ||
    runtime_module.RequestError ||
    simulate_text.RequestError;

pub const Response = response_module.Response;
pub const Runtime = RuntimeType(platform.Native);
pub const RuntimeType = runtime_module.RuntimeType;

pub const WindowFilter = if (capabilities.window_filter)
    filter_module.WindowFilter
else
    unavailable("WindowFilter", "window_filter");

pub const clipboard = if (capabilities.clipboard) struct {
    pub const CapacityError = clipboard_module.CapacityError;
    pub const PlatformError = clipboard_module.PlatformError;
    pub const RequestError = clipboard_module.RequestError;
} else unavailable("clipboard", "clipboard");

pub const middleware = struct {
    pub const BlockListType = middleware_blocklist.BlockListType;
    pub const Logging = middleware_logging.Logging;
    pub const Next = middleware_module.Next;
    pub const RemapType = middleware_remap.RemapType;
};

pub const remote = if (capabilities.remote) struct {
    pub const CapacityError = remote_module.CapacityError;
    pub const Client = Runtime.Client;
    pub const PlatformError = remote_module.PlatformError;
    pub const RequestError = remote_module.RequestError;
} else unavailable("remote", "remote");

pub const runtime = struct {
    pub const PlatformError = runtime_module.PlatformError;
    pub const RequestError = runtime_module.RequestError;
};

pub const simulate = struct {
    pub const text = struct {
        pub const CapacityError = simulate_text.CapacityError;
        pub const PlatformError = simulate_text.PlatformError;
        pub const RequestError = simulate_text.RequestError;
    };
};

pub const limits = struct {
    pub const binding_count_max = key_registry.capacity_max;
    pub const chord_count_max = chord_registry.capacity_max;
    pub const chord_keys_max = chord_registry.sequence_max;
    pub const chord_timeout_ms_default = chord_registry.timeout_default_ms;
    pub const chord_timeout_ms_max = chord_registry.timeout_ms_max;
    pub const chord_timeout_ms_min = chord_registry.timeout_ms_min;
    pub const clipboard_text_bytes_max = if (capabilities.clipboard)
        platform.Native.clipboard_text_bytes_max
    else
        0;

    pub const command_count_max = command_registry.capacity_max;
    pub const command_name_bytes_max = command_registry.name_max;
    pub const macro_action_count_max = macro_registry.action_max;
    pub const macro_count_max = macro_registry.capacity_max;
    pub const macro_name_bytes_max = macro_registry.name_max;
    pub const macro_step_count_max = builder_keyboard.macro_step_count_max;
    pub const macro_text_bytes_max = macro_registry.text_buffer_max;
    pub const macro_text_step_bytes_max = macro_registry.text_step_bytes_max;
    pub const monitor_count_max = monitor_module.count_max;
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
    pub const scroll_clicks_max = Runtime.scroll_clicks_max;
    pub const sequence_bytes_max = sequence_registry.length_max;
    pub const sequence_count_max = sequence_registry.capacity_max;
    pub const sleep_ms_max = time_module.sleep_ms_max;
    pub const text_bytes_max = Runtime.text_bytes_max;
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
    const FakeRuntime = RuntimeType(Fake);

    const fake = try testing.allocator.create(FakeRuntime);
    defer testing.allocator.destroy(fake);

    try fake.init(.{});
    defer fake.deinit();

    const Keyboard = FakeRuntime.KeyboardType(.{ .binding_count_max = 1 });
    const keyboard = try testing.allocator.create(Keyboard);
    defer testing.allocator.destroy(keyboard);

    try keyboard.init(fake, .{});
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

test "the root surface resolves on the native backend" {
    const gated = capabilities.clipboard and capabilities.monitor_query and
        capabilities.remote and capabilities.window_filter;

    if (comptime gated) {
        testing.refAllDecls(@This());
        testing.refAllDecls(clipboard);
        testing.refAllDecls(remote);
    }

    testing.refAllDecls(limits);
    testing.refAllDecls(middleware);
    testing.refAllDecls(runtime);
    testing.refAllDecls(simulate.text);
    testing.refAllDecls(RuntimeType(Fake));
}
