const std = @import("std");

const key_event = @import("event/key.zig");
const keycode = @import("keycode.zig");
const modifier = @import("modifier.zig");
const mouse_event = @import("event/mouse.zig");
const nimble = @import("root.zig");
const platform = @import("platform.zig");
const response_module = @import("response.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Keycode = keycode.Keycode;
const MouseEvent = mouse_event.MouseEvent;
const Fake = nimble.Fake;
const Response = response_module.Response;
const Runtime = nimble.RuntimeType(Fake);
const testing = std.testing;

test {
    _ = @import("builder/keyboard.zig");
    _ = @import("clipboard.zig");
    _ = @import("filter/window.zig");
    _ = @import("keyboard.zig");
    _ = @import("loop.zig");
    _ = @import("mouse.zig");
    _ = @import("pipeline_fuzz.zig");
    _ = @import("platform/fake.zig");
    _ = @import("platform/fake/clipboard.zig");
    _ = @import("platform/fake/keyboard.zig");
    _ = @import("platform/fake/loop.zig");
    _ = @import("platform/fake/monitor.zig");
    _ = @import("platform/fake/mouse.zig");
    _ = @import("platform/fake/record.zig");
    _ = @import("platform/fake/remote_client.zig");
    _ = @import("platform/fake/runtime.zig");
    _ = @import("platform/fake/state.zig");
    _ = @import("platform/fake/time.zig");
    _ = @import("platform/fake/timer.zig");
    _ = @import("platform/fake/window.zig");
    _ = @import("remote.zig");
    _ = @import("root.zig");
    _ = @import("runtime.zig");
    _ = @import("simulate/key.zig");
    _ = @import("simulate/mouse.zig");
    _ = @import("simulate/text.zig");
    _ = @import("time.zig");
}

const Keyboard = Runtime.KeyboardType(.{
    .binding_count_max = 16,
    .chord_count_max = 4,
    .command_count_max = 4,
    .macro_count_max = 2,
    .middleware_count_max = 4,
    .oneshot_count_max = 4,
    .repeat_count_max = 4,
    .sequence_count_max = 4,
    .timer_count_max = 4,
    .toggle_count_max = 4,
});

const Mouse = Runtime.MouseType(.{ .binding_count_max = 8 });
const wait_attempt_max: u32 = 1_000_000;

fn boot() !*Runtime {
    return runtime_open(.{ .mode = .grab });
}

fn runtime_open(options: platform.Options) !*Runtime {
    const runtime = try testing.allocator.create(Runtime);
    errdefer testing.allocator.destroy(runtime);

    try runtime.init(options);

    return runtime;
}

fn shutdown(runtime: *Runtime) void {
    runtime.deinit();

    testing.allocator.destroy(runtime);
}

fn keyboard_open(runtime: *Runtime, storage: *Keyboard) !*Keyboard {
    try storage.init(runtime, .{});

    return storage;
}

fn mouse_open(runtime: *Runtime, storage: *Mouse) *Mouse {
    storage.init(runtime, .{});

    return storage;
}

const Counter = struct {
    hits: u32 = 0,
    last: Keycode = .silent,

    fn on_key(counter: *Counter, key: *const Key) Response {
        counter.hits += 1;
        counter.last = key.value;

        return .consume;
    }

    fn on_key_pass(counter: *Counter, _: *const Key) Response {
        counter.hits += 1;

        return .pass;
    }

    fn on_chord(counter: *Counter) Response {
        counter.hits += 1;

        return .consume;
    }

    fn on_command(counter: *Counter, _: []const u8, _: []const u8) Response {
        counter.hits += 1;

        return .consume;
    }

    fn on_mouse(counter: *Counter, _: *const MouseEvent) Response {
        counter.hits += 1;

        return .consume;
    }

    fn on_void(counter: *Counter) void {
        counter.hits += 1;
    }
};

const Repeater = struct {
    count: std.atomic.Value(u32) = .init(0),

    fn on_repeat(repeater: *Repeater, _: u32) void {
        _ = repeater.count.fetchAdd(1, .seq_cst);
    }
};

fn press(code: Keycode) Key {
    return Key{ .value = code, .down = true, .injected = false };
}

fn release(code: Keycode) Key {
    assert(code != .silent);

    var key = press(code);

    key.down = false;

    return key;
}

fn mouse_event_of(kind: MouseEvent.Kind) MouseEvent {
    return switch (kind) {
        .left_down => MouseEvent.from_button(.{ .button = .left, .down = true }, .{}),
        .left_up => MouseEvent.from_button(.{ .button = .left, .down = false }, .{}),
        .right_down => MouseEvent.from_button(.{ .button = .right, .down = true }, .{}),
        .right_up => MouseEvent.from_button(.{ .button = .right, .down = false }, .{}),
        .middle_down => MouseEvent.from_button(.{ .button = .middle, .down = true }, .{}),
        .middle_up => MouseEvent.from_button(.{ .button = .middle, .down = false }, .{}),
        .x_down => MouseEvent.from_button(.{ .button = .x1, .down = true }, .{}),
        .x_up => MouseEvent.from_button(.{ .button = .x1, .down = false }, .{}),
        .wheel => MouseEvent.from_wheel(.{ .steps_vertical = 1 }, .{}),
        .move => MouseEvent.from_motion(.{}, .{}),
        .other => MouseEvent{ .kind = .other },
    };
}

fn push_chord(runtime: *Runtime, value: Keycode) void {
    assert(value != .silent);

    runtime.platform.loop.push_key(press(.control_left));
    runtime.platform.loop.push_key(press(value));
    runtime.platform.loop.push_key(release(value));
    runtime.platform.loop.push_key(release(.control_left));
}

test "a bound chord consumes the trigger and runs the callback" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.control_left));
    runtime.platform.loop.push_key(press(.a));

    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Keycode.a, app.last);
    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(1));
}

