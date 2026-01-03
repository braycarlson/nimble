const std = @import("std");
const common = @import("common");

const EventKind = enum(u8) {
    installed = 0,
    removed = 1,
    timeout = 2,
    reinstalled = 3,
    desktop_switched = 4,
    session_locked = 5,
    session_unlocked = 6,
    system_sleep = 7,
    system_resume = 8,
    uac_prompt = 9,
    uac_dismissed = 10,
    remote_connect = 11,
    remote_disconnect = 12,

    pub fn is_valid(self: EventKind) bool {
        const value = @intFromEnum(self);
        const result = value <= 12;
        return result;
    }
};

const State = enum(u8) {
    installed = 0,
    removed = 1,
    timed_out = 2,
    blocked_uac = 3,
    blocked_desktop = 4,
    blocked_session = 5,

    pub fn is_valid(self: State) bool {
        const value = @intFromEnum(self);
        const result = value <= 5;
        return result;
    }
};

const Health = enum(u8) {
    healthy = 0,
    degraded = 1,
    presumed_unhooked = 2,
    confirmed_unhooked = 3,

    pub fn is_valid(self: Health) bool {
        const value = @intFromEnum(self);
        const result = value <= 3;
        return result;
    }
};

const Event = struct {
    tick: u32,
    kind: EventKind,
    data: u32,

    pub fn is_valid(self: *const Event) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_kind = self.kind.is_valid();
        const result = valid_kind;

        return result;
    }
};

const max_events: usize = 65536;
const max_visible: usize = 16384;
const iteration_max: u32 = 0xFFFFFFFF;

var events = common.EventStore(Event, max_events){};
var ticker = common.TickTracker(0){};
var seed_store = common.SeedStore(){};

var visible_buffer: [max_visible * 3]u32 = undefined;

var final_total_callbacks: u32 = 0;
var final_callbacks_under: u32 = 0;
var final_callbacks_over: u32 = 0;
var final_timeouts: u32 = 0;
var final_unhooks: u32 = 0;
var final_reinstall_attempts: u32 = 0;
var final_reinstall_successes: u32 = 0;
var final_reinstall_failures: u32 = 0;
var final_inputs_lost: u32 = 0;

var max_callback_ns: u64 = 0;
var avg_callback_ns: u64 = 0;
var max_consecutive_slow: u32 = 0;

var final_desktop_switches: u32 = 0;
var final_session_locks: u32 = 0;
var final_uac_prompts: u32 = 0;

var current_hook_state: State = .installed;
var current_health: Health = .healthy;
var current_session_locked: bool = false;
var current_in_uac: bool = false;
var current_in_sleep: bool = false;
var current_desktop_secure: bool = false;
var current_timeouts: u32 = 0;
var current_reinstalls: u32 = 0;

export fn init() void {
    clear();
}

export fn clear() void {
    events.clear();
    ticker.clear();
    seed_store.clear();
    final_total_callbacks = 0;
    final_callbacks_under = 0;
    final_callbacks_over = 0;
    final_timeouts = 0;
    final_unhooks = 0;
    final_reinstall_attempts = 0;
    final_reinstall_successes = 0;
    final_reinstall_failures = 0;
    final_inputs_lost = 0;
    max_callback_ns = 0;
    avg_callback_ns = 0;
    max_consecutive_slow = 0;
    final_desktop_switches = 0;
    final_session_locks = 0;
    final_uac_prompts = 0;
    current_hook_state = .installed;
    current_health = .healthy;
    current_session_locked = false;
    current_in_uac = false;
    current_in_sleep = false;
    current_desktop_secure = false;
    current_timeouts = 0;
    current_reinstalls = 0;

    std.debug.assert(current_hook_state.is_valid());
    std.debug.assert(current_health.is_valid());
}

export fn reset() void {
    clear();
}

export fn set_seed(lo: u32, hi: u32) void {
    seed_store.set(lo, hi);
}

export fn set_max_tick(t: u32) void {
    ticker.max = t;
}

export fn set_stats(
    total: u32,
    under: u32,
    over: u32,
    timeouts: u32,
    unhooks: u32,
    attempts: u32,
    successes: u32,
    failures: u32,
    lost: u32,
) void {
    std.debug.assert(under <= total);
    std.debug.assert(over <= total);
    std.debug.assert(successes <= attempts);
    std.debug.assert(failures <= attempts);

    final_total_callbacks = total;
    final_callbacks_under = under;
    final_callbacks_over = over;
    final_timeouts = timeouts;
    final_unhooks = unhooks;
    final_reinstall_attempts = attempts;
    final_reinstall_successes = successes;
    final_reinstall_failures = failures;
    final_inputs_lost = lost;
}

