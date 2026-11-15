const std = @import("std");

const key_event = @import("../event.zig").key;
const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const monitor_module = @import("../monitor.zig");
const mouse_event = @import("../event.zig").mouse;
const position_module = @import("../position.zig");
const response_module = @import("../response.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Keycode = keycode.Keycode;
const Modifiers = modifier.Set;
const Monitor = monitor_module.Monitor;
const MouseEvent = mouse_event.MouseEvent;
const Position = position_module.Position;
const Response = response_module.Response;

pub const Capabilities = struct {
    clipboard: bool,
    injected_flag_exact: bool,
    monitor_query: bool,
    remote: bool,
    window_filter: bool,
    window_targeted_input: bool,
};

pub const HookError = error{
    HookDuplicate,
    HookInstallFailed,
};

pub const Mode = enum(u8) {
    observe,
    grab,

    pub fn is_valid(mode: Mode) bool {
        return @backingInt(mode) <= @backingInt(Mode.grab);
    }
};

pub const Options = struct {
    mode: Mode = .observe,
    synthesis: bool = true,
    rescue: bool = true,
    wayland_display: ?[]const u8 = null,
    xdg_runtime_dir: ?[]const u8 = null,

    pub fn is_valid(options: *const Options) bool {
        return options.mode.is_valid();
    }
};

pub const ReleaseCallback = struct {
    context: *anyopaque,
    invoke: *const fn (context: *anyopaque) void,
};

pub const Tick = *const fn (context: *anyopaque) void;
pub const TimerId = usize;

pub const sleep_ms_max: u32 = 1000 * 60 * 60;
pub const timer_interval_ms_max: u32 = 1000 * 60 * 60;
pub const timer_interval_ms_min: u32 = 1;

const capability_count: u8 = @typeInfo(Capabilities).@"struct".field_names.len;

comptime {
    assert(capability_count == 6);
    assert(@typeInfo(Mode).@"enum".field_names.len == 2);
    assert(sleep_ms_max > 0);
    assert(timer_interval_ms_min >= 1);
    assert(timer_interval_ms_max > timer_interval_ms_min);
}

pub fn assert_backend(comptime Backend: type) void {
    comptime {
        require_decl(Backend, "capabilities");

        const capabilities: Capabilities = Backend.capabilities;

        assert_lifecycle(Backend);
        assert_runtime(Backend);
        assert_loop(Backend);
        assert_hooks(Backend);
        assert_key(Backend);
        assert_mouse(Backend);
        assert_text(Backend);
        assert_timer(Backend);
        assert_state(Backend);
        assert_window(Backend, capabilities);
        assert_monitor(Backend, capabilities);
        assert_clipboard(Backend, capabilities);
        assert_message(Backend, capabilities);
        assert_remote(Backend, capabilities);
    }
}

fn assert_lifecycle(comptime Backend: type) void {
    require_decl(Backend, "Error");

    require_method(Backend, "init", fn (*Backend, Options) Backend.Error!void);
    require_method(Backend, "deinit", fn (*Backend) void);
    require_method(Backend, "now_ms", fn (*const Backend) i64);
    require_method(Backend, "sleep_ms", fn (*Backend, u32) void);
}

fn assert_runtime(comptime Backend: type) void {
    require_method(Backend, "runtime_mode", fn (*const Backend) Mode);
    require_method(Backend, "runtime_release_grab", fn (*Backend) void);
    require_method(Backend, "runtime_acquire_grab", fn (*Backend) void);
    require_method(Backend, "runtime_set_release_callback", fn (*Backend, ?ReleaseCallback) void);
}

fn assert_loop(comptime Backend: type) void {
    require_method(Backend, "loop_run", fn (*Backend) void);
    require_method(Backend, "loop_poll", fn (*Backend, u32) bool);
    require_method(Backend, "loop_stop", fn (*Backend) void);
}

fn assert_hooks(comptime Backend: type) void {
    require_decl(Backend, "keyboard_install");
    require_decl(Backend, "mouse_install");

    require_method(Backend, "keyboard_remove", fn (*Backend) void);
    require_method(Backend, "mouse_remove", fn (*Backend) void);

    const Check = struct {
        const KeyOwner = struct {
            pub fn process(_: *KeyOwner, _: *const Key) Response {
                return .pass;
            }
        };

        const MouseOwner = struct {
            pub fn process(_: *MouseOwner, _: *const MouseEvent) Response {
                return .pass;
            }
        };

        fn run(backend: *Backend, key_owner: *KeyOwner, mouse_owner: *MouseOwner) HookError!void {
            try backend.keyboard_install(KeyOwner, key_owner);
            try backend.mouse_install(MouseOwner, mouse_owner);
        }
    };

    _ = &Check.run;
}

fn assert_key(comptime Backend: type) void {
    require_method(Backend, "key_press", fn (*Backend, Keycode) bool);
    require_method(Backend, "key_down", fn (*Backend, Keycode) bool);
    require_method(Backend, "key_up", fn (*Backend, Keycode) bool);
    require_method(Backend, "key_suppress", fn (*Backend, Keycode) bool);
    require_method(Backend, "key_dummy", fn (*Backend) bool);
    require_method(Backend, "key_combination", fn (*Backend, *const Modifiers, Keycode) bool);
}

fn assert_mouse(comptime Backend: type) void {
    const Button = MouseEvent.Button;

    require_decl(Backend, "scroll_clicks_max");

    require_method(Backend, "mouse_click", fn (*Backend, Button) bool);
    require_method(Backend, "mouse_button_down", fn (*Backend, Button) bool);
    require_method(Backend, "mouse_button_up", fn (*Backend, Button) bool);
    require_method(Backend, "mouse_move_to", fn (*Backend, Position) bool);
    require_method(Backend, "mouse_move_relative", fn (*Backend, Position) bool);
    require_method(Backend, "mouse_get_position", fn (*Backend) Position);
    require_method(Backend, "mouse_scroll_up", fn (*Backend, u32) bool);
    require_method(Backend, "mouse_scroll_down", fn (*Backend, u32) bool);
    require_method(Backend, "mouse_scroll_left", fn (*Backend, u32) bool);
    require_method(Backend, "mouse_scroll_right", fn (*Backend, u32) bool);
}

fn assert_text(comptime Backend: type) void {
    require_decl(Backend, "TextError");
    require_decl(Backend, "text_bytes_max");

    const Sent = Backend.TextError!u32;

    require_method(Backend, "text_send", fn (*Backend, []const u8) Sent);
    require_method(Backend, "text_send_with_delay", fn (*Backend, []const u8, u32) Sent);
}

fn assert_timer(comptime Backend: type) void {
    require_method(Backend, "timer_start", fn (*Backend, u32, Tick, *anyopaque) ?TimerId);
    require_method(Backend, "timer_stop", fn (*Backend, TimerId) bool);
}

fn assert_state(comptime Backend: type) void {
    require_decl(Backend, "Snapshot");

    const Snapshot = Backend.Snapshot;

    require_method(Backend, "state_capture", fn (*const Backend) Snapshot);

    require_method(
        Backend,
        "state_is_key_down_at",
        fn (*const Backend, *const Snapshot, Keycode) bool,
    );
}

fn assert_window(comptime Backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.window_filter) {
        return;
    }

    require_decl(Backend, "WindowHandle");

    const Handle = Backend.WindowHandle;

    require_method(Backend, "window_foreground", fn (*const Backend) ?Handle);
    require_method(Backend, "window_is_fullscreen", fn (*const Backend, Handle) bool);
    require_method(Backend, "window_is_maximized", fn (*const Backend, Handle) bool);
    require_method(Backend, "window_class_matches", fn (*const Backend, Handle, []const u8) bool);
    require_method(Backend, "window_title_matches", fn (*const Backend, Handle, []const u8) bool);
}

