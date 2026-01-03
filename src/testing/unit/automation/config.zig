const std = @import("std");
const input = @import("input");

const config = input.automation.config;
const keycode = input.keycode;
const modifier = input.modifier;

const RepeatConfig = config.RepeatConfig;
const TimerConfig = config.TimerConfig;
const ToggleConfig = config.ToggleConfig;
const MacroConfig = config.MacroConfig;

const testing = std.testing;

test "RepeatConfig default" {
    const cfg = RepeatConfig{};

    try testing.expectEqual(@as(u32, 100), cfg.interval_ms);
    try testing.expectEqual(@as(u32, 0), cfg.initial_delay_ms);
}

test "RepeatConfig.interval" {
    const cfg = RepeatConfig.interval(50);

    try testing.expectEqual(@as(u32, 50), cfg.interval_ms);
    try testing.expectEqual(@as(u32, 0), cfg.initial_delay_ms);
}

test "RepeatConfig.with_delay" {
    const cfg = RepeatConfig.interval(100).with_delay(200);

    try testing.expectEqual(@as(u32, 100), cfg.interval_ms);
    try testing.expectEqual(@as(u32, 200), cfg.initial_delay_ms);
}

test "RepeatConfig chained" {
    const cfg = RepeatConfig.interval(75).with_delay(150);

    try testing.expectEqual(@as(u32, 75), cfg.interval_ms);
    try testing.expectEqual(@as(u32, 150), cfg.initial_delay_ms);
}

test "TimerConfig default" {
    const cfg = TimerConfig{};

    try testing.expectEqual(@as(u32, 1000), cfg.interval_ms);
    try testing.expect(cfg.repeating);
}

test "TimerConfig.every" {
    const cfg = TimerConfig.every(500);

    try testing.expectEqual(@as(u32, 500), cfg.interval_ms);
    try testing.expect(cfg.repeating);
}

test "TimerConfig.once" {
    const cfg = TimerConfig.once(2000);

    try testing.expectEqual(@as(u32, 2000), cfg.interval_ms);
    try testing.expect(!cfg.repeating);
}

test "TimerConfig.after" {
    const cfg = TimerConfig.after(3000);

    try testing.expectEqual(@as(u32, 3000), cfg.interval_ms);
    try testing.expect(!cfg.repeating);
}

test "ToggleConfig.init" {
    const cfg = comptime ToggleConfig.init("Ctrl+T");

    try testing.expectEqual(@as(u8, 'T'), cfg.toggle_key);
    try testing.expect(cfg.toggle_modifiers.ctrl());
    try testing.expect(!cfg.toggle_modifiers.alt());
}

test "ToggleConfig.init simple key" {
    const cfg = comptime ToggleConfig.init("F5");

    try testing.expectEqual(keycode.f5, cfg.toggle_key);
    try testing.expect(cfg.toggle_modifiers.none());
}

test "ToggleConfig.key" {
    const cfg = ToggleConfig.key('X');

    try testing.expectEqual(@as(u8, 'X'), cfg.toggle_key);
    try testing.expect(cfg.toggle_modifiers.none());
}

test "ToggleConfig.with_modifiers" {
    const mods = modifier.Set.from(.{ .alt = true, .shift = true });
    const cfg = ToggleConfig.key('Y').with_modifiers(mods);

    try testing.expectEqual(@as(u8, 'Y'), cfg.toggle_key);
    try testing.expect(cfg.toggle_modifiers.alt());
    try testing.expect(cfg.toggle_modifiers.shift());
}

test "MacroConfig.init" {
    const cfg = MacroConfig.init("test_macro");

    try testing.expectEqualStrings("test_macro", cfg.name);
    try testing.expectEqual(@as(u32, 0), cfg.step_count);
}

test "MacroConfig.text" {
    const cfg = MacroConfig.init("m").text("hello");

    try testing.expectEqual(@as(u32, 1), cfg.step_count);
    try testing.expectEqualStrings("hello", cfg.steps[0].text.?);
}

test "MacroConfig.line" {
    const cfg = MacroConfig.init("m").line("world");

    try testing.expectEqual(@as(u32, 1), cfg.step_count);
    try testing.expectEqualStrings("world", cfg.steps[0].text.?);
}

test "MacroConfig.key" {
    const cfg = comptime MacroConfig.init("m").key("Ctrl+S");

    try testing.expectEqual(@as(u32, 1), cfg.step_count);
    try testing.expectEqual(@as(u8, 'S'), cfg.steps[0].key_code);
    try testing.expect(cfg.steps[0].key_modifiers.ctrl());
}

test "MacroConfig.delay" {
    const cfg = MacroConfig.init("m").delay(500);

    try testing.expectEqual(@as(u32, 1), cfg.step_count);
    try testing.expectEqual(@as(u32, 500), cfg.steps[0].delay_ms);
}

test "MacroConfig chained" {
    const cfg = comptime MacroConfig.init("complex")
        .text("start")
        .delay(100)
        .key("Enter")
        .line("end");

    try testing.expectEqual(@as(u32, 4), cfg.step_count);
    try testing.expectEqualStrings("start", cfg.steps[0].text.?);
    try testing.expectEqual(@as(u32, 100), cfg.steps[1].delay_ms);
    try testing.expectEqual(keycode.@"return", cfg.steps[2].key_code);
    try testing.expectEqualStrings("end", cfg.steps[3].text.?);
}

test "MacroConfig multiple text" {
    const cfg = MacroConfig.init("m")
        .text("one")
        .text("two")
        .text("three");

    try testing.expectEqual(@as(u32, 3), cfg.step_count);
    try testing.expectEqualStrings("one", cfg.steps[0].text.?);
    try testing.expectEqualStrings("two", cfg.steps[1].text.?);
    try testing.expectEqualStrings("three", cfg.steps[2].text.?);
}

test "MacroConfig multiple keys" {
    const cfg = comptime MacroConfig.init("m")
        .key("Ctrl+A")
        .key("Ctrl+C")
        .key("Ctrl+V");

    try testing.expectEqual(@as(u32, 3), cfg.step_count);
    try testing.expectEqual(@as(u8, 'A'), cfg.steps[0].key_code);
    try testing.expectEqual(@as(u8, 'C'), cfg.steps[1].key_code);
    try testing.expectEqual(@as(u8, 'V'), cfg.steps[2].key_code);
}

test "MacroConfig preserves name" {
    const cfg = MacroConfig.init("my_macro")
        .text("test")
        .delay(50);

    try testing.expectEqualStrings("my_macro", cfg.name);
}
