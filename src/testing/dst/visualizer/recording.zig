const std = @import("std");

const max_file_size: usize = 10 * 1024 * 1024;
const max_events: usize = 1_000_000;

pub const Event = struct {
    tick: u64,
    kind: Kind,
    keycode: u8,
    data: u32,

    pub const Kind = enum {
        key_down,
        key_up,
        binding_triggered,
        binding_blocked,
        binding_replaced,
        binding_registered,
        binding_unregistered,
        state_divergence,
        tick,
        snapshot,
        fault_injected,
        invariant_violated,
        blocked,
        allowed,
        hook_installed,
        hook_removed,
        timeout,
        reinstall,
        unknown,
    };
};

pub const Stats = struct {
    key_events: u64 = 0,
    bindings_registered: u64 = 0,
    blocks: u64 = 0,
    allows: u64 = 0,
    total_callbacks: u64 = 0,
    timeouts_triggered: u64 = 0,
    reinstall_attempts: u64 = 0,
    stress_ticks: u64 = 0,
    inputs_dropped: u64 = 0,
    max_queue_depth: u64 = 0,
    invariant_violations: u64 = 0,
    passes: u64 = 0,
    consumes: u64 = 0,
    replaces: u64 = 0,
    faults_injected: u64 = 0,
};

pub const Header = struct {
    seed: u64,
    total_ticks: u64,
    max_ticks: u64,
};

pub const Data = struct {
    header: Header,
    events: []Event,
    stats: Stats,

    pub fn deinit(self: *Data, allocator: std.mem.Allocator) void {
        allocator.free(self.events);
    }
};

const LoadError = error{
    InvalidJson,
    MissingField,
    InvalidFieldType,
    OutOfMemory,
    FileNotFound,
    AccessDenied,
    Unexpected,
};

fn get_u64(obj: std.json.ObjectMap, key: []const u8) LoadError!u64 {
    const value = obj.get(key) orelse return LoadError.MissingField;
    return switch (value) {
        .integer => |i| @intCast(i),
        .float => |f| @intFromFloat(f),
        .number_string => |s| std.fmt.parseInt(u64, s, 10) catch return LoadError.InvalidFieldType,
        else => LoadError.InvalidFieldType,
    };
}

fn get_u64_optional(obj: std.json.ObjectMap, key: []const u8, default: u64) u64 {
    const value = obj.get(key) orelse return default;
    return switch (value) {
        .integer => |i| @intCast(i),
        .float => |f| @intFromFloat(f),
        .number_string => |s| std.fmt.parseInt(u64, s, 10) catch default,
        else => default,
    };
}

fn get_string(obj: std.json.ObjectMap, key: []const u8) LoadError![]const u8 {
    const value = obj.get(key) orelse return LoadError.MissingField;
    return switch (value) {
        .string => |s| s,
        else => LoadError.InvalidFieldType,
    };
}

fn get_array(obj: std.json.ObjectMap, key: []const u8) LoadError!std.json.Array {
    const value = obj.get(key) orelse return LoadError.MissingField;
    return switch (value) {
        .array => |a| a,
        else => LoadError.InvalidFieldType,
    };
}

