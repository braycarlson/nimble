const std = @import("std");

const common = @import("common");
const state_mod = @import("state.zig");
const simulator = @import("simulator.zig");

const Event = state_mod.Event;
const Stats = state_mod.Stats;
const Snapshot = state_mod.Snapshot;

const VOPR = simulator.VOPR;
const ReplayEntry = simulator.ReplayEntry;

pub const Format = common.Format;

pub const iteration_max: u32 = 65536;
pub const file_size_max: u32 = 100 * 1024 * 1024;

pub const HeaderExtra = extern struct {
    snapshot_count: u32,
    replay_count: u32,
    result: u8,
    reserved: [27]u8 = [_]u8{0} ** 27,

    pub fn is_valid(self: *const HeaderExtra) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_snapshot = self.snapshot_count <= state_mod.max_snapshots;
        const result = valid_snapshot;

        return result;
    }
};

pub const Header = common.Header("INPT", HeaderExtra);

const JsonStats = struct {
    total_operations: u64,
    key_events: u64,
    bindings_registered: u32,
    bindings_unregistered: u32,
    passes: u64,
    consumes: u64,
    replaces: u64,
    faults_injected: u32,
    invariant_violations: u32,
};

const JsonEvent = struct {
    tick: u64,
    kind: []const u8,
    keycode: u8,
};

const JsonRecording = struct {
    type: []const u8,
    seed: u64,
    max_ticks: u64,
    total_ticks: u64,
    stats: []const JsonStats,
    events: []const JsonEvent,
};

pub const Recorder = struct {
    allocator: std.mem.Allocator,
    buffer: std.ArrayListUnmanaged(u8),
    format: Format,

    pub fn init(allocator: std.mem.Allocator, format: Format) Recorder {
        std.debug.assert(@intFromPtr(&allocator) != 0);

        const result = Recorder{
            .allocator = allocator,
            .buffer = .{},
            .format = format,
        };

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn is_valid(self: *const Recorder) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        return true;
    }

    pub fn deinit(self: *Recorder) void {
        std.debug.assert(self.is_valid());

        self.buffer.deinit(self.allocator);
    }

    pub fn record_vopr(self: *Recorder, vopr: *const VOPR) !void {
        std.debug.assert(self.is_valid());
        std.debug.assert(vopr.is_valid());

        self.buffer.clearRetainingCapacity();

        switch (self.format) {
            .binary => try self.record_binary(vopr),
            .json => try self.record_json(vopr),
        }
    }

    fn record_binary(self: *Recorder, vopr: *const VOPR) !void {
        std.debug.assert(self.is_valid());
        std.debug.assert(vopr.is_valid());

        const header = Header{
            .seed = vopr.config.seed,
            .max_ticks = vopr.config.max_ticks,
            .total_ticks = vopr.stats.total_ticks,
            .event_count = @intCast(vopr.state_checker.events_len),
            .extra = .{
                .snapshot_count = @intCast(vopr.state_checker.snapshots_len),
                .replay_count = 0,
                .result = 0,
            },
        };

        std.debug.assert(header.extra.is_valid());

        var writer = self.buffer.writer(self.allocator);
        try writer.writeAll(std.mem.asBytes(&header));

        const events_len: u32 = @intCast(vopr.state_checker.events_len);
        const len = @min(events_len, iteration_max);

        for (vopr.state_checker.events[0..len]) |event| {
            std.debug.assert(event.is_valid());

            try writer.writeAll(std.mem.asBytes(&event));
        }
    }

    fn record_json(self: *Recorder, vopr: *const VOPR) !void {
        std.debug.assert(self.is_valid());
        std.debug.assert(vopr.is_valid());

        const events = try self.build_events(vopr);
        defer self.allocator.free(events);

        const json_stats = [_]JsonStats{.{
            .total_operations = vopr.stats.total_operations,
            .key_events = vopr.stats.key_events,
            .bindings_registered = vopr.stats.bindings_registered,
            .bindings_unregistered = vopr.stats.bindings_unregistered,
            .passes = vopr.stats.passes,
            .consumes = vopr.stats.consumes,
            .replaces = vopr.stats.replaces,
            .faults_injected = vopr.stats.faults_injected,
            .invariant_violations = vopr.stats.invariant_violations,
        }};

        const recording = JsonRecording{
            .type = "input",
            .seed = vopr.config.seed,
            .max_ticks = vopr.config.max_ticks,
            .total_ticks = vopr.stats.total_ticks,
            .stats = &json_stats,
            .events = events,
        };

        const json_str = try std.json.Stringify.valueAlloc(self.allocator, recording, .{ .whitespace = .indent_2 });
        defer self.allocator.free(json_str);

        try self.buffer.appendSlice(self.allocator, json_str);
    }

    fn build_events(self: *Recorder, vopr: *const VOPR) ![]JsonEvent {
        std.debug.assert(self.is_valid());
        std.debug.assert(vopr.is_valid());

        const events_len: u32 = @intCast(vopr.state_checker.events_len);
        const len = @min(events_len, iteration_max);

        var events = try self.allocator.alloc(JsonEvent, len);
        errdefer self.allocator.free(events);

        for (vopr.state_checker.events[0..len], 0..) |event, i| {
            std.debug.assert(event.is_valid());

            events[i] = .{
                .tick = event.tick,
                .kind = @tagName(event.kind),
                .keycode = event.keycode,
            };
        }

        return events;
    }

    pub fn get_data(self: *const Recorder) []const u8 {
        std.debug.assert(self.is_valid());

        return self.buffer.items;
    }

    pub fn write_to_file(self: *const Recorder, path: []const u8) !void {
        std.debug.assert(self.is_valid());
        std.debug.assert(path.len > 0);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        try file.writeAll(self.buffer.items);
    }
};

