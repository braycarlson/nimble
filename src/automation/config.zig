const modifier = @import("../modifier.zig");
const pattern_mod = @import("../builder/pattern.zig");

pub const RepeatConfig = struct {
    interval_ms: u32 = 100,
    initial_delay_ms: u32 = 0,

    pub fn interval(ms: u32) RepeatConfig {
        return .{ .interval_ms = ms };
    }

    pub fn with_delay(self: RepeatConfig, ms: u32) RepeatConfig {
        var result = self;
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
    toggle_key: u8,
    toggle_modifiers: modifier.Set = .{},

    pub fn init(comptime pattern: []const u8) ToggleConfig {
        const parsed = comptime pattern_mod.parse(pattern);
        return .{
            .toggle_key = parsed.key,
            .toggle_modifiers = parsed.modifiers,
        };
    }

    pub fn key(k: u8) ToggleConfig {
        return .{ .toggle_key = k };
    }

    pub fn with_modifiers(self: ToggleConfig, mods: modifier.Set) ToggleConfig {
        var result = self;
        result.toggle_modifiers = mods;
        return result;
    }
};

pub const MacroConfig = struct {
    const MaxSteps = 64;

    const StepKind = enum { text, line, key, delay };

    const Step = struct {
        kind: StepKind,
        text: ?[]const u8 = null,
        key_code: u8 = 0,
        key_modifiers: modifier.Set = .{},
        delay_ms: u32 = 0,
    };

    name: []const u8,
    steps: [MaxSteps]Step = undefined,
    step_count: u32 = 0,

    pub fn init(name: []const u8) MacroConfig {
        return .{ .name = name };
    }

    pub fn text(self: MacroConfig, txt: []const u8) MacroConfig {
        var result = self;

        if (result.step_count < MaxSteps) {
            result.steps[result.step_count] = .{
                .kind = .text,
                .text = txt,
            };

            result.step_count += 1;
        }

        return result;
    }

    pub fn line(self: MacroConfig, txt: []const u8) MacroConfig {
        var result = self;

        if (result.step_count < MaxSteps) {
            result.steps[result.step_count] = .{
                .kind = .line,
                .text = txt,
            };

            result.step_count += 1;
        }

        return result;
    }

    pub fn key(self: MacroConfig, comptime pattern: []const u8) MacroConfig {
        const parsed = comptime pattern_mod.parse(pattern);
        var result = self;

        if (result.step_count < MaxSteps) {
            result.steps[result.step_count] = .{
                .kind = .key,
                .key_code = parsed.key,
                .key_modifiers = parsed.modifiers,
            };

            result.step_count += 1;
        }

        return result;
    }

    pub fn delay(self: MacroConfig, ms: u32) MacroConfig {
        var result = self;

        if (result.step_count < MaxSteps) {
            result.steps[result.step_count] = .{
                .kind = .delay,
                .delay_ms = ms,
            };

            result.step_count += 1;
        }

        return result;
    }
};
