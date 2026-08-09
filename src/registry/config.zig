const std = @import("std");

const modifier = @import("../modifier.zig");
const pattern_mod = @import("../builder/pattern.zig");

const assert = std.debug.assert;

pub const RepeatConfig = struct {
    interval_ms: u32 = 100,
    initial_delay_ms: u32 = 0,

    pub fn interval(ms: u32) RepeatConfig {
        return .{ .interval_ms = ms };
    }

    pub fn with_delay(config: RepeatConfig, ms: u32) RepeatConfig {
        var result = config;
        result.initial_delay_ms = ms;
        return result;
    }
};

pub const TimerConfig = struct {
    interval_ms: u32 = 1000,
    repeating: bool = true,

    pub fn every(ms: u32) TimerConfig {
        return .{ .interval_ms = ms, .repeating = true };
    }

    pub fn once(ms: u32) TimerConfig {
        return .{ .interval_ms = ms, .repeating = false };
    }

    pub fn after(ms: u32) TimerConfig {
        return once(ms);
    }
};

pub const ToggleConfig = struct {
    toggle_key: Keycode,
    toggle_modifiers: modifier.Set = .{},

    pub fn init(comptime pattern: []const u8) ToggleConfig {
        const parsed = comptime pattern_mod.parse(pattern);

        return .{
            .toggle_key = parsed.key,
            .toggle_modifiers = parsed.modifiers,
        };
    }

    pub fn key(k: Keycode) ToggleConfig {
        return .{ .toggle_key = k };
    }

    pub fn with_modifiers(config: ToggleConfig, mods: modifier.Set) ToggleConfig {
        var result = config;
        result.toggle_modifiers = mods;
        return result;
    }
};

pub const MacroConfig = struct {
    const steps_max = 64;

    const StepKind = enum { text, line, key, delay };

    const Step = struct {
        kind: StepKind,
        text: ?[]const u8 = null,
        key_code: Keycode = .silent,
        key_modifiers: modifier.Set = .{},
        delay_ms: u32 = 0,
    };

    name: []const u8,
    steps: [steps_max]Step = undefined,
    step_count: u32 = 0,

    pub fn init(name: []const u8) MacroConfig {
        return .{ .name = name };
    }

    pub fn text(config: MacroConfig, txt: []const u8) MacroConfig {
        assert(config.step_count < steps_max);

        var result = config;

        result.steps[result.step_count] = .{
            .kind = .text,
            .text = txt,
        };

        result.step_count += 1;

        assert(result.step_count <= steps_max);

        return result;
    }

    pub fn line(config: MacroConfig, txt: []const u8) MacroConfig {
        assert(config.step_count < steps_max);

        var result = config;

        result.steps[result.step_count] = .{
            .kind = .line,
            .text = txt,
        };

        result.step_count += 1;

        assert(result.step_count <= steps_max);

        return result;
    }

    pub fn key(config: MacroConfig, comptime pattern: []const u8) MacroConfig {
        assert(config.step_count < steps_max);

        const parsed = comptime pattern_mod.parse(pattern);
        var result = config;

        result.steps[result.step_count] = .{
            .kind = .key,
            .key_code = parsed.key,
            .key_modifiers = parsed.modifiers,
        };

        result.step_count += 1;

        assert(result.step_count <= steps_max);

        return result;
    }

    pub fn delay(config: MacroConfig, ms: u32) MacroConfig {
        assert(config.step_count < steps_max);

        var result = config;

        result.steps[result.step_count] = .{
            .kind = .delay,
            .delay_ms = ms,
        };

        result.step_count += 1;

        assert(result.step_count <= steps_max);

        return result;
    }
};

const keycode = @import("../keycode.zig");

const Keycode = keycode.Keycode;

const testing = std.testing;

test "a repeat config starts at its defaults" {
    const cfg = RepeatConfig{};

    try testing.expectEqual(@as(u32, 100), cfg.interval_ms);
    try testing.expectEqual(@as(u32, 0), cfg.initial_delay_ms);
}

test "a repeat config carries its interval" {
    const cfg = RepeatConfig.interval(50);

    try testing.expectEqual(@as(u32, 50), cfg.interval_ms);
    try testing.expectEqual(@as(u32, 0), cfg.initial_delay_ms);
}

test "a repeat config carries its delay" {
    const cfg = RepeatConfig.interval(100).with_delay(200);

    try testing.expectEqual(@as(u32, 100), cfg.interval_ms);
    try testing.expectEqual(@as(u32, 200), cfg.initial_delay_ms);
}

test "a repeat config keeps every chained value" {
    const cfg = RepeatConfig.interval(75).with_delay(150);

    try testing.expectEqual(@as(u32, 75), cfg.interval_ms);
    try testing.expectEqual(@as(u32, 150), cfg.initial_delay_ms);
}

test "a timer config starts at its defaults" {
    const cfg = TimerConfig{};

    try testing.expectEqual(@as(u32, 1000), cfg.interval_ms);
    try testing.expect(cfg.repeating);
}