fn assert_monitor(comptime Backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.monitor_query) {
        return;
    }

    require_method(Backend, "monitor_enumerate", fn (*Backend, *Monitor.List) void);
}

fn assert_clipboard(comptime Backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.clipboard) {
        return;
    }

    require_decl(Backend, "ClipboardError");
    require_decl(Backend, "clipboard_text_bytes_max");

    const Set = Backend.ClipboardError!void;

    require_method(Backend, "clipboard_set", fn (*Backend, []const u8) Set);
    require_method(Backend, "clipboard_paste", fn (*Backend) bool);
    require_method(Backend, "clipboard_replace", fn (*Backend, u32, []const u8) Set);
}

fn assert_message(comptime Backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.window_targeted_input) {
        return;
    }

    require_decl(Backend, "WindowHandle");

    const Handle = Backend.WindowHandle;

    require_method(Backend, "window_get_focused", fn (*const Backend) ?Handle);
    require_method(Backend, "message_send_key", fn (*Backend, Handle, Keycode, bool) bool);
    require_method(Backend, "message_send_key_press", fn (*Backend, Handle, Keycode) bool);
    require_method(Backend, "message_send_char", fn (*Backend, Handle, u16) bool);
    require_method(Backend, "message_release_modifiers", fn (*Backend, Handle) bool);
}

