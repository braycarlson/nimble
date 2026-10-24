const std = @import("std");

const key_event = @import("event/key.zig");
const keycode = @import("keycode.zig");
const modifier = @import("modifier.zig");
const mouse_event = @import("event/mouse.zig");
const nimble = @import("root.zig");
const platform = @import("platform.zig");
const response_mod = @import("response.zig");
const runtime = @import("runtime.zig");

const Key = key_event.Key;
const Keycode = keycode.Keycode;
const MouseEvent = mouse_event.MouseEvent;
const Response = response_mod.Response;
const mock = platform.backend;
const testing = std.testing;

test {
    _ = @import("builder/keyboard.zig");
    _ = @import("clipboard.zig");
    _ = @import("filter/window.zig");
    _ = @import("keyboard.zig");
    _ = @import("loop.zig");
    _ = @import("mouse.zig");
    _ = @import("pipeline_fuzz.zig");
    _ = @import("platform/mock.zig");
    _ = @import("platform/mock/clipboard.zig");
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
    _ = @import("platform/mock/time.zig");
    _ = @import("platform/mock/timer.zig");
    _ = @import("platform/mock/window.zig");
    _ = @import("remote.zig");
    _ = @import("root.zig");
    _ = @import("runtime.zig");
    _ = @import("simulate/key.zig");
    _ = @import("simulate/mouse.zig");
    _ = @import("simulate/text.zig");
    _ = @import("time.zig");
}

const Keyboard = nimble.KeyboardType(.{
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

const Mouse = nimble.MouseType(.{ .binding_count_max = 8 });
const wait_attempt_max: u32 = 1_000_000;

fn boot() !void {
    mock.reset();

    try nimble.runtime.open(.{ .mode = .grab });
}

fn keyboard_open(storage: *Keyboard) !*Keyboard {
    try storage.init(.{});

    return storage;
}

fn mouse_open(storage: *Mouse) *Mouse {
    storage.init(.{});

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

fn push_chord(value: Keycode) void {
    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(value));
    mock.loop.push_key(release(value));
    mock.loop.push_key(release(.control_left));
}

test "pipeline: a bound chord consumes the trigger and runs the callback" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

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

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.b));
    mock.loop.run();

    try testing.expectEqual(@as(u32, 0), app.hits);
    try testing.expectEqual(Response.pass, mock.loop.response_at(0));
}

test "pipeline: a modifier alone never fires the binding" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

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

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key_pass);

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.a));

    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.pass, mock.loop.response_at(1));
}

test "pipeline: a binding built at runtime matches its pattern twin" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind_key(.a, .from(.{ .ctrl = true })).on(Counter, &app, Counter.on_key);

    const duplicate = hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

    try testing.expectError(error.BindingDuplicate, duplicate);
}

test "pipeline: an unbound handle stops firing and cannot be unbound twice" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    const handle = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    try hook.unbind(handle);
    try testing.expectError(error.HandleUnknown, hook.unbind(handle));

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.a));
    mock.loop.run();

    try testing.expectEqual(@as(u32, 0), app.hits);
    try testing.expectEqual(Response.pass, mock.loop.response_at(1));
}

test "pipeline: synthesis from a callback is recorded" {
    try boot();

    try testing.expect(nimble.simulate.key.press(.f5));
    try testing.expect(mock.record.contains(.key_press, .f5));
    try testing.expectEqual(@as(u16, 1), mock.record.count_of(.key_press));
}

test "pipeline: a sequence fires only on the full pattern" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    const handle = try hook.sequence("AB").on(Counter, &app, Counter.on_void);

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.a));
    mock.loop.run();

    try testing.expectEqual(@as(u32, 0), app.hits);

    mock.loop.push_key(press(.b));
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);

    try hook.unbind_sequence(handle);

    mock.loop.push_key(press(.a));
    mock.loop.push_key(press(.b));
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "pipeline: blocking consumes everything except injected events" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    hook.block();

    mock.loop.push_key(press(.a));
    mock.loop.run();

    try testing.expect(hook.is_blocked());
    try testing.expectEqual(Response.consume, mock.loop.response_at(0));

    hook.unblock();

    mock.loop.push_key(press(.b));
    mock.loop.run();

    try testing.expect(!hook.is_blocked());
    try testing.expectEqual(Response.pass, mock.loop.response_at(1));
}

