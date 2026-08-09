const std = @import("std");

const key_event = @import("../event/key.zig");
const keycode = @import("../keycode.zig");
const modifier = @import("../modifier.zig");
const mouse_event = @import("../event/mouse.zig");
const response_mod = @import("../response.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Keycode = keycode.Keycode;
const Modifiers = modifier.Set;
const Mouse = mouse_event.Mouse;
const Response = response_mod.Response;

pub const Capabilities = struct {
    clipboard: bool,
    injected_flag_exact: bool,
    monitor_query: bool,
    remote: bool,
    window_filter: bool,
    window_targeted_input: bool,
};

pub const capability_count: u8 = @typeInfo(Capabilities).@"struct".fields.len;

pub const Mode = enum(u8) {
    observe,
    grab,

    pub fn is_valid(mode: Mode) bool {
        return @intFromEnum(mode) <= @intFromEnum(Mode.grab);
    }
};

pub const Options = struct {
    mode: Mode = .observe,
    synthesis: bool = true,
    rescue: bool = true,

    pub fn is_valid(options: *const Options) bool {
        return options.mode.is_valid();
    }
};

comptime {
    assert(capability_count == 6);
    assert(@typeInfo(Mode).@"enum".fields.len == 2);
}

pub fn assert_backend(comptime backend: type) void {
    comptime {
        require_decl(backend, "capabilities", "backend");

        const capabilities: Capabilities = backend.capabilities;

        assert_time(backend);
        assert_keycode(backend);
        assert_state(backend);
        assert_runtime(backend);
        assert_hook(backend);
        assert_simulate(backend);
        assert_timer(backend);
        assert_loop(backend);
        assert_window(backend, capabilities);
        assert_monitor(backend, capabilities);
        assert_clipboard(backend, capabilities);
        assert_message(backend, capabilities);
        assert_remote(backend, capabilities);
    }
}

fn assert_time(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "time", "backend");

    require_fn(scope, "now_ms", fn () i64, "time");
    require_fn(scope, "sleep_ms", fn (u32) void, "time");
}

fn assert_keycode(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "keycode", "backend");

    require_fn(scope, "from_native", fn (u8) ?Keycode, "keycode");
    require_fn(scope, "to_native", fn (Keycode) ?u8, "keycode");
}

fn assert_state(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "state", "backend");

    require_decl(scope, "Snapshot", "state");

    require_fn(scope, "is_key_down", fn (Keycode) bool, "state");
    require_fn(scope, "capture", fn () scope.Snapshot, "state");
    require_fn(scope, "is_key_down_at", fn (*const scope.Snapshot, Keycode) bool, "state");
}

fn assert_runtime(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "runtime", "backend");

    require_type(scope, "Mode", Mode, "runtime");
    require_type(scope, "Options", Options, "runtime");
    require_decl(scope, "Error", "runtime");

    require_fn(scope, "open", fn (Options) scope.Error!void, "runtime");
    require_fn(scope, "close", fn () void, "runtime");
    require_fn(scope, "is_open", fn () bool, "runtime");
    require_fn(scope, "mode", fn () Mode, "runtime");
    require_fn(scope, "release_grab", fn () void, "runtime");
    require_fn(scope, "acquire_grab", fn () void, "runtime");
    require_fn(scope, "set_release_callback", fn (?*const fn () void) void, "runtime");
}

fn assert_hook(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "hook", "backend");

    require_decl(scope, "Kind", "hook");
    require_decl(scope, "Hook", "hook");

    assert_source(RequiredNamespaceType(backend, "keyboard", "backend"), Key, "keyboard");
    assert_source(RequiredNamespaceType(backend, "mouse", "backend"), Mouse, "mouse");
}

fn assert_source(comptime scope: type, comptime Event: type, comptime label: []const u8) void {
    require_decl(scope, "Error", label);
    require_decl(scope, "SourceType", label);

    const Owner = struct {
        pub fn process(_: *@This(), _: *const Event) Response {
            return .pass;
        }
    };

    const Instance = scope.SourceType(Owner);

    const source_label = label ++ ".SourceType";

    require_fn(Instance, "init", fn () Instance, source_label);
    require_fn(Instance, "install", fn (*Instance, *Owner) scope.Error!void, source_label);
    require_fn(Instance, "remove", fn (*Instance) void, source_label);
}

fn assert_simulate(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "simulate", "backend");

    assert_simulate_key(scope);
    assert_simulate_mouse(scope);
    assert_simulate_text(scope);
}

