const std = @import("std");

const format = @import("format.zig");

pub const Format = format.Format;
pub const JsonWriter = format.JsonWriter;
pub const BinaryWriter = format.BinaryWriter;
pub const BinaryReader = format.BinaryReader;

pub const file_size_max: u32 = 100 * 1024 * 1024;
pub const iteration_max: u32 = 0xFFFFFFFF;

pub fn Header(comptime magic: *const [4]u8, comptime Extra: type) type {
    return extern struct {
        const Self = @This();

        magic: [4]u8 = magic.*,
        version: u32 = 1,
        seed: u64,
        max_ticks: u64,
        total_ticks: u64,
        event_count: u32,
        extra: Extra,

        pub fn is_valid(self: *const Self) bool {
            std.debug.assert(@intFromPtr(self) != 0);

            const valid_magic = std.mem.eql(u8, &self.magic, magic);
            const valid_version = self.version == 1;
            const result = valid_magic and valid_version;

            return result;
        }

        pub fn validate(self: *const Self) !void {
            std.debug.assert(@intFromPtr(self) != 0);

            if (!std.mem.eql(u8, &self.magic, magic)) {
                return error.InvalidMagic;
            }

            if (self.version != 1) {
                return error.UnsupportedVersion;
            }

            std.debug.assert(self.is_valid());
        }
    };
}

pub fn Recorder(comptime BufferType: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        buffer: BufferType,
        selected_format: Format,

        pub fn init(allocator: std.mem.Allocator, fmt: Format) Self {
            std.debug.assert(@intFromPtr(&allocator.vtable) != 0);
            std.debug.assert(fmt.is_valid());

            const result = Self{
                .allocator = allocator,
                .buffer = .{},
                .selected_format = fmt,
            };

            std.debug.assert(result.is_valid());
            std.debug.assert(result.selected_format.is_valid());

            return result;
        }

        pub fn is_valid(self: *const Self) bool {
            std.debug.assert(@intFromPtr(self) != 0);

            const result = self.selected_format.is_valid();

            return result;
        }

        pub fn deinit(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.buffer.deinit(self.allocator);
        }

        pub fn reset(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.buffer.shrinkRetainingCapacity(0);

            std.debug.assert(self.buffer.items.len == 0);
            std.debug.assert(self.is_valid());
        }

        pub fn writer(self: *Self) BufferType.Writer {
            std.debug.assert(self.is_valid());

            const result = self.buffer.writer(self.allocator);

            return result;
        }

        pub fn json_writer(self: *Self) JsonWriter(BufferType.Writer) {
            std.debug.assert(self.is_valid());

            const result = JsonWriter(BufferType.Writer).init(self.writer());

            return result;
        }

        pub fn binary_writer(self: *Self) BinaryWriter(BufferType.Writer) {
            std.debug.assert(self.is_valid());

            const result = BinaryWriter(BufferType.Writer).init(self.writer());

            return result;
        }

        pub fn get_data(self: *const Self) []const u8 {
            std.debug.assert(self.is_valid());

            const result = self.buffer.items;

            std.debug.assert(@intFromPtr(result.ptr) != 0 or result.len == 0);

            return result;
        }

        pub fn to_owned_slice(self: *Self) ![]u8 {
            std.debug.assert(self.is_valid());

            const result = try self.buffer.toOwnedSlice(self.allocator);

            std.debug.assert(@intFromPtr(result.ptr) != 0 or result.len == 0);

            return result;
        }

        pub fn write_to_file(self: *const Self, path: []const u8) !void {
            std.debug.assert(self.is_valid());
            std.debug.assert(path.len > 0);

            const file = try std.fs.cwd().createFile(path, .{});
            defer file.close();

            try file.writeAll(self.buffer.items);
        }
    };
}