test "pipeline: a block exempt binding fires once per press while blocked" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+U").block_exempt().on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    hook.block();

    push_chord(.u);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "pipeline: mouse bindings consume their kind" {
    try boot();

    var mouse: Mouse = undefined;
    const hook = mouse_open(&mouse);
    defer hook.deinit();

    var app = Counter{};

    const handle = try hook.bind(.left_down).on(Counter, &app, Counter.on_mouse);

    try hook.start();
    defer hook.stop();

    mock.loop.push_mouse(mouse_event_of(.left_down));
    mock.loop.push_mouse(mouse_event_of(.right_down));

    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.consume, mock.loop.response_at(0));
    try testing.expectEqual(Response.pass, mock.loop.response_at(1));

    try hook.unbind(handle);

    mock.loop.push_mouse(mouse_event_of(.left_down));
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "pipeline: a blocked mouse hook consumes every event" {
    try boot();

    var mouse: Mouse = undefined;
    const hook = mouse_open(&mouse);
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    hook.block();

    mock.loop.push_mouse(mouse_event_of(.move));
    mock.loop.run();

    try testing.expectEqual(Response.consume, mock.loop.response_at(0));
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
        count: u32 = 0,

        fn fire(context: *anyopaque) void {
            const tick: *@This() = @ptrCast(@alignCast(context));

            tick.count += 1;
        }
    };

    var tick = Tick{};

    const id = mock.timer.start(100, Tick.fire, &tick) orelse return error.TimerUnavailable;
    defer _ = mock.timer.stop(id);

    mock.loop.push_advance(100);
    mock.loop.push_advance(100);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 2), tick.count);
}

test "pipeline: a hook timer fires only between its start and its stop" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    const timer = try hook.timer(100).on(Counter, &app, Counter.on_void);

    try hook.start();
    defer hook.stop();

    mock.loop.push_advance(200);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 0), app.hits);

    try hook.start_timer(timer);
    try testing.expectError(error.TimerRunning, hook.start_timer(timer));

    mock.loop.push_advance(100);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);

    try hook.stop_timer(timer);

    mock.loop.push_advance(300);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectError(error.TimerStopped, hook.stop_timer(timer));
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

    try nimble.clipboard.set("nimble");

    const text = try mock.clipboard.get(&buffer);

    try testing.expectEqualStrings("nimble", text);
    try testing.expect(mock.record.count_of(.clipboard_set) == 1);
}

test "monitor enumeration reports the scripted desktop" {
    try boot();

    var list: nimble.Monitor.List = undefined;

    list.enumerate();

    try testing.expectEqual(@as(u8, 2), list.count);

    const primary = list.primary() orelse return error.MissingMonitor;

    try testing.expect(primary.primary);
    try testing.expectEqual(@as(i32, 1920), primary.width());
    try testing.expect(list.at(.{ .x = 2000, .y = 10 }) != null);
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

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    const handle = try hook.chord(&.{ .a, .b }).on(Counter, &app, Counter.on_chord);

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.a));
    mock.loop.push_key(press(.b));

    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);

    try hook.unbind_chord(handle);
    try testing.expectError(error.HandleUnknown, hook.unbind_chord(handle));
}

test "pipeline: a command fires on its trigger, name, and enter" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.command("hi").on(Counter, &app, Counter.on_command);

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

test "pipeline: the default command trigger is a shifted semicolon" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.command("hi").on(Counter, &app, Counter.on_command);

    try testing.expectEqual(@as(u8, ':'), hook.command_registry.trigger);

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.semicolon));
    mock.loop.push_key(press(.h));
    mock.loop.push_key(press(.i));
    mock.loop.push_key(press(.enter));
    mock.loop.push_key(press(.shift_left));
    mock.loop.push_key(press(.semicolon));
    mock.loop.push_key(release(.shift_left));
    mock.loop.push_key(press(.h));
    mock.loop.push_key(press(.i));
    mock.loop.push_key(press(.enter));

    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.pass, mock.loop.response_at(3));
    try testing.expectEqual(Response.consume, mock.loop.response_at(9));
}

test "pipeline: middleware observes every dispatched key" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};
    var tagger = Tagger{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);
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

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};
    var tagger = Tagger{ .swallow = true };

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

    const handle = try hook.add_middleware(Tagger, &tagger);

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.a));

    mock.loop.run();

    try testing.expect(tagger.seen >= 1);
    try testing.expectEqual(@as(u32, 0), app.hits);
    try testing.expectEqual(Response.consume, mock.loop.response_at(1));

    try hook.remove_middleware(handle);

    mock.loop.push_key(press(.a));
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "pipeline: a toggle switches its action on and off" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+T").toggle("Ctrl+Y").on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    push_chord(.t);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 0), app.hits);
    try testing.expectEqual(Response.pass, mock.loop.response_at(1));

    push_chord(.y);
    push_chord(.t);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.consume, mock.loop.response_at(5));
    try testing.expectEqual(Response.consume, mock.loop.response_at(9));

    push_chord(.y);
    push_chord(.t);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
}