pub const Recording = struct {
    allocator: std.mem.Allocator,
    header: Header,
    events: []Event,
    snapshots: []Snapshot,
    replay: []ReplayEntry,
    stats: Stats,

    pub fn is_valid(self: *const Recording) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_events = self.events.len <= state_mod.max_events;
        const valid_snapshots = self.snapshots.len <= state_mod.max_snapshots;
        const valid_stats = self.stats.is_valid();
        const result = valid_events and valid_snapshots and valid_stats;

        return result;
    }

    pub fn deinit(self: *Recording) void {
        std.debug.assert(self.is_valid());

        self.allocator.free(self.events);
        self.allocator.free(self.snapshots);
        self.allocator.free(self.replay);
    }

    pub fn load_from_file(allocator: std.mem.Allocator, path: []const u8) !Recording {
        std.debug.assert(@intFromPtr(&allocator) != 0);
        std.debug.assert(path.len > 0);

        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        const content = try file.readToEndAlloc(allocator, file_size_max);
        defer allocator.free(content);

        std.debug.assert(content.len > 0);
        std.debug.assert(content.len <= file_size_max);

        const result = try parse(allocator, content);

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn parse(allocator: std.mem.Allocator, content: []const u8) !Recording {
        std.debug.assert(@intFromPtr(&allocator) != 0);
        std.debug.assert(content.len > 0);

        const parsed = try std.json.parseFromSlice(JsonRecording, allocator, content, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        const json = parsed.value;

        const events = try parse_events(allocator, json.events);
        errdefer allocator.free(events);

        const snapshots = try allocator.alloc(Snapshot, 0);
        const replay = try allocator.alloc(ReplayEntry, 0);

        const stats = if (json.stats.len > 0) Stats{
            .total_operations = json.stats[0].total_operations,
            .key_events = json.stats[0].key_events,
            .bindings_registered = json.stats[0].bindings_registered,
            .bindings_unregistered = json.stats[0].bindings_unregistered,
            .passes = json.stats[0].passes,
            .consumes = json.stats[0].consumes,
            .replaces = json.stats[0].replaces,
            .faults_injected = json.stats[0].faults_injected,
            .invariant_violations = json.stats[0].invariant_violations,
        } else Stats{};

        const header = Header{
            .seed = json.seed,
            .max_ticks = json.max_ticks,
            .total_ticks = json.total_ticks,
            .event_count = @intCast(events.len),
            .extra = .{
                .snapshot_count = 0,
                .replay_count = 0,
                .result = 0,
            },
        };

        const result = Recording{
            .allocator = allocator,
            .header = header,
            .events = events,
            .snapshots = snapshots,
            .replay = replay,
            .stats = stats,
        };

        std.debug.assert(result.is_valid());

        return result;
    }

    fn parse_events(allocator: std.mem.Allocator, json_events: []const JsonEvent) ![]Event {
        std.debug.assert(@intFromPtr(&allocator) != 0);
        std.debug.assert(json_events.len <= state_mod.max_events);

        var events = try allocator.alloc(Event, json_events.len);
        errdefer allocator.free(events);

        for (json_events, 0..) |evt, i| {
            events[i] = Event{
                .tick = evt.tick,
                .kind = std.meta.stringToEnum(state_mod.EventKind, evt.kind) orelse .key_down,
                .keycode = evt.keycode,
                .binding_id = 0,
                .response = null,
            };

            std.debug.assert(events[i].is_valid());
        }

        return events;
    }

    pub fn get_event_at_tick(self: *const Recording, target_tick: u64) ?*const Event {
        std.debug.assert(self.is_valid());

        for (self.events) |*event| {
            if (event.tick == target_tick) {
                return event;
            }
        }

        return null;
    }

    pub fn get_snapshot_at_tick(self: *const Recording, target_tick: u64) ?*const Snapshot {
        std.debug.assert(self.is_valid());

        var best: ?*const Snapshot = null;

        for (self.snapshots) |*snapshot| {
            if (snapshot.tick <= target_tick) {
                best = snapshot;
            } else {
                break;
            }
        }

        return best;
    }

    pub fn get_events_in_range(self: *const Recording, start: u64, end: u64) []const Event {
        std.debug.assert(self.is_valid());
        std.debug.assert(end >= start);

        var start_idx: usize = 0;
        var end_idx: usize = 0;
        var found_start: bool = false;

        for (self.events, 0..) |event, i| {
            if (event.tick >= start and !found_start) {
                start_idx = i;
                found_start = true;
            }

            if (event.tick <= end) {
                end_idx = i + 1;
            }
        }

        if (start_idx >= end_idx) {
            return &[_]Event{};
        }

        return self.events[start_idx..end_idx];
    }
};