test "an unbound key passes through" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.b));
    runtime.run();

    try testing.expectEqual(@as(u32, 0), app.hits);
    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(0));
}

test "a modifier alone never fires the binding" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.control_left));
    runtime.platform.loop.push_key(release(.control_left));
    runtime.platform.loop.push_key(press(.a));

    runtime.run();

    try testing.expectEqual(@as(u32, 0), app.hits);
}

test "a callback returning pass leaves the event flowing" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key_pass);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.control_left));
    runtime.platform.loop.push_key(press(.a));

    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(1));
}

test "a binding built at runtime matches its pattern twin" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind_key(.a, .from(.{ .ctrl = true })).on(Counter, &app, Counter.on_key);

    const duplicate = hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

    try testing.expectError(error.BindingDuplicate, duplicate);
}

test "an unbound handle stops firing and cannot be unbound twice" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    const handle = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    try hook.unbind(handle);
    try testing.expectError(error.HandleUnknown, hook.unbind(handle));

    runtime.platform.loop.push_key(press(.control_left));
    runtime.platform.loop.push_key(press(.a));
    runtime.run();

    try testing.expectEqual(@as(u32, 0), app.hits);
    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(1));
}

test "synthesis from a callback is recorded" {
    const runtime = try boot();
    defer shutdown(runtime);

    try testing.expect(runtime.key_press(.f5));
    try testing.expect(runtime.platform.record.contains(.key_press, .f5));
    try testing.expectEqual(@as(u16, 1), runtime.platform.record.count_of(.key_press));
}

test "a sequence fires only on the full pattern" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    const handle = try hook.sequence("AB").on(Counter, &app, Counter.on_void);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.a));
    runtime.run();

    try testing.expectEqual(@as(u32, 0), app.hits);

    runtime.platform.loop.push_key(press(.b));
    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);

    try hook.unbind_sequence(handle);

    runtime.platform.loop.push_key(press(.a));
    runtime.platform.loop.push_key(press(.b));
    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "blocking consumes everything except injected events" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    hook.block();

    runtime.platform.loop.push_key(press(.a));
    runtime.run();

    try testing.expect(hook.is_blocked());
    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(0));

    hook.unblock();

    runtime.platform.loop.push_key(press(.b));
    runtime.run();

    try testing.expect(!hook.is_blocked());
    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(1));
}