test "pipeline: a oneshot fires on its first press only" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+O").once().on(Counter, &app, Counter.on_key);

    try hook.start();
    defer hook.stop();

    push_chord(.o);
    push_chord(.o);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), app.hits);
    try testing.expectEqual(Response.consume, mock.loop.response_at(1));
    try testing.expectEqual(Response.pass, mock.loop.response_at(5));
}

test "pipeline: a repeat runs while its key is held and stops on release" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var repeater = Repeater{};

    const handle = try hook.bind("Ctrl+R").repeat(20).on(Repeater, &repeater, Repeater.on_repeat);
    const id = @backingInt(handle);

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.r));
    mock.loop.run();

    try testing.expectEqual(Response.consume, mock.loop.response_at(1));
    try testing.expectEqual(true, hook.repeat_registry.is_running(id).?);

    var attempt: u32 = 0;

    while (attempt < wait_attempt_max) : (attempt += 1) {
        if (repeater.count.load(.seq_cst) >= 1) break;

        std.Thread.yield() catch break;
    }

    mock.loop.push_key(release(.r));
    mock.loop.run();

    try testing.expectEqual(false, hook.repeat_registry.is_running(id).?);
    try testing.expect(repeater.count.load(.seq_cst) >= 1);
}

test "pipeline: a macro bound to a key plays its steps" {
    try boot();

    mock.window.set_present(false);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    _ = try hook.macro("greet").text("hi").key("Enter").bind("Ctrl+G").create();

    try hook.start();
    defer hook.stop();

    push_chord(.g);
    mock.loop.run();

    try testing.expectEqual(Response.consume, mock.loop.response_at(1));

    var attempt: u32 = 0;

    while (attempt < wait_attempt_max) : (attempt += 1) {
        if (!hook.macro_registry.is_playing()) break;

        std.Thread.yield() catch break;
    }

    hook.macro_registry.stop();

    try testing.expect(mock.record.count_of(.text_send) >= 1);
    try testing.expect(mock.record.contains(.key_press, .enter));
}

test "pipeline: a macro plays again on the worker that init started" {
    try boot();

    mock.window.set_present(false);

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    _ = try hook.macro("greet").text("hi").bind("Ctrl+G").create();

    try hook.start();
    defer hook.stop();

    const worker = hook.macro_registry.worker orelse return error.TestWorkerMissing;
    var text_counts: [2]u32 = @splat(0);

    for (&text_counts) |*text_count| {
        push_chord(.g);
        mock.loop.run();

        var attempt: u32 = 0;

        while (attempt < wait_attempt_max) : (attempt += 1) {
            if (!hook.macro_registry.is_playing()) break;

            std.Thread.yield() catch break;
        }

        hook.macro_registry.stop();
        text_count.* = mock.record.count_of(.text_send);
    }

    const worker_after = hook.macro_registry.worker orelse return error.TestWorkerMissing;

    try testing.expect(text_counts[0] >= 1);
    try testing.expect(text_counts[1] > text_counts[0]);
    try testing.expectEqual(worker.getHandle(), worker_after.getHandle());
}

test "pipeline: a targeted macro line arrives as characters ending in a return" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    _ = try hook.macro("greet").line("h\u{e9}").bind("Ctrl+G").create();

    try hook.start();
    defer hook.stop();

    push_chord(.g);
    mock.loop.run();

    var attempt: u32 = 0;

    while (attempt < wait_attempt_max) : (attempt += 1) {
        if (!hook.macro_registry.is_playing()) break;

        std.Thread.yield() catch break;
    }

    hook.macro_registry.stop();

    var characters: [4]i32 = @splat(0);
    var character_count: u32 = 0;
    var index: u16 = 0;

    while (index < mock.record.len()) : (index += 1) {
        const entry = mock.record.at(index);
        if (entry.kind != .message_char) continue;

        try testing.expect(character_count < characters.len);

        characters[character_count] = entry.amount;
        character_count += 1;
    }

    try testing.expectEqualSlices(i32, &.{ 'h', 0xE9, '\r' }, characters[0..character_count]);
    try testing.expect(!mock.record.contains(.message_key, .enter));
}

test "pipeline: the recorded tape is replayable and deterministic" {
    try boot();

    var first: u16 = 0;

    {
        var keyboard: Keyboard = undefined;
        const hook = try keyboard_open(&keyboard);
        defer hook.deinit();

        var app = Counter{};

        _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

        try hook.start();
        defer hook.stop();

        mock.loop.push_key(press(.control_left));
        mock.loop.push_key(press(.a));
        mock.loop.run();

        first = mock.loop.response_len();
    }

    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

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

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind("Ctrl+A").on(Counter, &app, Counter.on_key);

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

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    hook.block();

    mock.loop.push_key(press(.a));
    mock.loop.run();

    try testing.expect(hook.is_blocked());
    try testing.expectEqual(Response.pass, mock.loop.response_at(0));
}

