const std = @import("std");

const nimble = @import("root.zig");
const platform = @import("platform.zig");
const key_event = @import("event/key.zig");
const mouse_event = @import("event/mouse.zig");
const modifier = @import("modifier.zig");
const keycode = @import("keycode.zig");
const response_mod = @import("response.zig");

const Key = key_event.Key;
const Keycode = keycode.Keycode;
const MouseEvent = mouse_event.Mouse;
const Response = response_mod.Response;
const mock = platform.backend;
const testing = std.testing;

test {
    _ = @import("platform/mock/clipboard.zig");
    _ = @import("platform/mock/hook.zig");
    _ = @import("platform/mock/keyboard.zig");
    _ = @import("platform/mock/keycode.zig");
    _ = @import("platform/mock/loop.zig");
    _ = @import("platform/mock/monitor.zig");
    _ = @import("platform/mock/mouse.zig");
    _ = @import("platform/mock/record.zig");
    _ = @import("platform/mock/remote.zig");
    _ = @import("platform/mock/runtime.zig");
    _ = @import("platform/mock/simulate/key.zig");
    _ = @import("platform/mock/simulate/message.zig");
    _ = @import("platform/mock/simulate/mouse.zig");
    _ = @import("platform/mock/simulate/text.zig");
    _ = @import("platform/mock/state.zig");
    _ = @import("platform/mock/timer.zig");
    _ = @import("platform/mock/time.zig");
    _ = @import("platform/mock/window.zig");
    _ = @import("filter/window.zig");
    _ = @import("pipeline_fuzz.zig");
}

const Keyboard = nimble.KeyboardType(.{});
const Mouse = nimble.MouseType(.{});

fn boot() !void {
    mock.reset();

    try nimble.runtime.open(.{ .mode = .grab });
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

fn press(code: Keycode) Key {
    return Key{
        .value = code,
        .down = true,
        .injected = false,
    };
}

fn release(code: Keycode) Key {
    var key = press(code);
    key.down = false;

    return key;
}

fn mouse_event_of(kind: mouse_event.Kind) MouseEvent {
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

test "pipeline: a bound chord consumes the trigger and runs the callback" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(&app, Counter.on_key);
    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.a));

    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Keycode.a, app.last);
    try testing.expectEqual(Response.consume, mock.loop.response_at(1));
}

test "pipeline: an unbound key passes through" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(&app, Counter.on_key);
    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.b));
    mock.loop.run();

    try testing.expectEqual(@as(u32, 0), app.hits);
    try testing.expectEqual(Response.pass, mock.loop.response_at(0));
}

test "pipeline: a modifier alone never fires the binding" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(&app, Counter.on_key);
    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(release(.control_left));
    mock.loop.push_key(press(.a));

    mock.loop.run();

    try testing.expectEqual(@as(u32, 0), app.hits);
}

test "pipeline: a callback returning pass leaves the event flowing" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(&app, Counter.on_key_pass);
    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.a));

    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.pass, mock.loop.response_at(1));
}

test "pipeline: synthesis from a callback is recorded" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    _ = hook.press(.f5);

    try testing.expect(mock.record.contains(.key_press, .f5));
    try testing.expectEqual(@as(u16, 1), mock.record.count_of(.key_press));
}

test "pipeline: a sequence fires only on the full pattern" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.sequence("AB").on(&app, Counter.on_void);
    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.a));
    mock.loop.run();

    try testing.expectEqual(@as(u32, 0), app.hits);

    mock.loop.push_key(press(.b));
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "pipeline: blocking consumes everything except injected events" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    hook.set_blocked(true);

    mock.loop.push_key(press(.a));
    mock.loop.run();

    try testing.expect(hook.is_blocked());
    try testing.expectEqual(Response.consume, mock.loop.response_at(0));
}

test "pipeline: mouse bindings consume their kind" {
    try boot();

    var hook = Mouse.init();
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind(.left_down).on(&app, Counter.on_mouse);
    try hook.start();
    defer hook.stop();

    mock.loop.push_mouse(mouse_event_of(.left_down));
    mock.loop.push_mouse(mouse_event_of(.right_down));

    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.consume, mock.loop.response_at(0));
    try testing.expectEqual(Response.pass, mock.loop.response_at(1));
}

