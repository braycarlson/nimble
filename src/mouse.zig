const std = @import("std");

const builder = @import("builder/mouse.zig");
const event = @import("event/mouse.zig");
const platform = @import("platform.zig");
const registry = @import("registry/mouse.zig");
const response_mod = @import("response.zig");
const runtime = @import("runtime.zig");
const sync = @import("sync.zig");

const assert = std.debug.assert;
const Mutex = sync.Mutex;
const simulate_mouse = platform.backend.simulate.mouse;
const Mouse = event.Mouse;
const MouseKind = event.Kind;
const Response = response_mod.Response;
const Position = simulate_mouse.Position;
const Screen = simulate_mouse.Screen;
const Button = simulate_mouse.Button;
const Monitor = simulate_mouse.Monitor;
const MonitorList = simulate_mouse.MonitorList;

pub const Error = error{
    HookAlreadyInstalled,
    HookInstallFailed,
};

pub const Config = struct {
    capacity: u32 = 128,
    pass_injected: bool = true,
};

fn require(comptime available: bool, comptime feature: []const u8) void {
    if (!available) {
        @compileError("nimble: " ++ feature ++ " is not available on this backend");
    }
}

pub fn MouseHookType(comptime config: Config) type {
    return struct {
        const Instance = @This();

        const Source = platform.backend.mouse.SourceType(Instance);
        const Registry = registry.MouseRegistryType(config.capacity);

        registry: Registry = Registry.init(),
        running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        mutex: Mutex = .{},
        source: Source = Source.init(),
        blocked: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        pub fn init() Instance {
            return Instance{};
        }

        pub fn deinit(instance: *Instance) void {
            instance.stop();
            instance.registry.clear();
        }

        pub fn bind(instance: *Instance, kind: MouseKind) builder.BindBuilderType(Instance) {
            return builder.BindBuilderType(Instance).init(instance, kind);
        }

        pub fn group(instance: *Instance) builder.GroupBuilderType(Instance) {
            return builder.GroupBuilderType(Instance).init(instance);
        }

        pub fn is_blocked(instance: *const Instance) bool {
            return instance.blocked.load(.seq_cst);
        }

        pub fn set_blocked(instance: *Instance, value: bool) void {
            instance.blocked.store(value, .seq_cst);
        }

        pub fn click(_: *Instance, button: Button) bool {
            return simulate_mouse.click(button);
        }

        pub fn left_click(_: *Instance) bool {
            return simulate_mouse.left_click();
        }

        pub fn right_click(_: *Instance) bool {
            return simulate_mouse.right_click();
        }

        pub fn middle_click(_: *Instance) bool {
            return simulate_mouse.middle_click();
        }

        pub fn double_click(_: *Instance, button: Button) bool {
            return simulate_mouse.double_click(button);
        }

        pub fn left_double_click(_: *Instance) bool {
            return simulate_mouse.left_double_click();
        }

        pub fn button_down(_: *Instance, button: Button) bool {
            return simulate_mouse.button_down(button);
        }

        pub fn button_up(_: *Instance, button: Button) bool {
            return simulate_mouse.button_up(button);
        }

        pub fn move_to(_: *Instance, x: i32, y: i32) bool {
            return simulate_mouse.move_to(x, y);
        }

        pub fn move_to_position(_: *Instance, position: Position) bool {
            return simulate_mouse.move_to_position(position);
        }

        pub fn move_relative(_: *Instance, dx: i32, dy: i32) bool {
            return simulate_mouse.move_relative(dx, dy);
        }

        pub fn move_to_monitor(_: *Instance, index: u8, x: i32, y: i32) bool {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.move_to_monitor(index, x, y);
        }

        pub fn move_to_monitor_center(_: *Instance, index: u8) bool {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.move_to_monitor_center(index);
        }

        pub fn move_to_primary_monitor(_: *Instance, x: i32, y: i32) bool {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.move_to_primary_monitor(x, y);
        }

        pub fn move_to_primary_center(_: *Instance) bool {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.move_to_primary_center();
        }

        pub fn scroll_up(_: *Instance, clicks: u32) bool {
            assert(clicks >= 1);
            assert(clicks <= simulate_mouse.scroll_clicks_max);

            return simulate_mouse.scroll_up(clicks);
        }

        pub fn scroll_down(_: *Instance, clicks: u32) bool {
            assert(clicks >= 1);
            assert(clicks <= simulate_mouse.scroll_clicks_max);

            return simulate_mouse.scroll_down(clicks);
        }

        pub fn scroll_left(_: *Instance, clicks: u32) bool {
            return simulate_mouse.scroll_left(clicks);
        }

        pub fn scroll_right(_: *Instance, clicks: u32) bool {
            return simulate_mouse.scroll_right(clicks);
        }

        pub fn drag(_: *Instance, button: Button, from: Position, to: Position) bool {
            return simulate_mouse.drag(button, from, to);
        }

        pub fn left_drag(_: *Instance, from: Position, to: Position) bool {
            return simulate_mouse.left_drag(from, to);
        }

        pub fn click_at(_: *Instance, button: Button, x: i32, y: i32) bool {
            return simulate_mouse.click_at(button, x, y);
        }

        pub fn left_click_at(_: *Instance, x: i32, y: i32) bool {
            return simulate_mouse.left_click_at(x, y);
        }

        pub fn right_click_at(_: *Instance, x: i32, y: i32) bool {
            return simulate_mouse.right_click_at(x, y);
        }

        pub fn click_on_monitor(_: *Instance, button: Button, index: u8, x: i32, y: i32) bool {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.click_on_monitor(button, index, x, y);
        }

        pub fn left_click_on_monitor(_: *Instance, index: u8, x: i32, y: i32) bool {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.left_click_on_monitor(index, x, y);
        }

        pub fn right_click_on_monitor(_: *Instance, index: u8, x: i32, y: i32) bool {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.right_click_on_monitor(index, x, y);
        }

        pub fn get_position(_: *Instance) Position {
            return simulate_mouse.get_position();
        }

        pub fn get_screen(_: *Instance) Screen {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return Screen.get();
        }

        pub fn get_monitors(_: *Instance) MonitorList {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.get_monitors();
        }

        pub fn get_monitor(_: *Instance, index: u8) ?Monitor {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.get_monitor(index);
        }

        pub fn get_primary_monitor(_: *Instance) ?Monitor {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.get_primary_monitor();
        }

        pub fn get_current_monitor(_: *Instance) ?Monitor {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.get_current_monitor();
        }

        pub fn get_monitor_at(_: *Instance, x: i32, y: i32) ?Monitor {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.get_monitor_at(x, y);
        }

        pub fn get_monitor_count(_: *Instance) u8 {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.get_monitor_count();
        }

        pub fn center(_: *Instance) bool {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            const screen = Screen.get();
            const position = screen.center();

            return simulate_mouse.move_to(position.x, position.y);
        }

        pub fn center_on_monitor(_: *Instance, index: u8) bool {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.move_to_monitor_center(index);
        }

        pub fn center_on_primary(_: *Instance) bool {
            comptime require(platform.capabilities.monitor_query, "monitor query");

            return simulate_mouse.move_to_primary_center();
        }

        pub fn start(instance: *Instance) !void {
            assert(runtime.is_open());

            instance.mutex.lock();
            defer instance.mutex.unlock();

            if (instance.running.load(.seq_cst)) {
                return;
            }

            try instance.source.install(instance);

            instance.running.store(true, .seq_cst);

            assert(instance.running.load(.seq_cst));
        }

        pub fn stop(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            if (!instance.running.load(.seq_cst)) {
                return;
            }

            instance.running.store(false, .seq_cst);

            instance.source.remove();

            assert(!instance.running.load(.seq_cst));
        }

        pub fn is_running(instance: *Instance) bool {
            return instance.running.load(.seq_cst);
        }

        pub fn is_paused(instance: *Instance) bool {
            return instance.registry.is_paused();
        }

        pub fn set_paused(instance: *Instance, value: bool) void {
            instance.registry.set_paused(value);
        }

        pub fn process(instance: *Instance, parsed: *const Mouse) Response {
            assert(parsed.is_valid());

            return runtime.clamp(instance.resolve(parsed));
        }

        fn resolve(instance: *Instance, parsed: *const Mouse) Response {
            assert(parsed.is_valid());

            if (config.pass_injected and parsed.injected) {
                return .pass;
            }

            if (instance.blocked.load(.seq_cst)) {
                return .consume;
            }

            if (instance.registry.process(parsed)) |response| {
                if (response == .consume) {
                    return .consume;
                }
            }

            return .pass;
        }
    };
}