test "a block exempt binding fires once per press while blocked" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+U").block_exempt().on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    hook.block();

    push_chord(runtime, .u);
    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "mouse bindings consume their kind" {
    const runtime = try boot();
    defer shutdown(runtime);

    var mouse: Mouse = undefined;
    const hook = mouse_open(runtime, &mouse);
    defer hook.deinit();

    var app = Counter{};

    const handle = try hook.bind(.left_down).on(Counter, &app, Counter.on_mouse);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_mouse(mouse_event_of(.left_down));
    runtime.platform.loop.push_mouse(mouse_event_of(.right_down));

    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(0));
    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(1));

    try hook.unbind(handle);

    runtime.platform.loop.push_mouse(mouse_event_of(.left_down));
    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "a blocked mouse hook consumes every event" {
    const runtime = try boot();
    defer shutdown(runtime);

    var mouse: Mouse = undefined;
    const hook = mouse_open(runtime, &mouse);
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    hook.block();

    runtime.platform.loop.push_mouse(mouse_event_of(.move));
    runtime.run();

    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(0));
}

test "virtual time advances only when the queue says so" {
    const runtime = try boot();
    defer shutdown(runtime);

    try testing.expectEqual(@as(i64, 0), runtime.now_ms());

    runtime.platform.loop.push_advance(250);
    runtime.run();

    try testing.expectEqual(@as(i64, 250), runtime.now_ms());
}

test "virtual timers fire on their interval" {
    const runtime = try boot();
    defer shutdown(runtime);

    const Tick = struct {
        count: u32 = 0,

        fn fire(context: *anyopaque) void {
            const tick: *@This() = @ptrCast(@alignCast(context));

            tick.count += 1;
        }
    };

    var tick = Tick{};

    const backend = &runtime.platform;
    const id = backend.timer_start(100, Tick.fire, &tick) orelse return error.TimerUnavailable;
    defer _ = backend.timer_stop(id);

    runtime.platform.loop.push_advance(100);
    runtime.platform.loop.push_advance(100);
    runtime.run();

    try testing.expectEqual(@as(u32, 2), tick.count);
}

test "a hook timer fires only between its start and its stop" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    const timer = try hook.timer(100).on(Counter, &app, Counter.on_void);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_advance(200);
    runtime.run();

    try testing.expectEqual(@as(u32, 0), app.hits);

    try hook.start_timer(timer);
    try testing.expectError(error.TimerRunning, hook.start_timer(timer));

    runtime.platform.loop.push_advance(100);
    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);

    try hook.stop_timer(timer);

    runtime.platform.loop.push_advance(300);
    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectError(error.TimerStopped, hook.stop_timer(timer));
}

test "window filter reads the scripted foreground window" {
    const runtime = try boot();
    defer shutdown(runtime);

    runtime.platform.window.set_class("Notepad");

    const only = Runtime.WindowFilter.for_class("Notepad");
    const other = Runtime.WindowFilter.for_class("Chrome");

    try testing.expect(only.matches(Fake, &runtime.platform));
    try testing.expect(!other.matches(Fake, &runtime.platform));
}

test "clipboard round trips through the fake backend" {
    const runtime = try boot();
    defer shutdown(runtime);

    var buffer: [64]u8 = undefined;

    try runtime.clipboard_set("nimble");

    const text = try runtime.platform.clipboard.get(&buffer);

    try testing.expectEqualStrings("nimble", text);
    try testing.expect(runtime.platform.record.count_of(.clipboard_set) == 1);
}

test "monitor enumeration reports the scripted desktop" {
    const runtime = try boot();
    defer shutdown(runtime);

    var list: nimble.Monitor.List = undefined;

    runtime.monitor_enumerate(&list);

    try testing.expectEqual(@as(u8, 2), list.count);

    const monitor = list.primary() orelse return error.MissingMonitor;

    try testing.expect(monitor.primary);
    try testing.expectEqual(@as(i32, 1920), monitor.width());
    try testing.expect(list.at(.{ .x = 2000, .y = 10 }) != null);
}

test "capabilities report the fake matrix" {
    try testing.expect(Fake.capabilities.clipboard);
    try testing.expect(Fake.capabilities.injected_flag_exact);
    try testing.expect(Fake.capabilities.monitor_query);
    try testing.expect(Fake.capabilities.window_filter);
    try testing.expect(Fake.capabilities.window_targeted_input);
}

