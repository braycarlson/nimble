const std = @import("std");
const assert = std.debug.assert;

const simulator = @import("simulator.zig");
const recorder_mod = @import("recorder.zig");

const StressEvent = simulator.StressEvent;
const StressEventKind = simulator.StressEventKind;
const StressState = simulator.StressState;
const Recording = recorder_mod.Recording;

const max_ticks: u64 = 10_000_000;
const max_events_per_tick: u32 = 1000;

pub const ReplayState = struct {
    tick: u64 = 0,
    cpu_load: u8 = 0,
    in_stall: bool = false,
    has_focus: bool = true,
    queue_depth: u32 = 0,
    coalesced_inputs: u64 = 0,
    modifier_races: u64 = 0,
    timing_misses: u64 = 0,
};

pub const ReplayCallback = *const fn (replayer: *Replayer, tick: u64, event: ?*const StressEvent) void;

pub const Replayer = struct {
    recording: ?*const Recording,
    current_tick: u64,
    current_event_index: usize,
    state: ReplayState,
    callback: ?ReplayCallback,
    callback_context: ?*anyopaque,

    pub fn init() Replayer {
        return .{
            .recording = null,
            .current_tick = 0,
            .current_event_index = 0,
            .state = .{},
            .callback = null,
            .callback_context = null,
        };
    }

    pub fn deinit(self: *Replayer) void {
        _ = self;
    }

    pub fn load_recording(self: *Replayer, recording: *const Recording) void {
        assert(recording.config.max_ticks > 0);
        assert(recording.config.max_ticks <= max_ticks);

        self.recording = recording;
        self.reset();

        assert(self.current_tick == 0);
        assert(self.current_event_index == 0);
    }

    pub fn set_callback(self: *Replayer, callback: ReplayCallback, context: ?*anyopaque) void {
        self.callback = callback;
        self.callback_context = context;
    }

    pub fn reset(self: *Replayer) void {
        self.current_tick = 0;
        self.current_event_index = 0;
        self.state = .{};

        assert(self.state.tick == 0);
        assert(self.state.cpu_load == 0);
    }

    pub fn step(self: *Replayer) bool {
        const recording = self.recording orelse return false;

        assert(self.current_tick <= recording.config.max_ticks);
        assert(self.current_event_index <= recording.events.len);

        if (self.current_tick >= recording.config.max_ticks) {
            return false;
        }

        var events_processed: u32 = 0;
        while (self.current_event_index < recording.events.len) {
            if (events_processed >= max_events_per_tick) {
                break;
            }

            const event = &recording.events[self.current_event_index];
            if (event.tick > self.current_tick) {
                break;
            }

            self.apply_event(event);

            if (self.callback) |cb| {
                cb(self, self.current_tick, event);
            }

            self.current_event_index += 1;
            events_processed += 1;
        }

        self.state.tick = self.current_tick;
        self.current_tick += 1;

        assert(self.state.tick < self.current_tick);
        return true;
    }

    pub fn step_to(self: *Replayer, target_tick: u64) void {
        assert(target_tick <= max_ticks);

        const recording = self.recording orelse return;
        const bounded_target = @min(target_tick, recording.config.max_ticks);

        var iterations: u64 = 0;
        const max_iterations = bounded_target -| self.current_tick + 1;

        while (self.current_tick < bounded_target) {
            if (iterations >= max_iterations) {
                break;
            }
            if (!self.step()) {
                break;
            }
            iterations += 1;
        }

        assert(self.current_tick <= bounded_target or iterations >= max_iterations);
    }

    pub fn run(self: *Replayer) void {
        const recording = self.recording orelse return;

        assert(recording.config.max_ticks <= max_ticks);

        var iterations: u64 = 0;
        while (self.current_tick < recording.config.max_ticks) {
            if (iterations >= recording.config.max_ticks) {
                break;
            }
            if (!self.step()) {
                break;
            }
            iterations += 1;
        }

        assert(iterations <= recording.config.max_ticks);
    }

    pub fn get_state(self: *const Replayer) ReplayState {
        return self.state;
    }

    fn apply_event(self: *Replayer, event: *const StressEvent) void {
        assert(event.tick <= self.current_tick);

        switch (event.kind) {
            .cpu_spike => {
                self.state.cpu_load = event.data.cpu_load;
            },
            .cpu_normal => {
                self.state.cpu_load = 0;
            },
            .system_stall => {
                self.state.in_stall = true;
            },
            .hook_lost => {
                self.state.has_focus = false;
            },
            .hook_restored => {
                self.state.has_focus = true;
                self.state.in_stall = false;
            },
            .queue_backpressure => {
                self.state.queue_depth = event.data.queue_depth;
            },
            .input_coalesced => {
                self.state.coalesced_inputs += 1;
            },
            .modifier_race => {
                self.state.modifier_races += 1;
            },
            .timing_window_miss => {
                self.state.timing_misses += 1;
            },
            else => {},
        }
    }
};

const testing = std.testing;

test "Replayer init" {
    var replayer = Replayer.init();
    defer replayer.deinit();

    try testing.expectEqual(@as(u64, 0), replayer.current_tick);
}

test "Replayer reset" {
    var replayer = Replayer.init();
    defer replayer.deinit();

    replayer.current_tick = 100;
    replayer.state.timing_misses = 5;

    replayer.reset();

    try testing.expectEqual(@as(u64, 0), replayer.current_tick);
    try testing.expectEqual(@as(u64, 0), replayer.state.timing_misses);
}