pub fn load(allocator: std.mem.Allocator, path: []const u8) !Data {
    std.debug.assert(path.len > 0);

    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    std.debug.assert(file_size <= max_file_size);

    const content = try file.readToEndAlloc(allocator, max_file_size);
    defer allocator.free(content);

    const parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch {
        return LoadError.InvalidJson;
    };
    defer parsed.deinit();

    const root = switch (parsed.value) {
        .object => |obj| obj,
        else => return LoadError.InvalidJson,
    };

    const header = Header{
        .seed = try get_u64(root, "seed"),
        .total_ticks = try get_u64(root, "total_ticks"),
        .max_ticks = try get_u64(root, "max_ticks"),
    };

    const events_arr = try get_array(root, "events");
    std.debug.assert(events_arr.items.len <= max_events);

    var events = try allocator.alloc(Event, events_arr.items.len);
    errdefer allocator.free(events);

    for (events_arr.items, 0..) |item, i| {
        const obj = switch (item) {
            .object => |o| o,
            else => return LoadError.InvalidJson,
        };

        const kind_str = try get_string(obj, "kind");
        const tick = try get_u64(obj, "tick");
        const keycode: u8 = @intCast(get_u64_optional(obj, "keycode", 0));
        const data: u32 = @intCast(get_u64_optional(obj, "data", 0));

        events[i] = .{
            .tick = tick,
            .kind = parse_kind(kind_str),
            .keycode = keycode,
            .data = data,
        };
    }

    var stats = Stats{};
    if (root.get("stats")) |stats_val| {
        if (stats_val == .array and stats_val.array.items.len > 0) {
            if (stats_val.array.items[0] == .object) {
                const s = stats_val.array.items[0].object;
                stats.key_events = get_u64_optional(s, "key_events", 0);
                stats.bindings_registered = @intCast(get_u64_optional(s, "bindings_registered", 0));
                stats.blocks = get_u64_optional(s, "blocks", 0);
                stats.allows = get_u64_optional(s, "allows", 0);
                stats.total_callbacks = get_u64_optional(s, "total_callbacks", 0);
                stats.timeouts_triggered = get_u64_optional(s, "timeouts_triggered", 0);
                stats.reinstall_attempts = get_u64_optional(s, "reinstall_attempts", 0);
                stats.stress_ticks = get_u64_optional(s, "stress_ticks", 0);
                stats.inputs_dropped = get_u64_optional(s, "inputs_dropped", 0);
                stats.max_queue_depth = get_u64_optional(s, "max_queue_depth", 0);
                stats.invariant_violations = get_u64_optional(s, "invariant_violations", 0);
                stats.passes = get_u64_optional(s, "passes", 0);
                stats.consumes = get_u64_optional(s, "consumes", 0);
                stats.replaces = get_u64_optional(s, "replaces", 0);
                stats.faults_injected = @intCast(get_u64_optional(s, "faults_injected", 0));
            }
        }
    }

    std.debug.assert(events.len == events_arr.items.len);

    return Data{
        .header = header,
        .events = events,
        .stats = stats,
    };
}

fn parse_kind(str: []const u8) Event.Kind {
    const map = std.StaticStringMap(Event.Kind).initComptime(.{
        .{ "key_down", .key_down },
        .{ "key_up", .key_up },
        .{ "binding_triggered", .binding_triggered },
        .{ "binding_blocked", .binding_blocked },
        .{ "binding_replaced", .binding_replaced },
        .{ "binding_registered", .binding_registered },
        .{ "binding_unregistered", .binding_unregistered },
        .{ "state_divergence", .state_divergence },
        .{ "tick", .tick },
        .{ "snapshot", .snapshot },
        .{ "fault_injected", .fault_injected },
        .{ "invariant_violated", .invariant_violated },
        .{ "blocked", .blocked },
        .{ "allowed", .allowed },
        .{ "hook_installed", .hook_installed },
        .{ "hook_removed", .hook_removed },
        .{ "timeout", .timeout },
        .{ "reinstall", .reinstall },
    });

    return map.get(str) orelse .unknown;
}

pub fn compute_stats_at_tick(events: []const Event, tick: u64) Stats {
    var stats = Stats{};

    for (events) |event| {
        if (event.tick > tick) {
            break;
        }

        switch (event.kind) {
            .key_down, .key_up => {
                stats.key_events += 1;
            },
            .binding_triggered, .allowed => {
                stats.allows += 1;
            },
            .binding_blocked, .binding_replaced, .blocked => {
                stats.blocks += 1;
            },
            .binding_registered => {
                stats.bindings_registered += 1;
            },
            .fault_injected => {
                stats.faults_injected += 1;
            },
            .invariant_violated => {
                stats.invariant_violations += 1;
            },
            .timeout => {
                stats.timeouts_triggered += 1;
            },
            .reinstall => {
                stats.reinstall_attempts += 1;
            },
            else => {},
        }
    }

    return stats;
}