const Tagger = struct {
    seen: u32 = 0,
    swallow: bool = false,

    pub fn process(tagger: *Tagger, key: *const Key, next: *const nimble.middleware.Next) Response {
        tagger.seen += 1;

        if (tagger.swallow) {
            return .consume;
        }

        return next.invoke(key);
    }
};

test "a chord fires once its sequence completes" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    const handle = try hook.chord(&.{ .a, .b }).on(Counter, &app, Counter.on_chord);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.a));
    runtime.platform.loop.push_key(press(.b));

    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);

    try hook.unbind_chord(handle);
    try testing.expectError(error.HandleUnknown, hook.unbind_chord(handle));
}

test "a command fires on its trigger, name, and enter" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.command("hi").on(Counter, &app, Counter.on_command);

    hook.command_registry.trigger = ';';

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.semicolon));
    runtime.platform.loop.push_key(press(.h));
    runtime.platform.loop.push_key(press(.i));
    runtime.platform.loop.push_key(press(.enter));

    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "the default command trigger is a shifted semicolon" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.command("hi").on(Counter, &app, Counter.on_command);

    try testing.expectEqual(@as(u8, ':'), hook.command_registry.trigger);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.semicolon));
    runtime.platform.loop.push_key(press(.h));
    runtime.platform.loop.push_key(press(.i));
    runtime.platform.loop.push_key(press(.enter));
    runtime.platform.loop.push_key(press(.shift_left));
    runtime.platform.loop.push_key(press(.semicolon));
    runtime.platform.loop.push_key(release(.shift_left));
    runtime.platform.loop.push_key(press(.h));
    runtime.platform.loop.push_key(press(.i));
    runtime.platform.loop.push_key(press(.enter));

    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(3));
    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(9));
}

test "middleware observes every dispatched key" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};
    var tagger = Tagger{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);
    _ = try hook.add_middleware(Tagger, &tagger);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.control_left));
    runtime.platform.loop.push_key(press(.a));

    runtime.run();

    try testing.expect(tagger.seen >= 1);
    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "middleware can swallow a key before the registries see it" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};
    var tagger = Tagger{ .swallow = true };

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

    const handle = try hook.add_middleware(Tagger, &tagger);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.control_left));
    runtime.platform.loop.push_key(press(.a));

    runtime.run();

    try testing.expect(tagger.seen >= 1);
    try testing.expectEqual(@as(u32, 0), app.hits);
    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(1));

    try hook.remove_middleware(handle);

    runtime.platform.loop.push_key(press(.a));
    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "a toggle switches its action on and off" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+T").toggle("Ctrl+Y").on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    push_chord(runtime, .t);
    runtime.run();

    try testing.expectEqual(@as(u32, 0), app.hits);
    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(1));

    push_chord(runtime, .y);
    push_chord(runtime, .t);
    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(5));
    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(9));

    push_chord(runtime, .y);
    push_chord(runtime, .t);
    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "a oneshot fires on its first press only" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+O").once().on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    push_chord(runtime, .o);
    push_chord(runtime, .o);
    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(1));
    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(5));
}

test "a repeat runs while its key is held and stops on release" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var repeater = Repeater{};

    const handle = try hook.bind("Ctrl+R").repeat(20).on(Repeater, &repeater, Repeater.on_repeat);
    const id = @backingInt(handle);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.control_left));
    runtime.platform.loop.push_key(press(.r));
    runtime.run();

    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(1));
    try testing.expectEqual(true, hook.repeat_registry.is_running(id).?);

    var attempt: u32 = 0;

    while (attempt < wait_attempt_max) : (attempt += 1) {
        if (repeater.count.load(.seq_cst) >= 1) break;

        std.Thread.yield() catch break;
    }

    runtime.platform.loop.push_key(release(.r));
    runtime.run();

    try testing.expectEqual(false, hook.repeat_registry.is_running(id).?);
    try testing.expect(repeater.count.load(.seq_cst) >= 1);
}

