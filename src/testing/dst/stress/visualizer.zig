const std = @import("std");
const assert = std.debug.assert;
const common = @import("common");

const EventKind = enum(u8) {
    processing_delay = 0,
    queue_backpressure = 1,
    timing_window_miss = 2,
    input_coalesced = 3,
    system_stall = 4,
    hook_lost = 5,
    hook_restored = 6,
    cpu_spike = 7,
    cpu_normal = 8,
    input_reordered = 9,
    modifier_race = 10,
    rapid_repeat = 11,
    throttle_activated = 12,
    input_expired = 13,
    priority_drop = 14,
};

const Event = struct {
    tick: u32,
    kind: EventKind,
    data: u32,
};

const SystemState = struct {
    tick: u32 = 0,
    cpu_load: u8 = 0,
    in_stall: bool = false,
    has_focus: bool = true,
    queue_depth: u32 = 0,
    stall_end_tick: u32 = 0,
    cpu_spike_end_tick: u32 = 0,
    recent_delay_ns: u64 = 0,
};

const max_events: usize = 65536;
const max_visible: usize = 16384;
const max_tick: u32 = 10_000_000;
const max_queue_capacity: u32 = 1024;

var events = common.EventStore(Event, max_events){};
var ticker = common.TickTracker(0){};
var seed_store = common.SeedStore(){};

var visible_buffer: [max_visible * 3]u32 = undefined;

var final_queued: u32 = 0;
var final_processed: u32 = 0;
var final_dropped: u32 = 0;
var final_misses: u32 = 0;
var final_bursts: u32 = 0;
var final_bindings: u32 = 0;
var final_max_queue: u32 = 0;
var final_total_delay_ns: u64 = 0;
var final_stress_ticks: u32 = 0;
var final_coalesced: u32 = 0;
var final_races: u32 = 0;
var final_hook_lost_drops: u32 = 0;
var final_stall_drops: u32 = 0;
var final_backpressure_drops: u32 = 0;
var final_hook_deaths: u32 = 0;
var final_hook_restores: u32 = 0;

var queue_capacity: u32 = 64;
var current_state: SystemState = .{};

export fn init() void {
    clear();

    assert(events.count == 0);
    assert(ticker.current == 0);
}

export fn clear() void {
    events.clear();
    ticker.clear();
    seed_store.clear();
    final_queued = 0;
    final_processed = 0;
    final_dropped = 0;
    final_misses = 0;
    final_bursts = 0;
    final_bindings = 0;
    final_max_queue = 0;
    final_total_delay_ns = 0;
    final_stress_ticks = 0;
    final_coalesced = 0;
    final_races = 0;
    final_hook_lost_drops = 0;
    final_stall_drops = 0;
    final_backpressure_drops = 0;
    final_hook_deaths = 0;
    final_hook_restores = 0;
    queue_capacity = 64;
    current_state = .{};

    assert(queue_capacity > 0);
    assert(queue_capacity <= max_queue_capacity);
}

export fn reset() void {
    clear();
}

export fn set_max_tick(t: u32) void {
    assert(t <= max_tick);
    ticker.max = t;
}

export fn add_event(tick: u32, kind: u8, data: u32) void {
    assert(tick <= max_tick);
    assert(kind <= @intFromEnum(EventKind.priority_drop));

    events.add(.{
        .tick = tick,
        .kind = @enumFromInt(kind),
        .data = data,
    });
    ticker.update_max(tick);

    assert(events.count <= max_events);
}

export fn set_stats(
    seed_lo: u32,
    seed_hi: u32,
    queued: u32,
    processed: u32,
    dropped: u32,
    misses: u32,
    bursts: u32,
    bindings: u32,
    queue_max: u32,
    delay_lo: u32,
    delay_hi: u32,
    stress: u32,
    coalesced: u32,
    races: u32,
    hook_lost_drops: u32,
    stall_drops: u32,
    backpressure_drops: u32,
    hook_deaths: u32,
    hook_restores: u32,
) void {
    assert(processed <= queued);

    seed_store.set(seed_lo, seed_hi);
    final_queued = queued;
    final_processed = processed;
    final_dropped = dropped;
    final_misses = misses;
    final_bursts = bursts;
    final_bindings = bindings;
    final_max_queue = queue_max;
    final_total_delay_ns = (@as(u64, delay_hi) << 32) | @as(u64, delay_lo);
    final_stress_ticks = stress;
    final_coalesced = coalesced;
    final_races = races;
    final_hook_lost_drops = hook_lost_drops;
    final_stall_drops = stall_drops;
    final_backpressure_drops = backpressure_drops;
    final_hook_deaths = hook_deaths;
    final_hook_restores = hook_restores;

    assert(final_processed <= final_queued);
}

export fn set_queue_capacity(capacity: u32) void {
    assert(capacity > 0);
    assert(capacity <= max_queue_capacity);

    queue_capacity = capacity;
}

fn interpolate_stat(final_value: u32) u32 {
    if (ticker.max == 0) return 0;
    const progress = @as(u64, ticker.current) * @as(u64, final_value);
    return @truncate(progress / @as(u64, ticker.max));
}