test "virtual time advances only when the tape says so" {
    try boot();

    try testing.expectEqual(@as(i64, 0), mock.time.now_ms());

    mock.loop.push_advance(250);
    mock.loop.run();

    try testing.expectEqual(@as(i64, 250), mock.time.now_ms());
}

test "virtual timers fire on their interval" {
    try boot();

    const Tick = struct {
        var count: u32 = 0;

        fn fire() void {
            count += 1;
        }
    };

    Tick.count = 0;

    const id = mock.timer.start(100, Tick.fire) orelse return error.TimerUnavailable;
    defer _ = mock.timer.stop(id);

    mock.loop.push_advance(100);
    mock.loop.push_advance(100);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 2), Tick.count);
}

test "window filter reads the scripted foreground window" {
    try boot();

    mock.window.set_class("Notepad");

    const only = nimble.WindowFilter.for_class("Notepad");
    const other = nimble.WindowFilter.for_class("Chrome");

    try testing.expect(only.matches());
    try testing.expect(!other.matches());
}

test "clipboard round trips through the mock backend" {
    try boot();

    var buffer: [64]u8 = undefined;

    try mock.clipboard.set("nimble");

    const text = try mock.clipboard.get(&buffer);

    try testing.expectEqualStrings("nimble", text);
    try testing.expect(mock.record.count_of(.clipboard_set) == 1);
}

test "monitor query reports the scripted desktop" {
    try boot();

    try testing.expectEqual(@as(u8, 2), mock.monitor.get_count());

    const primary = mock.monitor.get_primary() orelse return error.MissingMonitor;

    try testing.expect(primary.primary);
    try testing.expectEqual(@as(i32, 1920), primary.width());
}

test "capabilities report the mock matrix" {
    try testing.expect(platform.capabilities.clipboard);
    try testing.expect(platform.capabilities.injected_flag_exact);
    try testing.expect(platform.capabilities.monitor_query);
    try testing.expect(platform.capabilities.window_filter);
    try testing.expect(platform.capabilities.window_targeted_input);
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

test "pipeline: a chord fires once its sequence completes" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.chord("AB").on(&app, Counter.on_chord);
    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.a));
    mock.loop.push_key(press(.b));

    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "pipeline: a command fires on its trigger, name, and enter" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.command("hi").on(&app, Counter.on_command);

    hook.command_registry.trigger = ';';

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.semicolon));
    mock.loop.push_key(press(.h));
    mock.loop.push_key(press(.i));
    mock.loop.push_key(press(.enter));

    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "the default command trigger is unreachable through from_keycode" {
    const character = @import("character.zig");
    const registry = nimble.registry.command.CommandRegistryType(4).init();

    try testing.expectEqual(@as(u8, ':'), registry.trigger);
    try testing.expectEqual(@as(u8, ';'), character.from_keycode(.semicolon));
    try testing.expect(character.from_keycode(.semicolon) != registry.trigger);
}

test "pipeline: middleware observes every dispatched key" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};
    var tagger = Tagger{};

    _ = try hook.bind("Ctrl+A").on(&app, Counter.on_key);
    _ = try hook.add_middleware(Tagger, &tagger);

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.a));

    mock.loop.run();

    try testing.expect(tagger.seen >= 1);
    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "pipeline: middleware can swallow a key before the registries see it" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};
    var tagger = Tagger{ .swallow = true };

    _ = try hook.bind("Ctrl+A").on(&app, Counter.on_key);
    _ = try hook.add_middleware(Tagger, &tagger);

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.a));

    mock.loop.run();

    try testing.expect(tagger.seen >= 1);
    try testing.expectEqual(@as(u32, 0), app.hits);
    try testing.expectEqual(Response.consume, mock.loop.response_at(1));
}

test "pipeline: a toggle binding registers without touching a real device" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};

    const id = try hook.bind("Ctrl+T").toggle("Ctrl+Y").on(&app, Counter.on_key);

    try testing.expect(id >= 1);

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.t));

    mock.loop.run();

    try testing.expect(mock.loop.response_len() == 2);
}

test "pipeline: paused registries stop dispatching" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(&app, Counter.on_key);
    try hook.start();
    defer hook.stop();

    hook.set_paused(true);

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.a));

    mock.loop.run();

    try testing.expect(hook.is_paused());
    try testing.expectEqual(@as(u32, 0), app.hits);
}

