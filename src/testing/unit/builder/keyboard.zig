const std = @import("std");
const input = @import("input");

const key_event = input.event.key;
const keyboard = input.keyboard;
const modifier = input.modifier;
const response = input.response;

const Key = key_event.Key;
const MacroConfig = input.MacroConfig;
const Response = response.Response;

const testing = std.testing;

const Hook = keyboard.KeyboardHook(.{
    .capacity_repeat = 1,
    .capacity_macro = 4,
});

const Ctx = struct {
    hits: u32 = 0,

    fn on_key(self: *Ctx, _: *const Key) Response {
        self.hits += 1;

        return .pass;
    }

    fn on_repeat(self: *Ctx, _: u32) void {
        self.hits += 1;
    }

    fn on_timer(self: *Ctx) void {
        self.hits += 1;
    }
};

fn make_key(value: u8, mods: modifier.Set) Key {
    return Key{
        .value = value,
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = mods,
    };
}

test "RepeatChainBuilder.on registers binding and repeat" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};
    const repeat_id = try hook.bind("Ctrl+A").repeat(100).on(&ctx, Ctx.on_repeat);

    try testing.expect(repeat_id >= 1);

    const key = make_key('A', modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) != null);
}

test "RepeatChainBuilder.on rolls back binding on repeat failure" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};

    _ = try hook.bind("Ctrl+A").repeat(100).on(&ctx, Ctx.on_repeat);

    const result = hook.bind("Ctrl+B").repeat(100).on(&ctx, Ctx.on_repeat);

    try testing.expectError(error.RegistryFull, result);

    const key = make_key('B', modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) == null);
}

test "TimerChainBuilder.on registers binding and timer" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};
    const timer_id = try hook.bind("Ctrl+C").timer(1000).on(&ctx, Ctx.on_timer);

    try testing.expect(timer_id >= 1);

    const key = make_key('C', modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) != null);
}

test "ToggleChainBuilder.on registers both bindings" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};
    const toggle_id = try hook.bind("Ctrl+D").toggle("Ctrl+T").on(&ctx, Ctx.on_key);

    try testing.expect(toggle_id >= 1);

    const action_key = make_key('D', modifier.Set.from(.{ .ctrl = true }));
    const toggle_key = make_key('T', modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&action_key) != null);
    try testing.expect(hook.registry.find(&toggle_key) != null);
}

test "MacroChainBuilder.on registers macro and binding" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};

    const cfg = MacroConfig.init("chain_macro").text("hello");
    const macro_id = try hook.bind("Ctrl+E").macro(cfg).on(&ctx, Ctx.on_key);

    try testing.expect(macro_id >= 1);
    try testing.expect(hook.macro_registry.find_by_name("chain_macro") != null);

    const key = make_key('E', modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) != null);
}

test "MacroChainBuilder.on rolls back macro on binding failure" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};

    _ = try hook.bind("Ctrl+F").on(&ctx, Ctx.on_key);

    const cfg = MacroConfig.init("orphan_macro").text("hello");
    const result = hook.bind("Ctrl+F").macro(cfg).on(&ctx, Ctx.on_key);

    try testing.expectError(error.AlreadyRegistered, result);
    try testing.expect(hook.macro_registry.find_by_name("orphan_macro") == null);
}

test "MacroBuilder.create wires play binding" {
    var hook = Hook.init();
    defer hook.deinit();

    const macro_id = try hook.macro_builder("play_macro")
        .text("hello")
        .bind("Ctrl+G")
        .create();

    try testing.expect(macro_id >= 1);
    try testing.expect(hook.macro_registry.find_by_name("play_macro") != null);

    const key = make_key('G', modifier.Set.from(.{ .ctrl = true }));
    const entry = hook.registry.find(&key);

    try testing.expect(entry != null);
}

test "MacroBuilder.create rolls back macro on binding failure" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};

    _ = try hook.bind("Ctrl+H").on(&ctx, Ctx.on_key);

    const result = hook.macro_builder("rollback_macro")
        .text("hello")
        .bind("Ctrl+H")
        .create();

    try testing.expectError(error.AlreadyRegistered, result);
    try testing.expect(hook.macro_registry.find_by_name("rollback_macro") == null);
}

test "MacroBuilder.on registers macro and callback binding" {
    var hook = Hook.init();
    defer hook.deinit();

    var ctx = Ctx{};

    const macro_id = try hook.macro_builder("callback_macro")
        .text("hello")
        .bind("Ctrl+I")
        .on(&ctx, Ctx.on_key);

    try testing.expect(macro_id >= 1);

    const key = make_key('I', modifier.Set.from(.{ .ctrl = true }));

    try testing.expect(hook.registry.find(&key) != null);
}
