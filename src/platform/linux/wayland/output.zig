const std = @import("std");

const client = @import("client.zig");
const wire = @import("wire.zig");

const assert = std.debug.assert;

pub const output_count_max: u8 = 16;
pub const name_bytes_max: u16 = 64;

pub const interface_output = "wl_output";
pub const interface_xdg_manager = "zxdg_output_manager_v1";

pub const opcode_manager_get_xdg_output: u16 = 1;

pub const event_output_geometry: u16 = 0;
pub const event_output_mode: u16 = 1;
pub const event_output_scale: u16 = 3;
pub const event_xdg_logical_position: u16 = 0;
pub const event_xdg_logical_size: u16 = 1;

pub const version_output: u32 = 2;
pub const version_xdg_manager: u32 = 2;

pub const Error = error{
    Unsupported,
} || client.Error;

pub const Output = struct {
    object: u32 = 0,
    xdg_object: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 0,
    height: i32 = 0,
    scale: i32 = 1,
    primary: bool = false,

    pub fn is_valid(output: *const Output) bool {
        return output.width >= 0 and output.height >= 0;
    }
};

pub const List = struct {
    outputs: [output_count_max]Output = @splat(.{}),
    count: u8 = 0,

    pub fn is_valid(list: *const List) bool {
        return list.count <= output_count_max;
    }

    pub fn find(list: *const List, object: u32) ?*const Output {
        assert(list.is_valid());

        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            if (list.outputs[index].object == object) {
                return &list.outputs[index];
            }
        }

        return null;
    }

    fn slot(list: *List, object: u32) ?*Output {
        assert(list.is_valid());

        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            if (list.outputs[index].object == object) {
                return &list.outputs[index];
            }
        }

        return null;
    }

    fn slot_by_xdg(list: *List, object: u32) ?*Output {
        var index: u8 = 0;

        while (index < list.count) : (index += 1) {
            if (list.outputs[index].xdg_object == object) {
                return &list.outputs[index];
            }
        }

        return null;
    }
};

comptime {
    assert(output_count_max > 0);
    assert(version_output >= 1);
}

pub fn enumerate(connection: *client.Connection, list: *List) Error!void {
    assert(list.count == 0);

    var index: u16 = 0;

    while (index < connection.global_count) : (index += 1) {
        const global = connection.globals[index];

        if (!global.matches(interface_output)) {
            continue;
        }

        if (list.count == output_count_max) {
            break;
        }

        const version = @min(global.version, version_output);
        const object = try connection.bind(global, version);

        list.outputs[list.count] = Output{
            .object = object,
            .primary = list.count == 0,
        };

        list.count += 1;
    }

    if (list.count == 0) {
        return Error.Unsupported;
    }

    try attach_logical(connection, list);
    try collect(connection, list);

    assert(list.is_valid());
}

fn attach_logical(connection: *client.Connection, list: *List) Error!void {
    const global = connection.find(interface_xdg_manager) orelse return;
    const version = @min(global.version, version_xdg_manager);
    const manager = try connection.bind(global, version);

    var index: u8 = 0;

    while (index < list.count) : (index += 1) {
        const id = connection.allocate_id();

        var writer = wire.Writer{};

        writer.begin(manager);
        writer.put_u32(id);
        writer.put_u32(list.outputs[index].object);
        writer.seal(opcode_manager_get_xdg_output);

        connection.send_raw(writer.finish()) catch return Error.WriteFailed;

        list.outputs[index].xdg_object = id;
    }

    assert(index == list.count);
}

fn collect(connection: *client.Connection, list: *List) Error!void {
    var reads: u16 = 0;

    while (reads < client.roundtrip_reads_max) : (reads += 1) {
        var buffer: [client.read_bytes_max]u8 = undefined;
        const size = connection.read_raw(&buffer) catch break;

        if (size == 0) {
            break;
        }

        absorb(list, buffer[0..size]);

        if (complete(list)) {
            break;
        }
    }

    assert(reads <= client.roundtrip_reads_max);
}