test "a recurring timer config carries its interval" {
    const cfg = TimerConfig.every(500);

    try testing.expectEqual(@as(u32, 500), cfg.interval_ms);
    try testing.expect(cfg.repeating);
}

test "a one shot timer config fires a single time" {
    const cfg = TimerConfig.once(2000);

    try testing.expectEqual(@as(u32, 2000), cfg.interval_ms);
    try testing.expect(!cfg.repeating);
}

test "a delayed timer config carries its delay" {
    const cfg = TimerConfig.after(3000);

    try testing.expectEqual(@as(u32, 3000), cfg.interval_ms);
    try testing.expect(!cfg.repeating);
}

test "a toggle config carries the binding it was built from" {
    const cfg = comptime ToggleConfig.init("Ctrl+T");

    try testing.expectEqual(.t, cfg.toggle_key);
    try testing.expect(cfg.toggle_modifiers.ctrl());
    try testing.expect(!cfg.toggle_modifiers.alt());
}

test "a toggle config can be built from a bare key" {
    const cfg = comptime ToggleConfig.init("F5");

    try testing.expectEqual(Keycode.f5, cfg.toggle_key);
    try testing.expect(cfg.toggle_modifiers.none());
}

test "a toggle config carries its key" {
    const cfg = ToggleConfig.key(.x);

    try testing.expectEqual(.x, cfg.toggle_key);
    try testing.expect(cfg.toggle_modifiers.none());
}

test "a toggle config carries its modifiers" {
    const mods = modifier.Set.from(.{ .alt = true, .shift = true });
    const cfg = ToggleConfig.key(.y).with_modifiers(mods);

    try testing.expectEqual(.y, cfg.toggle_key);
    try testing.expect(cfg.toggle_modifiers.alt());
    try testing.expect(cfg.toggle_modifiers.shift());
}

test "a macro config starts empty" {
    const cfg = MacroConfig.init("test_macro");

    try testing.expectEqualStrings("test_macro", cfg.name);
    try testing.expectEqual(@as(u32, 0), cfg.step_count);
}

test "a macro config records a text action" {
    const cfg = MacroConfig.init("m").text("hello");

    try testing.expectEqual(@as(u32, 1), cfg.step_count);
    try testing.expectEqualStrings("hello", cfg.steps[0].text.?);
}

test "a macro config records a line action" {
    const cfg = MacroConfig.init("m").line("world");

    try testing.expectEqual(@as(u32, 1), cfg.step_count);
    try testing.expectEqualStrings("world", cfg.steps[0].text.?);
}

test "a macro config records a key action" {
    const cfg = comptime MacroConfig.init("m").key("Ctrl+S");

    try testing.expectEqual(@as(u32, 1), cfg.step_count);
    try testing.expectEqual(.s, cfg.steps[0].key_code);
    try testing.expect(cfg.steps[0].key_modifiers.ctrl());
}

test "a macro config records a delay action" {
    const cfg = MacroConfig.init("m").delay(500);

    try testing.expectEqual(@as(u32, 1), cfg.step_count);
    try testing.expectEqual(@as(u32, 500), cfg.steps[0].delay_ms);
}

test "a macro config keeps every chained action" {
    const cfg = comptime MacroConfig.init("complex")
        .text("start")
        .delay(100)
        .key("Enter")
        .line("end");

    try testing.expectEqual(@as(u32, 4), cfg.step_count);
    try testing.expectEqualStrings("start", cfg.steps[0].text.?);
    try testing.expectEqual(@as(u32, 100), cfg.steps[1].delay_ms);
    try testing.expectEqual(Keycode.enter, cfg.steps[2].key_code);
    try testing.expectEqualStrings("end", cfg.steps[3].text.?);
}

test "a macro config keeps several text actions" {
    const cfg = MacroConfig.init("m")
        .text("one")
        .text("two")
        .text("three");

    try testing.expectEqual(@as(u32, 3), cfg.step_count);
    try testing.expectEqualStrings("one", cfg.steps[0].text.?);
    try testing.expectEqualStrings("two", cfg.steps[1].text.?);
    try testing.expectEqualStrings("three", cfg.steps[2].text.?);
}

test "a macro config keeps several key actions" {
    const cfg = comptime MacroConfig.init("m")
        .key("Ctrl+A")
        .key("Ctrl+C")
        .key("Ctrl+V");

    try testing.expectEqual(@as(u32, 3), cfg.step_count);
    try testing.expectEqual(.a, cfg.steps[0].key_code);
    try testing.expectEqual(.c, cfg.steps[1].key_code);
    try testing.expectEqual(.v, cfg.steps[2].key_code);
}

test "a macro config preserves its name" {
    const cfg = MacroConfig.init("my_macro")
        .text("test")
        .delay(50);

    try testing.expectEqualStrings("my_macro", cfg.name);
}