test "pipeline: the recorded tape is replayable and deterministic" {
    try boot();

    var first: u16 = 0;

    {
        var hook = Keyboard.init();
        defer hook.deinit();

        var app = Counter{};

        _ = try hook.bind("Ctrl+A").on(&app, Counter.on_key);
        try hook.start();
        defer hook.stop();

        mock.loop.push_key(press(.control_left));
        mock.loop.push_key(press(.a));
        mock.loop.run();

        first = mock.loop.response_len();
    }

    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(&app, Counter.on_key);
    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.a));
    mock.loop.run();

    try testing.expectEqual(first, mock.loop.response_len());
    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "the loop stays runnable until the tape runs dry" {
    try boot();

    mock.loop.push_advance(1);

    try testing.expect(nimble.loop.poll(0));
    try testing.expect(!nimble.loop.poll(0));
}

test "the loop stops being runnable once it is stopped" {
    try boot();

    mock.loop.push_advance(1);
    mock.loop.push_advance(1);

    nimble.loop.stop();

    try testing.expect(!nimble.loop.poll(0));
    try testing.expectEqual(@as(u16, 2), mock.loop.pending());
}

test "the loop stops being runnable once the runtime closes" {
    try boot();

    mock.loop.push_advance(1);
    nimble.runtime.close();

    try testing.expect(!nimble.loop.poll(0));
}

test "observe mode clamps a consuming binding down to pass" {
    mock.reset();

    try nimble.runtime.open(.{ .mode = .observe });
    defer nimble.runtime.close();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(&app, Counter.on_key);
    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.a));

    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.pass, mock.loop.response_at(1));
}

test "observe mode clamps a blocked hook down to pass" {
    mock.reset();

    try nimble.runtime.open(.{ .mode = .observe });
    defer nimble.runtime.close();

    var hook = Keyboard.init();
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    hook.set_blocked(true);

    mock.loop.push_key(press(.a));
    mock.loop.run();

    try testing.expect(hook.is_blocked());
    try testing.expectEqual(Response.pass, mock.loop.response_at(0));
}

test "observe mode clamps mouse bindings down to pass" {
    mock.reset();

    try nimble.runtime.open(.{ .mode = .observe });
    defer nimble.runtime.close();

    var hook = Mouse.init();
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind(.left_down).on(&app, Counter.on_mouse);
    try hook.start();
    defer hook.stop();

    mock.loop.push_mouse(mouse_event_of(.left_down));
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.pass, mock.loop.response_at(0));
}

test "the runtime records the lifecycle a program drives it through" {
    mock.reset();

    try testing.expect(!nimble.runtime.is_open());

    try nimble.runtime.open(.{ .mode = .grab });

    try testing.expect(nimble.runtime.is_open());
    try testing.expectEqual(nimble.Mode.grab, nimble.runtime.mode());
    try testing.expect(!nimble.runtime.observes());

    nimble.runtime.close();

    try testing.expect(!nimble.runtime.is_open());
    try testing.expect(nimble.runtime.observes());
    try testing.expectEqual(@as(u16, 1), mock.runtime.opens());
    try testing.expectEqual(@as(u16, 1), mock.runtime.closes());
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
    try boot();

    var hook = Mouse.init();
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.wheel).on(&app, Recorder.on_mouse);
    try hook.start();
    defer hook.stop();

    mock.loop.push_mouse(MouseEvent.from_wheel(.{ .steps_vertical = 1 }, .{}));
    mock.loop.push_mouse(MouseEvent.from_wheel(.{ .steps_vertical = -1 }, .{}));
    mock.loop.push_mouse(MouseEvent.from_wheel(.{ .steps_horizontal = 2 }, .{}));

    mock.loop.run();

    try testing.expectEqual(@as(u8, 3), app.count);
    try testing.expectEqual(@as(i32, 1), app.seen[0].payload.wheel.steps_vertical);
    try testing.expectEqual(@as(i32, -1), app.seen[1].payload.wheel.steps_vertical);
    try testing.expectEqual(@as(i32, 2), app.seen[2].payload.wheel.steps_horizontal);
}

