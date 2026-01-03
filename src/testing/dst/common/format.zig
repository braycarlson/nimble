const std = @import("std");

pub const iteration_max: u32 = 0xFFFFFFFF;

pub const Format = enum(u8) {
    binary = 0,
    json = 1,

    pub fn is_valid(self: Format) bool {
        const value = @intFromEnum(self);

        const result = value <= 1;

        return result;
    }
};

pub fn BinaryWriter(comptime Writer: type) type {
    return struct {
        const Self = @This();

        writer: Writer,

        pub fn init(writer: Writer) Self {
            const result = Self{ .writer = writer };

            std.debug.assert(@intFromPtr(&result.writer) != 0);

            return result;
        }

        pub fn is_valid(self: *const Self) bool {
            std.debug.assert(@intFromPtr(self) != 0);

            const result = @intFromPtr(&self.writer) != 0;

            return result;
        }

        pub fn write_struct(self: *Self, value: anytype) !void {
            std.debug.assert(self.is_valid());
            std.debug.assert(@sizeOf(@TypeOf(value)) > 0);

            try self.writer.writeAll(std.mem.asBytes(&value));
        }

        pub fn write_int(self: *Self, comptime T: type, value: T) !void {
            std.debug.assert(self.is_valid());
            std.debug.assert(@sizeOf(T) > 0);

            try self.writer.writeInt(T, value, .little);
        }

        pub fn write_byte(self: *Self, value: u8) !void {
            std.debug.assert(self.is_valid());
            std.debug.assert(value <= 255);

            try self.writer.writeByte(value);
        }

        pub fn write_all(self: *Self, bytes: []const u8) !void {
            std.debug.assert(self.is_valid());
            std.debug.assert(@intFromPtr(bytes.ptr) != 0 or bytes.len == 0);

            try self.writer.writeAll(bytes);
        }
    };
}

pub fn BinaryReader(comptime Reader: type) type {
    return struct {
        const Self = @This();

        reader: Reader,

        pub fn init(reader: Reader) Self {
            const result = Self{ .reader = reader };

            std.debug.assert(@intFromPtr(&result.reader) != 0);

            return result;
        }

        pub fn is_valid(self: *const Self) bool {
            std.debug.assert(@intFromPtr(self) != 0);

            const result = @intFromPtr(&self.reader) != 0;

            return result;
        }

        pub fn read_struct(self: *Self, comptime T: type) !T {
            std.debug.assert(self.is_valid());
            std.debug.assert(@sizeOf(T) > 0);

            const result = try self.reader.readStruct(T);

            return result;
        }

        pub fn read_int(self: *Self, comptime T: type) !T {
            std.debug.assert(self.is_valid());
            std.debug.assert(@sizeOf(T) > 0);

            const result = try self.reader.readInt(T, .little);

            return result;
        }

        pub fn read_byte(self: *Self) !u8 {
            std.debug.assert(self.is_valid());

            const result = try self.reader.readByte();

            std.debug.assert(result <= 255);

            return result;
        }
    };
}
