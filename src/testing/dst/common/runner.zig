const std = @import("std");

const w32 = @import("win32").everything;

pub const iteration_max: u32 = 0xFFFFFFFF;
pub const arg_max: u32 = 256;

pub const ArgParser = struct {
    args: std.process.Args.Iterator,
    initialized: bool = false,

    pub fn init(args: std.process.Args, allocator: std.mem.Allocator) !ArgParser {
        var iterator = try args.iterateAllocator(allocator);
        _ = iterator.skip();

        const result = ArgParser{
            .args = iterator,
            .initialized = true,
        };

        std.debug.assert(result.initialized);

        return result;
    }

    pub fn is_valid(self: *const ArgParser) bool {
        const result = self.initialized;

        return result;
    }

    pub fn deinit(self: *ArgParser) void {
        std.debug.assert(self.is_valid());

        self.args.deinit();
        self.initialized = false;

        std.debug.assert(!self.initialized);
    }

    pub fn next(self: *ArgParser) ?[]const u8 {
        std.debug.assert(self.is_valid());

        const result = self.args.next();

        return result;
    }
};

pub fn parse_int_arg(comptime T: type, arg: []const u8, prefix: []const u8, default: T) T {
    std.debug.assert(prefix.len > 0);
    std.debug.assert(prefix.len <= arg_max);

    if (!std.mem.startsWith(u8, arg, prefix)) {
        return default;
    }

    std.debug.assert(arg.len >= prefix.len);

    const value_slice = arg[prefix.len..];
    const result = std.fmt.parseUnsigned(T, value_slice, 10) catch default;

    return result;
}

pub fn parse_string_arg(allocator: std.mem.Allocator, arg: []const u8, prefix: []const u8) ?[]u8 {
    std.debug.assert(prefix.len > 0);
    std.debug.assert(prefix.len <= arg_max);

    if (!std.mem.startsWith(u8, arg, prefix)) {
        return null;
    }

    std.debug.assert(arg.len >= prefix.len);

    const value_slice = arg[prefix.len..];
    const result = allocator.dupe(u8, value_slice) catch null;

    return result;
}

pub fn matches_flag(arg: []const u8, short: []const u8, long: []const u8) bool {
    std.debug.assert(short.len > 0);
    std.debug.assert(long.len > 0);
    std.debug.assert(short.len <= arg_max);
    std.debug.assert(long.len <= arg_max);

    const match_short = std.mem.eql(u8, arg, short);
    const match_long = std.mem.eql(u8, arg, long);
    const result = match_short or match_long;

    return result;
}

pub fn random_seed() u64 {
    var counter: w32.LARGE_INTEGER = undefined;

    if (w32.QueryPerformanceCounter(&counter) == 0) {
        const timestamp: u64 = w32.GetTickCount64();

        return timestamp;
    }

    const result: u64 = @bitCast(counter.QuadPart);

    std.debug.assert(@sizeOf(@TypeOf(result)) == 8);

    return result;
}

pub fn print_header(name: []const u8) void {
    std.debug.assert(name.len > 0);
    std.debug.assert(name.len <= arg_max);

    std.debug.print("{s}\n", .{name});
}

pub fn print_section(name: []const u8) void {
    std.debug.assert(name.len > 0);
    std.debug.assert(name.len <= arg_max);

    std.debug.print("\n{s}\n", .{name});
}

pub fn print_field(comptime name: []const u8, value: anytype) void {
    std.debug.assert(name.len > 0);
    std.debug.assert(name.len <= arg_max);

    const T = @TypeOf(value);

    switch (@typeInfo(T)) {
        .int, .comptime_int => std.debug.print("  {s}: {d}\n", .{ name, value }),
        .float, .comptime_float => std.debug.print("  {s}: {d:.2}\n", .{ name, value }),
        .bool => std.debug.print("  {s}: {}\n", .{ name, value }),
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                std.debug.print("  {s}: {s}\n", .{ name, value });
            } else {
                std.debug.print("  {s}: {any}\n", .{ name, value });
            }
        },
        .@"enum" => std.debug.print("  {s}: {s}\n", .{ name, @tagName(value) }),
        else => std.debug.print("  {s}: {any}\n", .{ name, value }),
    }
}

pub fn print_field_fmt(comptime name: []const u8, comptime fmt: []const u8, args: anytype) void {
    std.debug.assert(name.len > 0);
    std.debug.assert(fmt.len > 0);
    std.debug.assert(name.len <= arg_max);

    std.debug.print("  {s}: " ++ fmt ++ "\n", .{name} ++ args);
}

pub fn print_duration(start_time: i64, end_time: i64) void {
    std.debug.assert(end_time >= start_time);

    const duration_ms = end_time - start_time;

    std.debug.assert(duration_ms >= 0);

    std.debug.print("  Duration: {d}ms\n", .{duration_ms});
}

pub fn print_warning(comptime fmt: []const u8, args: anytype) void {
    std.debug.assert(fmt.len > 0);
    std.debug.assert(fmt.len <= arg_max);

    std.debug.print("\nWARNING: " ++ fmt ++ "\n", args);
}

pub fn print_reproduce_command(seed: u64, extra_args: []const u8) void {
    std.debug.assert(@intFromPtr(extra_args.ptr) != 0 or extra_args.len == 0);

    std.debug.print("\nReproduce with: --seed={d} {s}\n", .{ seed, extra_args });
}