fn assert_remote(comptime Backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.remote) {
        return;
    }

    require_decl(Backend, "RemoteClient");

    if (@TypeOf(Backend.RemoteClient) != type) {
        @compileError("nimble backend " ++ @typeName(Backend) ++ ".RemoteClient must be a type");
    }
}

fn require_decl(comptime Backend: type, comptime name: []const u8) void {
    assert(name.len > 0);

    if (!@hasDecl(Backend, name)) {
        @compileError("nimble backend " ++ @typeName(Backend) ++ " is missing '" ++ name ++ "'");
    }
}

fn require_method(
    comptime Backend: type,
    comptime name: []const u8,
    comptime Signature: type,
) void {
    assert(name.len > 0);

    require_decl(Backend, name);

    const Actual = @TypeOf(@field(Backend, name));

    if (Actual != Signature) {
        @compileError(
            "nimble backend " ++ @typeName(Backend) ++ "." ++ name ++ " has type " ++
                @typeName(Actual) ++ ", expected " ++ @typeName(Signature),
        );
    }
}

const testing = std.testing;

test "the capability set has the fields the interface names" {
    try testing.expectEqual(@as(u8, 6), capability_count);
}

test "a capability set can deny everything" {
    const capabilities = Capabilities{
        .clipboard = false,
        .injected_flag_exact = false,
        .monitor_query = false,
        .remote = false,
        .window_filter = false,
        .window_targeted_input = false,
    };

    try testing.expect(!capabilities.clipboard);
    try testing.expect(!capabilities.injected_flag_exact);
    try testing.expect(!capabilities.monitor_query);
    try testing.expect(!capabilities.remote);
    try testing.expect(!capabilities.window_filter);
    try testing.expect(!capabilities.window_targeted_input);
}

test "a capability set can allow everything" {
    const capabilities = Capabilities{
        .clipboard = true,
        .injected_flag_exact = true,
        .monitor_query = true,
        .remote = true,
        .window_filter = true,
        .window_targeted_input = true,
    };

    try testing.expect(capabilities.clipboard);
    try testing.expect(capabilities.injected_flag_exact);
    try testing.expect(capabilities.monitor_query);
    try testing.expect(capabilities.remote);
    try testing.expect(capabilities.window_filter);
    try testing.expect(capabilities.window_targeted_input);
}

test "the modes cover observing and grabbing" {
    try testing.expect(Mode.observe.is_valid());
    try testing.expect(Mode.grab.is_valid());
    try testing.expectEqual(@as(u8, 0), @backingInt(Mode.observe));
    try testing.expectEqual(@as(u8, 1), @backingInt(Mode.grab));
}

test "options default to the safe mode" {
    const options = Options{};

    try testing.expect(options.is_valid());
    try testing.expectEqual(Mode.observe, options.mode);
    try testing.expect(options.synthesis);
    try testing.expect(options.rescue);
    try testing.expect(options.wayland_display == null);
    try testing.expect(options.xdg_runtime_dir == null);
}

test "options carry an explicit grab request" {
    const options = Options{ .mode = .grab, .synthesis = false, .rescue = false };

    try testing.expect(options.is_valid());
    try testing.expectEqual(Mode.grab, options.mode);
    try testing.expect(!options.synthesis);
    try testing.expect(!options.rescue);
}