fn assert_simulate_key(comptime simulate: type) void {
    const scope = RequiredNamespaceType(simulate, "key", "simulate");

    require_fn(scope, "press", fn (Keycode) bool, "simulate.key");
    require_fn(scope, "key_down", fn (Keycode) bool, "simulate.key");
    require_fn(scope, "key_up", fn (Keycode) bool, "simulate.key");
    require_fn(scope, "suppress", fn (Keycode) bool, "simulate.key");
    require_fn(scope, "dummy", fn () bool, "simulate.key");
    require_fn(scope, "combination", fn (*const Modifiers, Keycode) bool, "simulate.key");
    require_fn(scope, "release_modifiers", fn (*const Modifiers) bool, "simulate.key");
}

fn assert_simulate_mouse(comptime simulate: type) void {
    const scope = RequiredNamespaceType(simulate, "mouse", "simulate");

    require_decl(scope, "Button", "simulate.mouse");
    require_decl(scope, "Position", "simulate.mouse");
    require_decl(scope, "scroll_clicks_max", "simulate.mouse");

    require_fn(scope, "click", fn (scope.Button) bool, "simulate.mouse");
    require_fn(scope, "button_down", fn (scope.Button) bool, "simulate.mouse");
    require_fn(scope, "button_up", fn (scope.Button) bool, "simulate.mouse");
    require_fn(scope, "move_to", fn (i32, i32) bool, "simulate.mouse");
    require_fn(scope, "move_relative", fn (i32, i32) bool, "simulate.mouse");
    require_fn(scope, "get_position", fn () scope.Position, "simulate.mouse");
    require_fn(scope, "scroll_up", fn (u32) bool, "simulate.mouse");
    require_fn(scope, "scroll_down", fn (u32) bool, "simulate.mouse");
    require_fn(scope, "scroll_left", fn (u32) bool, "simulate.mouse");
    require_fn(scope, "scroll_right", fn (u32) bool, "simulate.mouse");
}

fn assert_simulate_text(comptime simulate: type) void {
    const scope = RequiredNamespaceType(simulate, "text", "simulate");

    require_decl(scope, "Error", "simulate.text");
    require_decl(scope, "Typer", "simulate.text");

    require_fn(scope, "send", fn ([]const u8) scope.Error!u32, "simulate.text");
    require_fn(scope, "send_with_delay", fn ([]const u8, u32) scope.Error!u32, "simulate.text");
}

fn assert_timer(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "timer", "backend");

    require_decl(scope, "Id", "timer");
    require_decl(scope, "Tick", "timer");
    require_fn(scope, "start", fn (u32, scope.Tick) ?scope.Id, "timer");
    require_fn(scope, "stop", fn (scope.Id) bool, "timer");
}

fn assert_loop(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "loop", "backend");

    require_fn(scope, "run", fn () void, "loop");
    require_fn(scope, "poll", fn (u32) bool, "loop");
    require_fn(scope, "stop", fn () void, "loop");
}

fn assert_window(comptime backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.window_filter) {
        return;
    }

    const scope = RequiredNamespaceType(backend, "window", "backend");

    require_decl(scope, "Handle", "window");
    require_fn(scope, "foreground", fn () ?scope.Handle, "window");
    require_fn(scope, "is_fullscreen", fn (scope.Handle) bool, "window");
    require_fn(scope, "is_maximized", fn (scope.Handle) bool, "window");
    require_fn(scope, "class_matches", fn (scope.Handle, []const u8) bool, "window");
    require_fn(scope, "title_matches", fn (scope.Handle, []const u8) bool, "window");
}

fn assert_monitor(comptime backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.monitor_query) {
        return;
    }

    const scope = RequiredNamespaceType(backend, "monitor", "backend");

    require_decl(scope, "Monitor", "monitor");
    require_decl(scope, "List", "monitor");
    require_decl(scope, "Position", "monitor");
    require_decl(scope, "Screen", "monitor");

    require_fn(scope, "enumerate", fn () scope.List, "monitor");
    require_fn(scope, "get", fn (u8) ?scope.Monitor, "monitor");
    require_fn(scope, "get_primary", fn () ?scope.Monitor, "monitor");
    require_fn(scope, "get_count", fn () u8, "monitor");

    require_fn(scope.List, "enumerate", fn () scope.List, "monitor.List");
    require_fn(scope.List, "get", fn (*const scope.List, u8) ?scope.Monitor, "monitor.List");

    require_fn(scope.Position, "init", fn (i32, i32) scope.Position, "monitor.Position");
    require_fn(scope.Position, "zero", fn () scope.Position, "monitor.Position");

    require_fn(scope.Monitor, "width", fn (*const scope.Monitor) i32, "monitor.Monitor");
    require_fn(scope.Monitor, "height", fn (*const scope.Monitor) i32, "monitor.Monitor");

    require_fn(
        scope.Monitor,
        "center",
        fn (*const scope.Monitor) scope.Position,
        "monitor.Monitor",
    );

    require_fn(scope.Screen, "get", fn () scope.Screen, "monitor.Screen");
}