test "a macro bound to a key plays its steps" {
    const runtime = try boot();
    defer shutdown(runtime);

    runtime.platform.window.set_present(false);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    _ = try hook.macro("greet").text("hi").key("Enter").bind("Ctrl+G").create();

    try hook.start();
    defer hook.stop();

    push_chord(runtime, .g);
    runtime.run();

    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(1));

    var attempt: u32 = 0;

    while (attempt < wait_attempt_max) : (attempt += 1) {
        if (!hook.macro_registry.is_playing()) break;

        std.Thread.yield() catch break;
    }

    hook.macro_registry.stop();

    try testing.expect(runtime.platform.record.count_of(.text_send) >= 1);
    try testing.expect(runtime.platform.record.contains(.key_press, .enter));
}

test "a macro plays again on the worker that init started" {
    const runtime = try boot();
    defer shutdown(runtime);

    runtime.platform.window.set_present(false);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    _ = try hook.macro("greet").text("hi").bind("Ctrl+G").create();

    try hook.start();
    defer hook.stop();

    const worker = hook.macro_registry.worker orelse return error.TestWorkerMissing;
    var text_counts: [2]u32 = @splat(0);

    for (&text_counts) |*text_count| {
        push_chord(runtime, .g);
        runtime.run();

        var attempt: u32 = 0;

        while (attempt < wait_attempt_max) : (attempt += 1) {
            if (!hook.macro_registry.is_playing()) break;

            std.Thread.yield() catch break;
        }

        hook.macro_registry.stop();
        text_count.* = runtime.platform.record.count_of(.text_send);
    }

    const worker_after = hook.macro_registry.worker orelse return error.TestWorkerMissing;

    try testing.expect(text_counts[0] >= 1);
    try testing.expect(text_counts[1] > text_counts[0]);
    try testing.expectEqual(worker.getHandle(), worker_after.getHandle());
}

test "a targeted macro line arrives as characters ending in a return" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    _ = try hook.macro("greet").line("h\u{e9}").bind("Ctrl+G").create();

    try hook.start();
    defer hook.stop();

    push_chord(runtime, .g);
    runtime.run();

    var attempt: u32 = 0;

    while (attempt < wait_attempt_max) : (attempt += 1) {
        if (!hook.macro_registry.is_playing()) break;

        std.Thread.yield() catch break;
    }

    hook.macro_registry.stop();

    var characters: [4]i32 = @splat(0);
    var character_count: u32 = 0;
    var index: u16 = 0;

    while (index < runtime.platform.record.len()) : (index += 1) {
        const entry = runtime.platform.record.at(index);
        if (entry.kind != .message_char) continue;

        try testing.expect(character_count < characters.len);

        characters[character_count] = entry.amount;
        character_count += 1;
    }

    try testing.expectEqualSlices(i32, &.{ 'h', 0xE9, '\r' }, characters[0..character_count]);
    try testing.expect(!runtime.platform.record.contains(.message_key, .enter));
}

test "the recorded queue is replayable and deterministic" {
    var first: u16 = 0;

    {
        const runtime = try boot();
        defer shutdown(runtime);

        var keyboard: Keyboard = undefined;
        const hook = try keyboard_open(runtime, &keyboard);
        defer hook.deinit();

        var app = Counter{};

        _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

        try hook.start();
        defer hook.stop();

        runtime.platform.loop.push_key(press(.control_left));
        runtime.platform.loop.push_key(press(.a));
        runtime.run();

        first = runtime.platform.loop.response_len();
    }

    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.control_left));
    runtime.platform.loop.push_key(press(.a));
    runtime.run();

    try testing.expectEqual(first, runtime.platform.loop.response_len());
    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "the loop stays runnable until the queue runs dry" {
    const runtime = try boot();
    defer shutdown(runtime);

    runtime.platform.loop.push_advance(1);

    try testing.expect(runtime.poll(0));
    try testing.expect(!runtime.poll(0));
}

test "the loop stops being runnable once it is stopped" {
    const runtime = try boot();
    defer shutdown(runtime);

    runtime.platform.loop.push_advance(1);
    runtime.platform.loop.push_advance(1);

    runtime.stop();

    try testing.expect(!runtime.poll(0));
    try testing.expectEqual(@as(u16, 2), runtime.platform.loop.pending());
}