test "a Windows shaped and a Linux shaped scroll reach the pipeline identically" {
    try boot();

    var hook = Mouse.init();
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.wheel).on(&app, Recorder.on_mouse);
    try hook.start();
    defer hook.stop();

    const windows_shaped = MouseEvent.from_wheel(.{
        .steps_vertical = 1,
        .position = nimble.MousePosition.init(7, 9),
    }, .{});

    const linux_shaped = MouseEvent.from_wheel(.{ .steps_vertical = 1 }, .{});

    mock.loop.push_mouse(windows_shaped);
    mock.loop.push_mouse(linux_shaped);

    mock.loop.run();

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
    try boot();

    var hook = Mouse.init();
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.move).on(&app, Recorder.on_mouse);
    try hook.start();
    defer hook.stop();

    mock.loop.push_mouse(MouseEvent.from_motion(.{ .delta_x = 5, .delta_y = -4 }, .{}));
    mock.loop.run();

    try testing.expectEqual(@as(u8, 1), app.count);
    try testing.expectEqual(@as(i32, 5), app.seen[0].payload.motion.delta_x);
    try testing.expectEqual(@as(i32, -4), app.seen[0].payload.motion.delta_y);
}

test "a side button keeps its identity through the pipeline" {
    try boot();

    var hook = Mouse.init();
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.x_down).on(&app, Recorder.on_mouse);
    try hook.start();
    defer hook.stop();

    mock.loop.push_mouse(MouseEvent.from_button(.{ .button = .x2, .down = true }, .{}));
    mock.loop.run();

    try testing.expectEqual(@as(u8, 1), app.count);
    try testing.expectEqual(nimble.MouseButton.x2, app.seen[0].button().?);
    try testing.expectEqual(nimble.MouseKind.x_down, app.seen[0].kind);
}

const Observer = struct {
    seen: [8]Key = undefined,
    count: u8 = 0,

    fn on_key(context: *anyopaque, key: *const Key) ?Response {
        const self: *Observer = @ptrCast(@alignCast(context));

        if (self.count < self.seen.len) {
            self.seen[self.count] = key.*;
            self.count += 1;
        }

        return null;
    }
};

test "the key callback sees the same modifier set the registries see" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    var app = Observer{};

    hook.set_key_callback(Observer.on_key, &app);

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.a));

    mock.loop.run();

    try testing.expectEqual(@as(u8, 2), app.count);
    try testing.expectEqual(Keycode.a, app.seen[1].value);
    try testing.expect(app.seen[1].modifiers.ctrl());
    try testing.expect(app.seen[1].modifiers.flags != modifier.flag_none);
}

test "a Windows shaped and a Linux shaped motion keep their own payloads" {
    try boot();

    var hook = Mouse.init();
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.move).on(&app, Recorder.on_mouse);
    try hook.start();
    defer hook.stop();

    const windows_shaped = MouseEvent.from_motion(.{
        .position = nimble.MousePosition.init(11, 22),
    }, .{});

    const linux_shaped = MouseEvent.from_motion(.{ .delta_x = 5, .delta_y = -4 }, .{});

    mock.loop.push_mouse(windows_shaped);
    mock.loop.push_mouse(linux_shaped);

    mock.loop.run();

    try testing.expectEqual(@as(u8, 2), app.count);

    try testing.expect(app.seen[0].position().?.eql(nimble.MousePosition.init(11, 22)));
    try testing.expectEqual(@as(i32, 0), app.seen[0].payload.motion.delta_x);
    try testing.expectEqual(@as(i32, 0), app.seen[0].payload.motion.delta_y);

    try testing.expect(app.seen[1].position() == null);
    try testing.expectEqual(@as(i32, 5), app.seen[1].payload.motion.delta_x);
    try testing.expectEqual(@as(i32, -4), app.seen[1].payload.motion.delta_y);
}

test "an injected key is passed through when the hook is blocked" {
    try boot();

    var hook = Keyboard.init();
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    hook.set_blocked(true);

    var injected = press(.a);
    injected.injected = true;

    mock.loop.push_key(injected);
    mock.loop.push_key(press(.b));

    mock.loop.run();

    try testing.expectEqual(Response.pass, mock.loop.response_at(0));
    try testing.expectEqual(Response.consume, mock.loop.response_at(1));
}