fn compute_state_at_tick(tick: u32) void {
    assert(tick <= max_tick);

    current_state = .{};

    var iterations: u32 = 0;
    for (events.slice()) |event| {
        if (event.tick > tick) break;
        if (iterations >= max_events) break;

        switch (event.kind) {
            .processing_delay => {
                current_state.recent_delay_ns = event.data;
            },
            .queue_backpressure => {
                current_state.queue_depth = event.data;
            },
            .system_stall => {
                current_state.in_stall = true;
                current_state.stall_end_tick = event.tick + event.data;
            },
            .hook_lost => {
                current_state.has_focus = false;
            },
            .hook_restored => {
                current_state.has_focus = true;
                current_state.in_stall = false;
            },
            .cpu_spike => {
                current_state.cpu_load = @truncate(event.data);
                current_state.cpu_spike_end_tick = event.tick + 100;
            },
            .cpu_normal => {
                current_state.cpu_load = 0;
            },
            .timing_window_miss,
            .input_coalesced,
            .input_reordered,
            .modifier_race,
            .rapid_repeat,
            .throttle_activated,
            .input_expired,
            .priority_drop,
            => {},
        }

        if (current_state.stall_end_tick > 0 and event.tick >= current_state.stall_end_tick) {
            current_state.in_stall = false;
        }
        if (current_state.cpu_spike_end_tick > 0 and event.tick >= current_state.cpu_spike_end_tick) {
            current_state.cpu_load = 0;
        }

        iterations += 1;
    }

    current_state.tick = tick;

    assert(current_state.cpu_load <= 100);
}

export fn set_tick(tick: u32) void {
    assert(tick <= max_tick);

    ticker.set(tick);
    compute_state_at_tick(tick);

    assert(ticker.current == tick);
}

export fn step_forward() void {
    ticker.step_forward();
    compute_state_at_tick(ticker.current);

    assert(ticker.current <= ticker.max);
}

export fn step_backward() void {
    ticker.step_backward();
    compute_state_at_tick(ticker.current);

    assert(ticker.current <= ticker.max);
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

export fn get_inputs_queued() u32 {
    return interpolate_stat(final_queued);
}

export fn get_inputs_processed() u32 {
    return interpolate_stat(final_processed);
}

export fn get_inputs_dropped() u32 {
    return interpolate_stat(final_dropped);
}

export fn get_timing_misses() u32 {
    return interpolate_stat(final_misses);
}

export fn get_bursts_generated() u32 {
    return interpolate_stat(final_bursts);
}

export fn get_coalesced_inputs() u32 {
    return interpolate_stat(final_coalesced);
}

export fn get_modifier_races() u32 {
    return interpolate_stat(final_races);
}

export fn get_stress_ticks() u32 {
    return interpolate_stat(final_stress_ticks);
}

export fn get_hook_lost_drops() u32 {
    return interpolate_stat(final_hook_lost_drops);
}

export fn get_stall_drops() u32 {
    return interpolate_stat(final_stall_drops);
}

export fn get_backpressure_drops() u32 {
    return interpolate_stat(final_backpressure_drops);
}

export fn get_hook_deaths() u32 {
    return interpolate_stat(final_hook_deaths);
}

export fn get_hook_restores() u32 {
    return interpolate_stat(final_hook_restores);
}

export fn get_cpu_load() u32 {
    return current_state.cpu_load;
}

export fn get_queue_depth() u32 {
    return current_state.queue_depth;
}

export fn is_in_stall() u32 {
    return if (current_state.in_stall) 1 else 0;
}

export fn has_focus() u32 {
    return if (current_state.has_focus) 1 else 0;
}

export fn get_queue_capacity() u32 {
    return queue_capacity;
}

export fn get_recent_delay_ms() u32 {
    return @truncate(current_state.recent_delay_ns / 1_000_000);
}

export fn is_under_stress() u32 {
    const under_stress = current_state.in_stall or
        current_state.cpu_load > 50 or
        !current_state.has_focus or
        current_state.queue_depth > queue_capacity / 2;
    return if (under_stress) 1 else 0;
}

export fn get_stress_percentage() u32 {
    if (ticker.max == 0) return 0;
    return @truncate((@as(u64, final_stress_ticks) * 100) / @as(u64, ticker.max));
}

export fn get_event_count() u32 {
    return @intCast(events.count);
}

export fn get_events_at_tick_count(tick: u32) u32 {
    assert(tick <= max_tick);
    return events.count_at_tick(tick);
}

export fn get_event_at_tick_by_index(tick: u32, index: u32) u32 {
    assert(tick <= MAX_TICK);

    if (events.get_at_tick_by_index(tick, index)) |event| {
        return (@as(u32, @intFromEnum(event.kind)) << 8) | @as(u32, event.data & 0xFF);
    }
    return 0xFFFFFFFF;
}

export fn get_event_at_index(index: u32) u64 {
    assert(index < max_events);

    if (events.get(index)) |event| {
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
    assert(start_tick <= end_tick);
    assert(end_tick <= max_tick);

    var count: u32 = 0;
    const limit: u32 = max_visible;

    for (events.slice()) |event| {
        if (event.tick < start_tick) continue;
        if (event.tick > end_tick) break;
        if (count >= limit) break;

        visible_buffer[count * 3 + 0] = event.tick;
        visible_buffer[count * 3 + 1] = @intFromEnum(event.kind);
        visible_buffer[count * 3 + 2] = event.data;
        count += 1;
    }

    assert(count <= max_visible);
    return count;
}

export fn get_next_event_tick(current_tick: u32) u32 {
    assert(current_tick <= max_tick);
    return events.get_next_tick(current_tick);
}

export fn get_prev_event_tick(current_tick: u32) u32 {
    assert(current_tick <= max_tick);
    return events.get_prev_tick(current_tick);
}
