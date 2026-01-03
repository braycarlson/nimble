const std = @import("std");
const common = @import("common");

pub const iteration_max: u32 = 65536;

const EventKind = enum(u8) {
    key_down = 0,
    key_up = 1,
    binding_triggered = 2,
    binding_blocked = 3,
    binding_replaced = 4,
    binding_registered = 5,
    binding_unregistered = 6,
    state_divergence = 7,
    tick = 8,
    snapshot = 9,
    fault_injected = 10,
    invariant_violated = 11,
};

const Event = struct {
    tick: u32,
    kind: EventKind,
    keycode: u8,
};

const max_events: u32 = 65536;
const max_visible: u32 = 16384;

var events = common.EventStore(Event, max_events){};
var ticker = common.TickTracker(0){};
var seed_store = common.SeedStore(){};
var keyboard = common.KeyboardState(){};

var visible_buffer: [max_visible * 3]u32 = undefined;

var current_bindings: u32 = 0;
var current_key_events: u32 = 0;
var current_blocks: u32 = 0;
var current_allows: u32 = 0;
var current_faults: u32 = 0;
var current_violations: u32 = 0;

export fn init() void {
    clear();
}

export fn clear() void {
    events.clear();
    ticker.clear();
    seed_store.clear();
    keyboard.clear();
    current_bindings = 0;
    current_key_events = 0;
    current_blocks = 0;
    current_allows = 0;
    current_faults = 0;
    current_violations = 0;
}

export fn set_max_tick(t: u32) void {
    ticker.max = t;
}

export fn add_event(tick: u32, kind: u8, keycode_value: u8) void {
    std.debug.assert(kind <= @intFromEnum(EventKind.invariant_violated));

    events.add(.{
        .tick = tick,
        .kind = @enumFromInt(kind),
        .keycode = keycode_value,
    });
    ticker.update_max(tick);
}

export fn set_stats(seed_lo: u32, seed_hi: u32) void {
    seed_store.set(seed_lo, seed_hi);
}

export fn set_tick(tick: u32) void {
    reset_current_stats();
    process_events_to_tick(tick);
    ticker.set(tick);
}

fn reset_current_stats() void {
    keyboard.clear();
    current_bindings = 0;
    current_key_events = 0;
    current_blocks = 0;
    current_allows = 0;
    current_faults = 0;
    current_violations = 0;
}

fn process_events_to_tick(tick: u32) void {
    var i: u32 = 0;
    const event_slice = events.slice();
    const slice_len: u32 = @intCast(event_slice.len);

    while (i < slice_len and i < iteration_max) : (i += 1) {
        std.debug.assert(i < slice_len);

        const evt = event_slice[i];

        if (evt.tick > tick) {
            break;
        }

        process_single_event(&evt);
    }

    std.debug.assert(i <= iteration_max);
}

fn process_single_event(evt: *const Event) void {
    switch (evt.kind) {
        .key_down => {
            keyboard.set_down(evt.keycode, true);
            current_key_events += 1;
        },
        .key_up => {
            keyboard.set_down(evt.keycode, false);
            current_key_events += 1;
        },
        .binding_triggered => {
            current_allows += 1;
        },
        .binding_blocked, .binding_replaced => {
            current_blocks += 1;
        },
        .binding_registered => {
            current_bindings += 1;
        },
        .binding_unregistered => {
            if (current_bindings > 0) {
                current_bindings -= 1;
            }
        },
        .fault_injected => {
            current_faults += 1;
        },
        .invariant_violated => {
            current_violations += 1;
        },
        else => {},
    }
}

export fn step_forward() void {
    ticker.step_forward();
    set_tick(ticker.current);
}

export fn step_backward() void {
    ticker.step_backward();
    set_tick(ticker.current);
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

export fn get_key_events() u32 {
    return current_key_events;
}

export fn get_bindings() u32 {
    return current_bindings;
}

export fn get_blocks() u32 {
    return current_blocks;
}

export fn get_allows() u32 {
    return current_allows;
}

export fn get_faults() u32 {
    return current_faults;
}

export fn get_violations() u32 {
    return current_violations;
}

export fn get_current_key_events() u32 {
    return current_key_events;
}

export fn get_current_blocks() u32 {
    return current_blocks;
}

export fn get_current_allows() u32 {
    return current_allows;
}

export fn is_key_down(keycode_value: u8) bool {
    return keyboard.is_down(keycode_value);
}

export fn get_keys_down_count() u32 {
    return keyboard.count();
}

export fn get_event_count() u32 {
    return @intCast(events.count);
}

export fn get_events_at_tick_count(tick: u32) u32 {
    return events.count_at_tick(tick);
}

export fn get_event_at_tick_by_index(tick: u32, index: u32) u32 {
    if (events.get_at_tick_by_index(tick, index)) |evt| {
        const result = (@as(u32, @intFromEnum(evt.kind)) << 8) | @as(u32, evt.keycode);

        return result;
    }

    return 0xFFFFFFFF;
}

export fn get_event_at_index(index: u32) u64 {
    if (events.get(index)) |evt| {
        const tick_part: u64 = @as(u64, evt.tick) << 32;
        const kind_part: u64 = @as(u64, @intFromEnum(evt.kind)) << 24;
        const keycode_part: u64 = @as(u64, evt.keycode);
        const result = tick_part | kind_part | keycode_part;

        return result;
    }

    return 0;
}

export fn get_visible_events_buffer() [*]u32 {
    return &visible_buffer;
}

export fn get_visible_events(start_tick: u32, end_tick: u32) u32 {
    std.debug.assert(end_tick >= start_tick);

    var count: u32 = 0;
    const event_slice = events.slice();
    var i: u32 = 0;
    const slice_len: u32 = @intCast(event_slice.len);

    while (i < slice_len and i < iteration_max) : (i += 1) {
        std.debug.assert(i < slice_len);

        const evt = event_slice[i];

        if (evt.tick < start_tick) {
            continue;
        }

        if (evt.tick > end_tick) {
            break;
        }

        if (count >= max_visible) {
            break;
        }

        std.debug.assert(count < max_visible);

        write_visible_event(count, &evt);
        count += 1;
    }

    std.debug.assert(i <= iteration_max);
    std.debug.assert(count <= max_visible);

    return count;
}

fn write_visible_event(index: u32, evt: *const Event) void {
    std.debug.assert(index < max_visible);

    visible_buffer[index * 3 + 0] = evt.tick;
    visible_buffer[index * 3 + 1] = @intFromEnum(evt.kind);
    visible_buffer[index * 3 + 2] = evt.keycode;
}

export fn get_next_event_tick(current_tick: u32) u32 {
    return events.get_next_tick(current_tick);
}

export fn get_prev_event_tick(current_tick: u32) u32 {
    return events.get_prev_tick(current_tick);
}