export fn set_callback_stats(max_ns_lo: u32, max_ns_hi: u32, avg_ns_lo: u32, avg_ns_hi: u32, consecutive: u32) void {
    max_callback_ns = (@as(u64, max_ns_hi) << 32) | @as(u64, max_ns_lo);
    avg_callback_ns = (@as(u64, avg_ns_hi) << 32) | @as(u64, avg_ns_lo);
    max_consecutive_slow = consecutive;

    std.debug.assert(avg_callback_ns <= max_callback_ns or max_callback_ns == 0);
}

export fn set_system_stats(desktop: u32, session: u32, uac: u32) void {
    final_desktop_switches = desktop;
    final_session_locks = session;
    final_uac_prompts = uac;
}

export fn add_event(tick: u32, kind: u8, data: u32) void {
    std.debug.assert(kind <= 12);

    const event_kind: EventKind = @enumFromInt(kind);

    std.debug.assert(event_kind.is_valid());

    events.add(.{
        .tick = tick,
        .kind = event_kind,
        .data = data,
    });
    ticker.update_max(tick);
}

fn interpolate_stat(final_value: u32) u32 {
    if (ticker.max == 0) return final_value;

    std.debug.assert(ticker.max > 0);

    const progress = @as(u64, ticker.current) * @as(u64, final_value);
    const result: u32 = @truncate(progress / @as(u64, ticker.max));

    return result;
}

fn reset_current_state() void {
    current_hook_state = .installed;
    current_health = .healthy;
    current_session_locked = false;
    current_in_uac = false;
    current_in_sleep = false;
    current_desktop_secure = false;
    current_timeouts = 0;
    current_reinstalls = 0;

    std.debug.assert(current_hook_state.is_valid());
    std.debug.assert(current_health.is_valid());
}

fn apply_event_to_state(event: *const Event) void {
    std.debug.assert(@intFromPtr(event) != 0);
    std.debug.assert(event.is_valid());

    switch (event.kind) {
        .installed => {
            current_hook_state = .installed;
            current_health = .healthy;
        },
        .removed => {
            current_hook_state = .removed;
        },
        .timeout => {
            current_hook_state = .timed_out;
            current_health = .confirmed_unhooked;
            current_timeouts += 1;
        },
        .reinstalled => {
            current_hook_state = .installed;
            current_health = .healthy;
            current_reinstalls += 1;
        },
        .desktop_switched => {
            current_desktop_secure = !current_desktop_secure;
            if (current_desktop_secure) {
                current_hook_state = .blocked_desktop;
            } else if (current_hook_state == .blocked_desktop) {
                current_hook_state = .installed;
            }
        },
        .session_locked => {
            current_session_locked = true;
            current_hook_state = .blocked_session;
        },
        .session_unlocked => {
            current_session_locked = false;
            if (current_hook_state == .blocked_session) {
                current_hook_state = .installed;
            }
        },
        .system_sleep => {
            current_in_sleep = true;
        },
        .system_resume => {
            current_in_sleep = false;
        },
        .uac_prompt => {
            current_in_uac = true;
            current_hook_state = .blocked_uac;
        },
        .uac_dismissed => {
            current_in_uac = false;
            if (current_hook_state == .blocked_uac) {
                current_hook_state = .installed;
            }
        },
        .remote_connect, .remote_disconnect => {},
    }

    std.debug.assert(current_hook_state.is_valid());
    std.debug.assert(current_health.is_valid());
}

fn compute_state_at_tick(tick: u32) void {
    reset_current_state();

    const slice = events.slice();
    var iteration: u32 = 0;

    for (slice) |*event| {
        std.debug.assert(iteration < iteration_max);

        if (event.tick > tick) break;

        std.debug.assert(event.is_valid());

        apply_event_to_state(event);

        iteration += 1;
    }

    std.debug.assert(current_hook_state.is_valid());
    std.debug.assert(current_health.is_valid());
}

export fn set_tick(tick: u32) void {
    ticker.set(tick);
    compute_state_at_tick(tick);
}

export fn step_forward() void {
    ticker.step_forward();
    compute_state_at_tick(ticker.current);
}

export fn step_backward() void {
    ticker.step_backward();
    compute_state_at_tick(ticker.current);
}

export fn get_tick() u32 {
    return ticker.current;
}

export fn get_max_tick() u32 {
    return ticker.max;
}

export fn get_seed_lo() u32 {
    return seed_store.get_lo();
}

export fn get_seed_hi() u32 {
    return seed_store.get_hi();
}