fn complete(list: *const List) bool {
    var index: u8 = 0;

    while (index < list.count) : (index += 1) {
        if (list.outputs[index].width == 0) {
            return false;
        }
    }

    return list.count > 0;
}

pub fn absorb(list: *List, bytes: []const u8) void {
    var reader = wire.Reader{ .bytes = bytes };

    while (reader.remaining() >= wire.header_bytes) {
        const header = reader.read_header() catch return;
        const body = header.size - wire.header_bytes;
        const start = reader.offset;

        apply(list, header, &reader);

        reader.offset = start;
        reader.skip(body) catch return;
    }
}

fn apply(list: *List, header: wire.Header, reader: *wire.Reader) void {
    if (list.slot(header.object)) |output| {
        apply_output(output, header.opcode, reader);

        return;
    }

    if (list.slot_by_xdg(header.object)) |output| {
        apply_logical(output, header.opcode, reader);
    }
}

fn apply_output(output: *Output, opcode: u16, reader: *wire.Reader) void {
    switch (opcode) {
        event_output_geometry => {
            output.x = reader.read_i32() catch return;
            output.y = reader.read_i32() catch return;
        },
        event_output_mode => {
            _ = reader.read_u32() catch return;

            output.width = reader.read_i32() catch return;
            output.height = reader.read_i32() catch return;
        },
        event_output_scale => {
            output.scale = reader.read_i32() catch return;
        },
        else => {},
    }
}

fn apply_logical(output: *Output, opcode: u16, reader: *wire.Reader) void {
    switch (opcode) {
        event_xdg_logical_position => {
            output.x = reader.read_i32() catch return;
            output.y = reader.read_i32() catch return;
        },
        event_xdg_logical_size => {
            output.width = reader.read_i32() catch return;
            output.height = reader.read_i32() catch return;
        },
        else => {},
    }
}

const testing = std.testing;

test "an empty list finds nothing and is valid" {
    const list = List{};

    try testing.expect(list.is_valid());
    try testing.expectEqual(@as(u8, 0), list.count);
    try testing.expect(list.find(7) == null);
}

test "wl_output mode events populate width and height" {
    var list = List{};

    list.outputs[0] = Output{ .object = 5 };
    list.count = 1;

    var writer = wire.Writer{};

    writer.begin(5);
    writer.put_u32(3);
    writer.put_i32(2560);
    writer.put_i32(1440);
    writer.put_i32(60000);
    writer.seal(event_output_mode);

    absorb(&list, writer.finish());

    try testing.expectEqual(@as(i32, 2560), list.outputs[0].width);
    try testing.expectEqual(@as(i32, 1440), list.outputs[0].height);
}

test "xdg_output logical size overrides the physical mode" {
    var list = List{};

    list.outputs[0] = Output{ .object = 5, .xdg_object = 9, .width = 3840, .height = 2160 };
    list.count = 1;

    var writer = wire.Writer{};

    writer.begin(9);
    writer.put_i32(1920);
    writer.put_i32(1080);
    writer.seal(event_xdg_logical_size);

    absorb(&list, writer.finish());

    try testing.expectEqual(@as(i32, 1920), list.outputs[0].width);
    try testing.expectEqual(@as(i32, 1080), list.outputs[0].height);
}

test "geometry events populate position" {
    var list = List{};

    list.outputs[0] = Output{ .object = 5 };
    list.count = 1;

    var writer = wire.Writer{};

    writer.begin(5);
    writer.put_i32(1920);
    writer.put_i32(0);
    writer.put_i32(600);
    writer.put_i32(340);
    writer.put_i32(0);
    writer.seal(event_output_geometry);

    absorb(&list, writer.finish());

    try testing.expectEqual(@as(i32, 1920), list.outputs[0].x);
    try testing.expectEqual(@as(i32, 0), list.outputs[0].y);
}

test "completion requires every output to have a mode" {
    var list = List{};

    list.outputs[0] = Output{ .object = 5, .width = 1920, .height = 1080 };
    list.outputs[1] = Output{ .object = 6 };
    list.count = 2;

    try testing.expect(!complete(&list));

    list.outputs[1].width = 2560;

    try testing.expect(complete(&list));
}