fn assert_clipboard(comptime backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.clipboard) {
        return;
    }

    const scope = RequiredNamespaceType(backend, "clipboard", "backend");

    require_decl(scope, "Clipboard", "clipboard");
    require_decl(scope, "Error", "clipboard");

    require_fn(scope, "set", fn ([]const u8) scope.Error!void, "clipboard");
    require_fn(scope, "get", fn ([]u8) scope.Error![]const u8, "clipboard");
    require_fn(scope, "clear", fn () scope.Error!void, "clipboard");
    require_fn(scope, "paste", fn () bool, "clipboard");
    require_fn(scope, "copy", fn () bool, "clipboard");
    require_fn(scope, "cut", fn () bool, "clipboard");
    require_fn(scope, "select_all", fn () bool, "clipboard");
    require_fn(scope, "select_left", fn (u32) scope.Error!void, "clipboard");
    require_fn(scope, "select_right", fn (u32) scope.Error!void, "clipboard");
    require_fn(scope, "replace", fn (u32, []const u8) scope.Error!void, "clipboard");
}

fn assert_message(comptime backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.window_targeted_input) {
        return;
    }

    const scope = RequiredNamespaceType(backend, "message", "backend");
    const window = RequiredNamespaceType(backend, "window", "backend");

    require_fn(scope, "send_key", fn (window.Handle, Keycode, bool) bool, "message");
    require_fn(scope, "send_key_press", fn (window.Handle, Keycode) bool, "message");
    require_fn(scope, "send_char", fn (window.Handle, u16) bool, "message");
    require_fn(scope, "post_key", fn (window.Handle, Keycode, bool) bool, "message");
    require_fn(scope, "release_modifiers", fn (window.Handle) bool, "message");
    require_fn(window, "get_focused", fn () ?window.Handle, "window");
}

fn assert_remote(comptime backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.remote) {
        return;
    }

    const scope = RequiredNamespaceType(backend, "remote", "backend");

    require_decl(scope, "BindOptions", "remote");
    require_decl(scope, "Client", "remote");
    require_decl(scope, "KeyAction", "remote");
    require_decl(scope, "Pattern", "remote");
}

fn RequiredNamespaceType(
    comptime scope: type,
    comptime name: []const u8,
    comptime label: []const u8,
) type {
    require_decl(scope, name, label);

    const Namespace = @field(scope, name);

    if (@TypeOf(Namespace) != type) {
        @compileError(
            "nimble backend " ++ label ++ "." ++ name ++ " must be a namespace, found " ++
                @typeName(@TypeOf(Namespace)),
        );
    }

    return Namespace;
}

fn require_decl(comptime scope: type, comptime name: []const u8, comptime label: []const u8) void {
    if (!@hasDecl(scope, name)) {
        @compileError("nimble backend " ++ label ++ " is missing declaration '" ++ name ++ "'");
    }
}

fn require_fn(
    comptime scope: type,
    comptime name: []const u8,
    comptime Signature: type,
    comptime label: []const u8,
) void {
    require_decl(scope, name, label);

    const Actual = @TypeOf(@field(scope, name));

    if (Actual != Signature) {
        @compileError(
            "nimble backend " ++ label ++ "." ++ name ++ " has type " ++ @typeName(Actual) ++
                ", expected " ++ @typeName(Signature),
        );
    }
}

fn require_type(
    comptime scope: type,
    comptime name: []const u8,
    comptime Expected: type,
    comptime label: []const u8,
) void {
    require_decl(scope, name, label);

    const Actual = @field(scope, name);

    if (Actual != Expected) {
        @compileError(
            "nimble backend " ++ label ++ "." ++ name ++ " is " ++ @typeName(Actual) ++
                ", expected " ++ @typeName(Expected),
        );
    }
}

const testing = std.testing;

test "the capability set has the fields the contract names" {
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
    try testing.expectEqual(@as(u8, 0), @intFromEnum(Mode.observe));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(Mode.grab));
}

test "options default to the safe mode" {
    const options = Options{};

    try testing.expect(options.is_valid());
    try testing.expectEqual(Mode.observe, options.mode);
    try testing.expect(options.synthesis);
    try testing.expect(options.rescue);
}

test "options carry an explicit grab request" {
    const options = Options{ .mode = .grab, .synthesis = false, .rescue = false };

    try testing.expect(options.is_valid());
    try testing.expectEqual(Mode.grab, options.mode);
    try testing.expect(!options.synthesis);
    try testing.expect(!options.rescue);
}