test "observe mode clamps a consuming binding down to pass" {
    const runtime = try runtime_open(.{ .mode = .observe });
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.control_left));
    runtime.platform.loop.push_key(press(.a));

    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(1));
}

test "observe mode clamps a blocked hook down to pass" {
    const runtime = try runtime_open(.{ .mode = .observe });
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    hook.block();

    runtime.platform.loop.push_key(press(.a));
    runtime.run();

    try testing.expect(hook.is_blocked());
    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(0));
}

test "observe mode clamps mouse bindings down to pass" {
    const runtime = try runtime_open(.{ .mode = .observe });
    defer shutdown(runtime);

    var mouse: Mouse = undefined;
    const hook = mouse_open(runtime, &mouse);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind(.left_down).on(Counter, &app, Counter.on_mouse);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_mouse(mouse_event_of(.left_down));
    runtime.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(0));
}

test "the runtime records the mode a program drives it through" {
    const runtime = try boot();
    defer shutdown(runtime);

    try testing.expectEqual(Runtime.Mode.grab, runtime.mode());
    try testing.expectEqual(Runtime.Mode.grab, runtime.platform.runtime.options.mode);

    runtime.release_grab();

    try testing.expectEqual(Runtime.Mode.observe, runtime.mode());
}

test "a second hook of one kind is a request error" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    var second: Runtime.KeyboardType(.{}) = undefined;

    try second.init(runtime, .{});
    defer second.deinit();

    try testing.expectError(error.HookDuplicate, second.start());
}

const Recorder = struct {
    seen: [8]MouseEvent = undefined,
    count: u8 = 0,

    fn on_mouse(recorder: *Recorder, event: *const MouseEvent) Response {
        if (recorder.count < recorder.seen.len) {
            recorder.seen[recorder.count] = event.*;
            recorder.count += 1;
        }

        return .pass;
    }
};

test "a wheel event reaches a binding with signed steps intact" {
    const runtime = try boot();
    defer shutdown(runtime);

    var mouse: Mouse = undefined;
    const hook = mouse_open(runtime, &mouse);
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.wheel).on(Recorder, &app, Recorder.on_mouse);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_mouse(MouseEvent.from_wheel(.{ .steps_vertical = 1 }, .{}));
    runtime.platform.loop.push_mouse(MouseEvent.from_wheel(.{ .steps_vertical = -1 }, .{}));
    runtime.platform.loop.push_mouse(MouseEvent.from_wheel(.{ .steps_horizontal = 2 }, .{}));

    runtime.run();

    try testing.expectEqual(@as(u8, 3), app.count);
    try testing.expectEqual(@as(i32, 1), app.seen[0].payload.wheel.steps_vertical);
    try testing.expectEqual(@as(i32, -1), app.seen[1].payload.wheel.steps_vertical);
    try testing.expectEqual(@as(i32, 2), app.seen[2].payload.wheel.steps_horizontal);
}

test "a Windows shaped and a Linux shaped scroll reach the pipeline identically" {
    const runtime = try boot();
    defer shutdown(runtime);

    var mouse: Mouse = undefined;
    const hook = mouse_open(runtime, &mouse);
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.wheel).on(Recorder, &app, Recorder.on_mouse);

    try hook.start();
    defer hook.stop();

    const windows_shaped = MouseEvent.from_wheel(.{
        .steps_vertical = 1,
        .position = .{ .x = 7, .y = 9 },
    }, .{});

    const linux_shaped = MouseEvent.from_wheel(.{ .steps_vertical = 1 }, .{});

    runtime.platform.loop.push_mouse(windows_shaped);
    runtime.platform.loop.push_mouse(linux_shaped);

    runtime.run();

    try testing.expectEqual(@as(u8, 2), app.count);
    try testing.expectEqual(app.seen[0].kind, app.seen[1].kind);

    try testing.expectEqual(
        app.seen[0].payload.wheel.steps_vertical,
        app.seen[1].payload.wheel.steps_vertical,
    );

    try testing.expect(app.seen[0].position() != null);
    try testing.expect(app.seen[1].position() == null);
}

