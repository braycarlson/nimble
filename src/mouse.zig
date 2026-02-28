const std = @import("std");

const w32 = @import("win32").everything;

const primitive = @import("hook.zig");
const response_mod = @import("response.zig");
const event = @import("event/mouse.zig");
const registry = @import("registry/mouse.zig");
const simulate_mouse = @import("simulate/mouse.zig");

const builder = @import("builder/mouse.zig");

const Mouse = event.Mouse;
const MouseKind = event.Kind;
const Response = response_mod.Response;
const Position = simulate_mouse.Position;
const Screen = simulate_mouse.Screen;
const Button = simulate_mouse.Button;
const Monitor = simulate_mouse.Monitor;
const MonitorList = simulate_mouse.MonitorList;

pub const Error = error{
    HookInstallFailed,
};

pub const Config = struct {
    capacity: u32 = 128,
};

var instance_global: std.atomic.Value(?*anyopaque) = std.atomic.Value(?*anyopaque).init(null);
var proc_global: std.atomic.Value(?*const fn (c_int, w32.WPARAM, w32.LPARAM) callconv(.c) w32.LRESULT) = std.atomic.Value(?*const fn (c_int, w32.WPARAM, w32.LPARAM) callconv(.c) w32.LRESULT).init(null);

pub fn MouseHook(comptime config: Config) type {
    return struct {
        const Self = @This();

        const Registry = registry.MouseRegistry(config.capacity);

        registry: Registry = Registry.init(),
        running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        mutex: std.Thread.Mutex = .{},
        hook_handle: ?primitive.Hook = null,
        module_handle: ?w32.HINSTANCE = null,
        blocked: bool = false,

        pub fn init() Self {
            return Self{};
        }

        pub fn deinit(self: *Self) void {
            self.stop();
            self.registry.clear();
        }

        pub fn bind(self: *Self, kind: MouseKind) builder.BindBuilder(Self) {
            return builder.BindBuilder(Self).init(self, kind);
        }

        pub fn group(self: *Self) builder.GroupBuilder(Self) {
            return builder.GroupBuilder(Self).init(self);
        }

        pub fn is_blocked(self: *const Self) bool {
            return self.blocked;
        }

        pub fn set_blocked(self: *Self, value: bool) void {
            self.blocked = value;
        }

        pub fn click(_: *Self, button: Button) bool {
            return simulate_mouse.click(button);
        }

        pub fn left_click(_: *Self) bool {
            return simulate_mouse.left_click();
        }

        pub fn right_click(_: *Self) bool {
            return simulate_mouse.right_click();
        }

        pub fn middle_click(_: *Self) bool {
            return simulate_mouse.middle_click();
        }

        pub fn double_click(_: *Self, button: Button) bool {
            return simulate_mouse.double_click(button);
        }

        pub fn left_double_click(_: *Self) bool {
            return simulate_mouse.left_double_click();
        }

        pub fn button_down(_: *Self, button: Button) bool {
            return simulate_mouse.button_down(button);
        }

        pub fn button_up(_: *Self, button: Button) bool {
            return simulate_mouse.button_up(button);
        }

        pub fn move_to(_: *Self, x: i32, y: i32) bool {
            return simulate_mouse.move_to(x, y);
        }

        pub fn move_to_position(_: *Self, position: Position) bool {
            return simulate_mouse.move_to_position(position);
        }

        pub fn move_relative(_: *Self, dx: i32, dy: i32) bool {
            return simulate_mouse.move_relative(dx, dy);
        }

        pub fn move_to_monitor(_: *Self, index: u8, x: i32, y: i32) bool {
            return simulate_mouse.move_to_monitor(index, x, y);
        }

        pub fn move_to_monitor_center(_: *Self, index: u8) bool {
            return simulate_mouse.move_to_monitor_center(index);
        }

        pub fn move_to_primary_monitor(_: *Self, x: i32, y: i32) bool {
            return simulate_mouse.move_to_primary_monitor(x, y);
        }

        pub fn move_to_primary_center(_: *Self) bool {
            return simulate_mouse.move_to_primary_center();
        }

        pub fn scroll_up(_: *Self, clicks: u32) bool {
            return simulate_mouse.scroll_up(clicks);
        }

        pub fn scroll_down(_: *Self, clicks: u32) bool {
            return simulate_mouse.scroll_down(clicks);
        }

        pub fn scroll_left(_: *Self, clicks: u32) bool {
            return simulate_mouse.scroll_left(clicks);
        }

        pub fn scroll_right(_: *Self, clicks: u32) bool {
            return simulate_mouse.scroll_right(clicks);
        }

        pub fn drag(_: *Self, button: Button, from: Position, to: Position) bool {
            return simulate_mouse.drag(button, from, to);
        }

        pub fn left_drag(_: *Self, from: Position, to: Position) bool {
            return simulate_mouse.left_drag(from, to);
        }

        pub fn click_at(_: *Self, button: Button, x: i32, y: i32) bool {
            return simulate_mouse.click_at(button, x, y);
        }

        pub fn left_click_at(_: *Self, x: i32, y: i32) bool {
            return simulate_mouse.left_click_at(x, y);
        }

        pub fn right_click_at(_: *Self, x: i32, y: i32) bool {
            return simulate_mouse.right_click_at(x, y);
        }

        pub fn click_on_monitor(_: *Self, button: Button, index: u8, x: i32, y: i32) bool {
            return simulate_mouse.click_on_monitor(button, index, x, y);
        }

        pub fn left_click_on_monitor(_: *Self, index: u8, x: i32, y: i32) bool {
            return simulate_mouse.left_click_on_monitor(index, x, y);
        }

        pub fn right_click_on_monitor(_: *Self, index: u8, x: i32, y: i32) bool {
            return simulate_mouse.right_click_on_monitor(index, x, y);
        }

        pub fn get_position(_: *Self) Position {
            return simulate_mouse.get_position();
        }

        pub fn get_screen(_: *Self) Screen {
            return Screen.get();
        }

        pub fn get_monitors(_: *Self) MonitorList {
            return simulate_mouse.get_monitors();
        }

        pub fn get_monitor(_: *Self, index: u8) ?Monitor {
            return simulate_mouse.get_monitor(index);
        }

        pub fn get_primary_monitor(_: *Self) ?Monitor {
            return simulate_mouse.get_primary_monitor();
        }

        pub fn get_current_monitor(_: *Self) ?Monitor {
            return simulate_mouse.get_current_monitor();
        }

        pub fn get_monitor_at(_: *Self, x: i32, y: i32) ?Monitor {
            return simulate_mouse.get_monitor_at(x, y);
        }

        pub fn get_monitor_count(_: *Self) u8 {
            return simulate_mouse.get_monitor_count();
        }

        pub fn center(_: *Self) bool {
            const screen = Screen.get();
            const pos = screen.center();
            return simulate_mouse.move_to(pos.x, pos.y);
        }

        pub fn center_on_monitor(_: *Self, index: u8) bool {
            return simulate_mouse.move_to_monitor_center(index);
        }

        pub fn center_on_primary(_: *Self) bool {
            return simulate_mouse.move_to_primary_center();
        }

        pub fn start(self: *Self) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.running.load(.acquire)) {
                return;
            }

            self.module_handle = primitive.module();

            if (self.module_handle == null) {
                return error.HookInstallFailed;
            }

            instance_global.store(self, .release);
            proc_global.store(Self.hook_proc, .release);

            self.hook_handle = primitive.Hook.install(.mouse, wrapper_proc, self.module_handle.?);

            if (self.hook_handle == null) {
                instance_global.store(null, .release);
                proc_global.store(null, .release);
                return error.HookInstallFailed;
            }

            self.running.store(true, .release);
        }

        pub fn stop(self: *Self) void {
            self.mutex.lock();

            if (!self.running.load(.acquire)) {
                self.mutex.unlock();
                return;
            }

            self.running.store(false, .release);
            self.mutex.unlock();

            if (self.hook_handle) |h| {
                _ = h.remove();
                self.hook_handle = null;
            }

            instance_global.store(null, .release);
            proc_global.store(null, .release);
        }

        pub fn is_running(self: *Self) bool {
            return self.running.load(.acquire);
        }

        pub fn is_paused(self: *Self) bool {
            return self.registry.is_paused();
        }

        pub fn set_paused(self: *Self, value: bool) void {
            self.registry.set_paused(value);
        }

        fn hook_proc(
            code_hook: c_int,
            wparam: w32.WPARAM,
            lparam: w32.LPARAM,
        ) callconv(.c) w32.LRESULT {
            if (code_hook < 0) {
                return primitive.next(code_hook, wparam, lparam);
            }

            const parsed = Mouse.parse(wparam, lparam) orelse {
                return primitive.next(code_hook, wparam, lparam);
            };

            const instance: ?*Self = @ptrCast(@alignCast(instance_global.load(.acquire)));

            if (instance == null) {
                return primitive.next(code_hook, wparam, lparam);
            }

            const self = instance.?;

            if (self.blocked) {
                return 1;
            }

            if (self.registry.process(&parsed)) |response| {
                if (response == .consume) {
                    return 1;
                }
            }

            return primitive.next(code_hook, wparam, lparam);
        }
    };
}

fn wrapper_proc(
    code_hook: c_int,
    wparam: w32.WPARAM,
    lparam: w32.LPARAM,
) callconv(.c) w32.LRESULT {
    if (proc_global.load(.acquire)) |proc| {
        return proc(code_hook, wparam, lparam);
    }

    return primitive.next(code_hook, wparam, lparam);
}
