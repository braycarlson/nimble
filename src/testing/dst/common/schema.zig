const std = @import("std");

pub const field_capacity: u32 = 64;
pub const iteration_max: u32 = 0xFFFFFFFF;

pub const Field = struct {
    id: []const u8,
    label: []const u8,
    color: []const u8,

    pub fn is_valid(self: *const Field) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_id = self.id.len > 0;
        const valid_label = self.label.len > 0;
        const valid_color = self.color.len > 0;
        const result = valid_id and valid_label and valid_color;

        return result;
    }
};

pub fn StatsPrinter(comptime json_data: []const u8) type {
    @setEvalBranchQuota(10000);
    const fields = comptime parse_fields(json_data);

    return struct {
        pub const field_count = fields.len;

        pub fn get_field(comptime index: usize) Field {
            std.debug.assert(index < field_count);

            const result = fields[index];

            std.debug.assert(result.id.len > 0);
            std.debug.assert(result.label.len > 0);
            std.debug.assert(result.color.len > 0);

            return result;
        }

        pub fn print(values: [field_count]u64) void {
            comptime var field_index: usize = 0;

            inline while (field_index < field_count) : (field_index += 1) {
                const field = comptime get_field(field_index);

                std.debug.print("  {s}: {d}\n", .{ field.label, values[field_index] });
            }
        }

        pub fn print_section(name: []const u8, values: [field_count]u64) void {
            std.debug.assert(name.len > 0);
            std.debug.assert(name.len <= iteration_max);

            std.debug.print("\n{s}\n", .{name});
            print(values);
        }
    };
}

fn parse_fields(comptime json: []const u8) []const Field {
    @setEvalBranchQuota(10000);

    comptime {
        var fields: []const Field = &.{};
        var pos: usize = 0;
        var iteration: usize = 0;

        while (iteration < field_capacity) : (iteration += 1) {
            if (pos >= json.len) {
                break;
            }

            const id_start = find_string(json, pos, "\"id\"");

            if (id_start == null) {
                break;
            }

            const id = extract_string(json, id_start.?);

            const label_start = find_string(json, id_start.?, "\"label\"");

            if (label_start == null) {
                continue;
            }

            const label = extract_string(json, label_start.?);

            const color_start = find_string(json, label_start.?, "\"color\"");

            if (color_start == null) {
                continue;
            }

            const color = extract_string(json, color_start.?);

            fields = fields ++ &[_]Field{.{
                .id = id,
                .label = label,
                .color = color,
            }};

            pos = color_start.? + color.len;
        }

        return fields;
    }
}

fn find_string(comptime json: []const u8, comptime start: usize, comptime needle: []const u8) ?usize {
    @setEvalBranchQuota(10000);

    comptime {
        var pos: usize = start;
        var iteration: usize = 0;

        while (iteration < iteration_max) : (iteration += 1) {
            if (pos + needle.len > json.len) {
                break;
            }

            if (std.mem.eql(u8, json[pos..][0..needle.len], needle)) {
                const result = pos + needle.len;

                return result;
            }

            pos += 1;
        }

        return null;
    }
}

fn extract_string(comptime json: []const u8, comptime after_key: usize) []const u8 {
    comptime {
        var pos: usize = after_key;
        var iteration: usize = 0;

        while (iteration < iteration_max) : (iteration += 1) {
            if (pos >= json.len) {
                break;
            }

            if (json[pos] == '"') {
                break;
            }

            pos += 1;
        }

        pos += 1;

        const start = pos;

        iteration = 0;

        while (iteration < iteration_max) : (iteration += 1) {
            if (pos >= json.len) {
                break;
            }

            if (json[pos] == '"') {
                break;
            }

            pos += 1;
        }

        const result = json[start..pos];

        return result;
    }
}