pub fn Recording(comptime HeaderType: type, comptime EventType: type, comptime ExtraData: type) type {
    return struct {
        const Self = @This();

        allocator: std.mem.Allocator,
        header: HeaderType,
        events: []EventType,
        extra: ExtraData,

        pub fn is_valid(self: *const Self) bool {
            std.debug.assert(@intFromPtr(self) != 0);

            const valid_header = self.header.is_valid();
            const valid_events = @intFromPtr(self.events.ptr) != 0 or self.events.len == 0;
            const result = valid_header and valid_events;

            return result;
        }

        pub fn deinit(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.allocator.free(self.events);

            if (@hasDecl(ExtraData, "deinit")) {
                self.extra.deinit(self.allocator);
            }
        }

        pub fn load_from_file(allocator: std.mem.Allocator, path: []const u8) !Self {
            std.debug.assert(@intFromPtr(&allocator.vtable) != 0);
            std.debug.assert(path.len > 0);

            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();

            const data = try file.readToEndAlloc(allocator, file_size_max);
            defer allocator.free(data);

            std.debug.assert(data.len > 0);

            const result = try load_from_binary(allocator, data);

            std.debug.assert(result.is_valid());

            return result;
        }

        pub fn load_from_binary(allocator: std.mem.Allocator, data: []const u8) !Self {
            std.debug.assert(@intFromPtr(&allocator.vtable) != 0);
            std.debug.assert(data.len > 0);

            var stream = std.io.fixedBufferStream(data);
            const reader = stream.reader();
            var bin_reader = BinaryReader(@TypeOf(reader)).init(reader);

            const header = try bin_reader.read_struct(HeaderType);
            try header.validate();

            std.debug.assert(header.is_valid());

            const events = try allocator.alloc(EventType, header.event_count);
            errdefer allocator.free(events);

            const stored_count = try bin_reader.read_int(u32);

            std.debug.assert(stored_count == header.event_count);

            var i: u32 = 0;

            while (i < events.len and i < iteration_max) : (i += 1) {
                std.debug.assert(i < events.len);

                events[i] = try read_event(EventType, &bin_reader);
            }

            std.debug.assert(i == events.len or i == iteration_max);

            const extra = if (@hasDecl(ExtraData, "read"))
                try ExtraData.read(allocator, &bin_reader)
            else
                ExtraData{};

            const result = Self{
                .allocator = allocator,
                .header = header,
                .events = events,
                .extra = extra,
            };

            std.debug.assert(result.is_valid());

            return result;
        }

        fn read_event(comptime E: type, bin_reader: anytype) !E {
            std.debug.assert(@intFromPtr(bin_reader) != 0);

            if (@hasDecl(E, "read")) {
                const result = try E.read(bin_reader);

                return result;
            }

            const result = try bin_reader.read_struct(E);

            return result;
        }

        pub fn get_event_at_tick(self: *const Self, target_tick: u64) ?*const EventType {
            std.debug.assert(self.is_valid());

            var i: u32 = 0;

            while (i < self.events.len and i < iteration_max) : (i += 1) {
                std.debug.assert(i < self.events.len);

                if (self.events[i].tick == target_tick) {
                    const result = &self.events[i];

                    std.debug.assert(@intFromPtr(result) != 0);

                    return result;
                }
            }

            std.debug.assert(i == self.events.len or i == iteration_max);

            return null;
        }

        pub fn get_events_in_range(self: *const Self, start: u64, end: u64) []const EventType {
            std.debug.assert(self.is_valid());
            std.debug.assert(end >= start);

            var start_idx: usize = self.events.len;
            var end_idx: usize = 0;
            var i: u32 = 0;

            while (i < self.events.len and i < iteration_max) : (i += 1) {
                std.debug.assert(i < self.events.len);

                const event = self.events[i];

                if (event.tick >= start and start_idx == self.events.len) {
                    start_idx = i;
                }

                if (event.tick <= end) {
                    end_idx = i + 1;
                }
            }

            std.debug.assert(i == self.events.len or i == iteration_max);

            if (start_idx >= end_idx) {
                return &[_]EventType{};
            }

            std.debug.assert(start_idx < end_idx);
            std.debug.assert(end_idx <= self.events.len);

            const result = self.events[start_idx..end_idx];

            return result;
        }
    };
}