export fn get_total_callbacks() u32 {
    return interpolate_stat(final_total_callbacks);
}

export fn get_callbacks_under() u32 {
    return interpolate_stat(final_callbacks_under);
}

export fn get_callbacks_over() u32 {
    return interpolate_stat(final_callbacks_over);
}

export fn get_timeouts_triggered() u32 {
    return interpolate_stat(final_timeouts);
}

export fn get_silent_unhooks() u32 {
    return interpolate_stat(final_unhooks);
}

export fn get_reinstall_attempts() u32 {
    return interpolate_stat(final_reinstall_attempts);
}

export fn get_reinstall_successes() u32 {
    return interpolate_stat(final_reinstall_successes);
}

export fn get_reinstall_failures() u32 {
    return interpolate_stat(final_reinstall_failures);
}

export fn get_inputs_lost() u32 {
    return interpolate_stat(final_inputs_lost);
}

export fn get_max_callback_ns_lo() u32 {
    return @truncate(max_callback_ns);
}

export fn get_max_callback_ns_hi() u32 {
    return @truncate(max_callback_ns >> 32);
}

export fn get_avg_callback_ns_lo() u32 {
    return @truncate(avg_callback_ns);
}

export fn get_avg_callback_ns_hi() u32 {
    return @truncate(avg_callback_ns >> 32);
}

export fn get_max_consecutive_slow() u32 {
    return max_consecutive_slow;
}

export fn get_desktop_switches() u32 {
    return interpolate_stat(final_desktop_switches);
}

export fn get_session_locks() u32 {
    return interpolate_stat(final_session_locks);
}

export fn get_uac_prompts() u32 {
    return interpolate_stat(final_uac_prompts);
}

export fn get_hook_state() u8 {
    std.debug.assert(current_hook_state.is_valid());

    return @intFromEnum(current_hook_state);
}

export fn get_health() u8 {
    std.debug.assert(current_health.is_valid());

    return @intFromEnum(current_health);
}

export fn is_session_locked() u8 {
    return @intFromBool(current_session_locked);
}

export fn is_in_uac() u8 {
    return @intFromBool(current_in_uac);
}

export fn is_in_sleep() u8 {
    return @intFromBool(current_in_sleep);
}

export fn is_desktop_secure() u8 {
    return @intFromBool(current_desktop_secure);
}

export fn get_timeouts_so_far() u32 {
    return current_timeouts;
}

export fn get_reinstalls_so_far() u32 {
    return current_reinstalls;
}

export fn get_event_count() u32 {
    return @intCast(events.count);
}

export fn get_events_at_tick_count(tick: u32) u32 {
    return events.count_at_tick(tick);
}

export fn get_event_at_tick_by_index(tick: u32, index: u32) u32 {
    if (events.get_at_tick_by_index(tick, index)) |event| {
        std.debug.assert(event.is_valid());

        return (@as(u32, @intFromEnum(event.kind)) << 8) | @as(u32, event.data & 0xFF);
    }
    return 0xFFFFFFFF;
}

export fn get_event_at_index(index: u32) u64 {
    if (events.get(index)) |event| {
        std.debug.assert(event.is_valid());

        const tick_part: u64 = @as(u64, event.tick) << 32;
        const kind_part: u64 = @as(u64, @intFromEnum(event.kind)) << 24;
        const data_part: u64 = @as(u64, event.data) & 0xFFFFFF;
        return tick_part | kind_part | data_part;
    }
    return 0;
}

export fn get_visible_events_buffer() [*]u32 {
    return &visible_buffer;
}

export fn get_visible_events(start_tick: u32, end_tick: u32) u32 {
    std.debug.assert(start_tick <= end_tick);

    var count: u32 = 0;
    const limit: u32 = max_visible;
    const slice = events.slice();
    var iteration: u32 = 0;

    for (slice) |*event| {
        std.debug.assert(iteration < iteration_max);

        if (event.tick < start_tick) {
            iteration += 1;
            continue;
        }
        if (event.tick > end_tick) break;
        if (count >= limit) break;

        std.debug.assert(event.is_valid());
        std.debug.assert(count < limit);

        visible_buffer[count * 3 + 0] = event.tick;
        visible_buffer[count * 3 + 1] = @intFromEnum(event.kind);
        visible_buffer[count * 3 + 2] = event.data;
        count += 1;
        iteration += 1;
    }

    std.debug.assert(count <= limit);

    return count;
}

export fn get_next_event_tick(current_tick: u32) u32 {
    return events.get_next_tick(current_tick);
}

export fn get_prev_event_tick(current_tick: u32) u32 {
    return events.get_prev_tick(current_tick);
}
