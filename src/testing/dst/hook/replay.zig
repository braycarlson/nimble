const std = @import("std");

const simulator = @import("simulator.zig");
const recorder_mod = @import("recorder.zig");

const HookEvent = simulator.Event;
const State = simulator.State;
const Health = simulator.Health;
const RecordedEvent = simulator.RecordedEvent;
const Recording = recorder_mod.Recording;

pub const iteration_max: u64 = 0xFFFFFFFF;
pub const tick_max: u64 = 0xFFFFFFFF;

pub const ReplayState = struct {
    tick: u64 = 0,
    hook_state: State = .installed,
    health: Health = .healthy,
    session_locked: bool = false,
    in_uac: bool = false,
    in_sleep: bool = false,
    desktop_secure: bool = false,
    callbacks_so_far: u64 = 0,
    timeouts_so_far: u64 = 0,
    inputs_lost_so_far: u64 = 0,
    reinstalls_so_far: u64 = 0,

    pub fn is_valid(self: *const ReplayState) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_state = self.hook_state.is_valid();
        const valid_health = self.health.is_valid();
        const result = valid_state and valid_health;

        return result;
    }
};

pub const ReplayCallback = *const fn (replayer: *Replayer, tick: u64, event: ?*const RecordedEvent) void;

pub const Replayer = struct {
    recording: ?*const Recording,
    current_tick: u64,
    current_event_index: usize,
    state: ReplayState,
    callback: ?ReplayCallback,
    callback_context: ?*anyopaque,

    pub fn init() Replayer {
        const result = Replayer{
            .recording = null,
            .current_tick = 0,
            .current_event_index = 0,
            .state = .{},
            .callback = null,
            .callback_context = null,
        };

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn is_valid(self: *const Replayer) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_state = self.state.is_valid();
        const valid_tick = self.current_tick <= tick_max;
        const result = valid_state and valid_tick;

        return result;
    }

    pub fn deinit(self: *Replayer) void {
        std.debug.assert(self.is_valid());

        self.recording = null;
        self.callback = null;
        self.callback_context = null;
    }

    pub fn load_recording(self: *Replayer, recording: *const Recording) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(recording) != 0);
        std.debug.assert(recording.is_valid());

        self.recording = recording;
        self.reset();

        std.debug.assert(self.recording != null);
        std.debug.assert(self.is_valid());
    }

    pub fn set_callback(self: *Replayer, callback: ReplayCallback, context: ?*anyopaque) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(callback) != 0);

        self.callback = callback;
        self.callback_context = context;

        std.debug.assert(self.callback != null);
    }

    pub fn reset(self: *Replayer) void {
        std.debug.assert(self.is_valid());

        self.current_tick = 0;
        self.current_event_index = 0;
        self.state = .{};

        std.debug.assert(self.current_tick == 0);
        std.debug.assert(self.current_event_index == 0);
        std.debug.assert(self.is_valid());
    }

    pub fn step(self: *Replayer) bool {
        std.debug.assert(self.is_valid());

        const recording = self.recording orelse return false;

        std.debug.assert(recording.is_valid());

        if (self.current_tick >= recording.config.max_ticks) {
            return false;
        }

        var iteration: u64 = 0;

        while (self.current_event_index < recording.events.len and iteration < iteration_max) : (iteration += 1) {
            std.debug.assert(self.current_event_index < recording.events.len);
            std.debug.assert(iteration < iteration_max);

            const event = &recording.events[self.current_event_index];

            std.debug.assert(event.is_valid());

            if (event.tick > self.current_tick) break;

            self.apply_event(event);

            if (self.callback) |cb| {
                cb(self, self.current_tick, event);
            }

            self.current_event_index += 1;
        }

        std.debug.assert(iteration < iteration_max);

        self.state.tick = self.current_tick;
        self.current_tick += 1;

        std.debug.assert(self.is_valid());

        return true;
    }

    pub fn step_to(self: *Replayer, target_tick: u64) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(target_tick <= tick_max);

        var iteration: u64 = 0;

        while (self.current_tick < target_tick and iteration < iteration_max) : (iteration += 1) {
            std.debug.assert(self.current_tick < target_tick);
            std.debug.assert(iteration < iteration_max);

            if (!self.step()) break;
        }

        std.debug.assert(iteration < iteration_max);
        std.debug.assert(self.is_valid());
    }

    pub fn run(self: *Replayer) void {
        std.debug.assert(self.is_valid());

        const recording = self.recording orelse return;

        std.debug.assert(recording.is_valid());

        var iteration: u64 = 0;

        while (self.current_tick < recording.config.max_ticks and iteration < iteration_max) : (iteration += 1) {
            std.debug.assert(self.current_tick < recording.config.max_ticks);
            std.debug.assert(iteration < iteration_max);

            if (!self.step()) break;
        }

        std.debug.assert(iteration < iteration_max);
        std.debug.assert(self.is_valid());
    }

    pub fn get_state(self: *const Replayer) ReplayState {
        std.debug.assert(self.is_valid());

        const result = self.state;

        std.debug.assert(result.is_valid());

        return result;
    }

    fn apply_event(self: *Replayer, event: *const RecordedEvent) void {
        std.debug.assert(self.is_valid());
        std.debug.assert(@intFromPtr(event) != 0);
        std.debug.assert(event.is_valid());

        switch (event.event) {
            .installed => {
                self.state.hook_state = .installed;
                self.state.health = .healthy;
            },
            .removed => {
                self.state.hook_state = .removed;
                self.state.health = .confirmed_unhooked;
            },
            .timeout => {
                self.state.timeouts_so_far += 1;
                self.state.hook_state = .timeout_pending;
            },
            .reinstalled => {
                self.state.reinstalls_so_far += 1;
                self.state.hook_state = .installed;
                self.state.health = .healthy;
            },
            .desktop_switched => {},
            .session_locked => {
                self.state.session_locked = true;
                self.state.hook_state = .blocked_session_locked;
                self.state.health = .confirmed_unhooked;
            },
            .session_unlocked => {
                self.state.session_locked = false;
                self.state.hook_state = .installed;
                self.state.health = .healthy;
            },
            .system_sleep => {
                self.state.in_sleep = true;
                self.state.hook_state = .removed;
                self.state.health = .confirmed_unhooked;
            },
            .system_resume => {
                self.state.in_sleep = false;
            },
            .uac_prompt => {
                self.state.in_uac = true;
                self.state.desktop_secure = true;
                self.state.hook_state = .blocked_uac;
                self.state.health = .presumed_unhooked;
            },
            .uac_dismissed => {
                self.state.in_uac = false;
                self.state.desktop_secure = false;
                self.state.hook_state = .installed;
                self.state.health = .healthy;
            },
            .remote_connect => {
                self.state.hook_state = .removed;
                self.state.health = .presumed_unhooked;
            },
            .remote_disconnect => {
                self.state.hook_state = .installed;
                self.state.health = .healthy;
            },
        }

        self.state.hook_state = event.hook_state;
        self.state.health = event.health;

        std.debug.assert(self.state.is_valid());
    }
};

const testing = std.testing;

test "Replayer init" {
    var replayer = Replayer.init();
    defer replayer.deinit();

    try testing.expect(replayer.is_valid());
    try testing.expectEqual(@as(u64, 0), replayer.current_tick);
    try testing.expectEqual(State.installed, replayer.state.hook_state);
}

test "Replayer reset" {
    var replayer = Replayer.init();
    defer replayer.deinit();

    replayer.current_tick = 100;
    replayer.state.timeouts_so_far = 5;

    replayer.reset();

    try testing.expect(replayer.is_valid());
    try testing.expectEqual(@as(u64, 0), replayer.current_tick);
    try testing.expectEqual(@as(u64, 0), replayer.state.timeouts_so_far);
}

test "ReplayState is_valid" {
    const state = ReplayState{};

    try testing.expect(state.is_valid());
}