test "a motion event carries deltas through the pipeline" {
    const runtime = try boot();
    defer shutdown(runtime);

    var mouse: Mouse = undefined;
    const hook = mouse_open(runtime, &mouse);
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.move).on(Recorder, &app, Recorder.on_mouse);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_mouse(MouseEvent.from_motion(.{ .delta_x = 5, .delta_y = -4 }, .{}));
    runtime.run();

    try testing.expectEqual(@as(u8, 1), app.count);
    try testing.expectEqual(@as(i32, 5), app.seen[0].payload.motion.delta_x);
    try testing.expectEqual(@as(i32, -4), app.seen[0].payload.motion.delta_y);
}

test "a side button keeps its identity through the pipeline" {
    const runtime = try boot();
    defer shutdown(runtime);

    var mouse: Mouse = undefined;
    const hook = mouse_open(runtime, &mouse);
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.x_down).on(Recorder, &app, Recorder.on_mouse);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_mouse(MouseEvent.from_button(.{ .button = .x2, .down = true }, .{}));
    runtime.run();

    try testing.expectEqual(@as(u8, 1), app.count);
    try testing.expectEqual(MouseEvent.Button.x2, app.seen[0].button().?);
    try testing.expectEqual(MouseEvent.Kind.x_down, app.seen[0].kind);
}

const Observer = struct {
    seen: [8]Key = undefined,
    count: u8 = 0,

    fn on_key(observer: *Observer, key: *const Key) Response {
        if (observer.count < observer.seen.len) {
            observer.seen[observer.count] = key.*;
            observer.count += 1;
        }

        return .pass;
    }
};

test "the key callback sees the same modifier set the registries see" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    var app = Observer{};

    hook.set_key_callback(Observer, &app, Observer.on_key);

    try hook.start();
    defer hook.stop();

    runtime.platform.loop.push_key(press(.control_left));
    runtime.platform.loop.push_key(press(.a));

    runtime.run();

    try testing.expectEqual(@as(u8, 2), app.count);
    try testing.expectEqual(Keycode.a, app.seen[1].value);
    try testing.expect(app.seen[1].modifiers.ctrl());
    try testing.expect(app.seen[1].modifiers.flags != modifier.flag_none);

    hook.clear_key_callback();

    runtime.platform.loop.push_key(press(.b));
    runtime.run();

    try testing.expectEqual(@as(u8, 2), app.count);
}

test "a Windows shaped and a Linux shaped motion keep their own payloads" {
    const runtime = try boot();
    defer shutdown(runtime);

    var mouse: Mouse = undefined;
    const hook = mouse_open(runtime, &mouse);
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.move).on(Recorder, &app, Recorder.on_mouse);

    try hook.start();
    defer hook.stop();

    const windows_shaped = MouseEvent.from_motion(.{ .position = .{ .x = 11, .y = 22 } }, .{});
    const linux_shaped = MouseEvent.from_motion(.{ .delta_x = 5, .delta_y = -4 }, .{});

    runtime.platform.loop.push_mouse(windows_shaped);
    runtime.platform.loop.push_mouse(linux_shaped);

    runtime.run();

    try testing.expectEqual(@as(u8, 2), app.count);

    try testing.expect(app.seen[0].position().?.eql(.{ .x = 11, .y = 22 }));
    try testing.expectEqual(@as(i32, 0), app.seen[0].payload.motion.delta_x);
    try testing.expectEqual(@as(i32, 0), app.seen[0].payload.motion.delta_y);

    try testing.expect(app.seen[1].position() == null);
    try testing.expectEqual(@as(i32, 5), app.seen[1].payload.motion.delta_x);
    try testing.expectEqual(@as(i32, -4), app.seen[1].payload.motion.delta_y);
}

test "an injected key is passed through when the hook is blocked" {
    const runtime = try boot();
    defer shutdown(runtime);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(runtime, &keyboard);
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    hook.block();

    var key = press(.a);

    key.injected = true;

    runtime.platform.loop.push_key(key);
    runtime.platform.loop.push_key(press(.b));

    runtime.run();

    try testing.expectEqual(Response.pass, runtime.platform.loop.response_at(0));
    try testing.expectEqual(Response.consume, runtime.platform.loop.response_at(1));
}