test "observe mode clamps mouse bindings down to pass" {
    mock.reset();

    try nimble.runtime.open(.{ .mode = .observe });
    defer nimble.runtime.close();

    var mouse: Mouse = undefined;
    const hook = mouse_open(&mouse);
    defer hook.deinit();

    var app = Counter{};

    _ = try hook.bind(.left_down).on(Counter, &app, Counter.on_mouse);

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
    try testing.expectEqual(nimble.runtime.Mode.grab, nimble.runtime.mode());
    try testing.expect(!runtime.observes());

    nimble.runtime.close();

    try testing.expect(!nimble.runtime.is_open());
    try testing.expect(runtime.observes());
    try testing.expectEqual(@as(u16, 1), mock.runtime.opens());
    try testing.expectEqual(@as(u16, 1), mock.runtime.closes());
}

test "a second hook of one kind is a request error" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    var second: nimble.KeyboardType(.{}) = undefined;

    try second.init(.{});
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
    try boot();

    var mouse: Mouse = undefined;
    const hook = mouse_open(&mouse);
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.wheel).on(Recorder, &app, Recorder.on_mouse);

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

    var mouse: Mouse = undefined;
    const hook = mouse_open(&mouse);
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

    var mouse: Mouse = undefined;
    const hook = mouse_open(&mouse);
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.move).on(Recorder, &app, Recorder.on_mouse);

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

    var mouse: Mouse = undefined;
    const hook = mouse_open(&mouse);
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.x_down).on(Recorder, &app, Recorder.on_mouse);

    try hook.start();
    defer hook.stop();

    mock.loop.push_mouse(MouseEvent.from_button(.{ .button = .x2, .down = true }, .{}));
    mock.loop.run();

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
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    var app = Observer{};

    hook.set_key_callback(Observer, &app, Observer.on_key);

    try hook.start();
    defer hook.stop();

    mock.loop.push_key(press(.control_left));
    mock.loop.push_key(press(.a));

    mock.loop.run();

    try testing.expectEqual(@as(u8, 2), app.count);
    try testing.expectEqual(Keycode.a, app.seen[1].value);
    try testing.expect(app.seen[1].modifiers.ctrl());
    try testing.expect(app.seen[1].modifiers.flags != modifier.flag_none);

    hook.clear_key_callback();

    mock.loop.push_key(press(.b));
    mock.loop.run();

    try testing.expectEqual(@as(u8, 2), app.count);
}

test "a Windows shaped and a Linux shaped motion keep their own payloads" {
    try boot();

    var mouse: Mouse = undefined;
    const hook = mouse_open(&mouse);
    defer hook.deinit();

    var app = Recorder{};

    _ = try hook.bind(.move).on(Recorder, &app, Recorder.on_mouse);

    try hook.start();
    defer hook.stop();

    const windows_shaped = MouseEvent.from_motion(.{
        .position = .{ .x = 11, .y = 22 },
    }, .{});

    const linux_shaped = MouseEvent.from_motion(.{ .delta_x = 5, .delta_y = -4 }, .{});

    mock.loop.push_mouse(windows_shaped);
    mock.loop.push_mouse(linux_shaped);

    mock.loop.run();

    try testing.expectEqual(@as(u8, 2), app.count);

    try testing.expect(app.seen[0].position().?.eql(.{ .x = 11, .y = 22 }));
    try testing.expectEqual(@as(i32, 0), app.seen[0].payload.motion.delta_x);
    try testing.expectEqual(@as(i32, 0), app.seen[0].payload.motion.delta_y);

    try testing.expect(app.seen[1].position() == null);
    try testing.expectEqual(@as(i32, 5), app.seen[1].payload.motion.delta_x);
    try testing.expectEqual(@as(i32, -4), app.seen[1].payload.motion.delta_y);
}

test "an injected key is passed through when the hook is blocked" {
    try boot();

    var keyboard: Keyboard = undefined;
    const hook = try keyboard_open(&keyboard);
    defer hook.deinit();

    try hook.start();
    defer hook.stop();

    hook.block();

    var injected = press(.a);

    injected.injected = true;

    mock.loop.push_key(injected);
    mock.loop.push_key(press(.b));

    mock.loop.run();

    try testing.expectEqual(Response.pass, mock.loop.response_at(0));
    try testing.expectEqual(Response.consume, mock.loop.response_at(1));
}
