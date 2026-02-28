const std = @import("std");

const circular_mod = @import("../buffer/circular.zig");
const character = @import("../character.zig");
const keycode = @import("../keycode.zig");
const key_event = @import("../event/key.zig");
const response_mod = @import("../response.zig");
const base_mod = @import("base.zig");

const Key = key_event.Key;
const Response = response_mod.Response;

pub const name_max: u32 = 32;
pub const buffer_max: u32 = 128;
pub const capacity_default: u32 = 32;
pub const capacity_max: u32 = 128;

pub const Error = base_mod.BaseError || error{
    AlreadyRegistered,
    InvalidName,
};

pub const Callback = *const fn (context: *anyopaque, name: []const u8, args: []const u8) Response;

pub const Entry = struct {
    id: u32 = 0,
    callback: ?Callback = null,
    context: ?*anyopaque = null,
    active: bool = false,
    name: [name_max]u8 = undefined,
    name_len: u8 = 0,

    pub fn get_id(self: *const Entry) u32 {
        return self.id;
    }

    pub fn get_callback(self: *const Entry) ?Callback {
        return self.callback;
    }

    pub fn get_context(self: *const Entry) ?*anyopaque {
        return self.context;
    }

    pub fn is_active(self: *const Entry) bool {
        return self.active;
    }

    pub fn get_name(self: *const Entry) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn invoke(self: *Entry, name: []const u8, args: []const u8) ?Response {
        std.debug.assert(self.active);

        if (self.callback) |cb| {
            if (self.context) |ctx| {
                return cb(ctx, name, args);
            }
        }

        return null;
    }

    pub fn is_valid(self: *const Entry) bool {
        if (!self.active) {
            return true;
        }

        const id_valid = self.id >= 1;
        const callback_valid = self.callback != null;
        const context_valid = self.context != null;
        const name_valid = self.name_len > 0 and self.name_len <= name_max;

        return id_valid and callback_valid and context_valid and name_valid;
    }
};

pub fn CommandRegistry(comptime capacity: u8) type {
    const Buffer = circular_mod.CircularBuffer(buffer_max);

    return struct {
        const Self = @This();

        entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
        count: u8 = 0,
        next_id: u32 = 1,
        buffer: Buffer = Buffer.init(),
        trigger: u8 = ':',

        pub fn init() Self {
            return Self{};
        }

        pub fn is_valid(self: *const Self) bool {
            const count_valid = self.count <= capacity;
            const next_id_valid = self.next_id >= 1;
            const buffer_valid = self.buffer.is_valid();

            return count_valid and next_id_valid and buffer_valid;
        }

        pub fn register(
            self: *Self,
            name: []const u8,
            callback: Callback,
            context: anytype,
        ) Error!u32 {
            std.debug.assert(self.is_valid());

            if (name.len == 0 or name.len > name_max) {
                return error.InvalidName;
            }

            for (name) |c| {
                if (!std.ascii.isAlphanumeric(c) and c != '_') {
                    return error.InvalidName;
                }
            }

            for (&self.entries) |*entry| {
                if (entry.active and std.mem.eql(u8, entry.get_name(), name)) {
                    return error.AlreadyRegistered;
                }
            }

            const slot = self.find_empty_slot() orelse return error.RegistryFull;

            const id = self.next_id;
            self.next_id += 1;

            self.entries[slot] = Entry{
                .id = id,
                .callback = callback,
                .context = @ptrCast(@alignCast(context)),
                .active = true,
                .name = undefined,
                .name_len = @intCast(name.len),
            };

            @memcpy(self.entries[slot].name[0..name.len], name);

            self.count += 1;

            std.debug.assert(self.entries[slot].is_valid());

            return id;
        }

        pub fn unregister(self: *Self, id: u32) Error!void {
            std.debug.assert(id >= 1);

            for (&self.entries) |*entry| {
                if (entry.id == id and entry.active) {
                    entry.active = false;
                    self.count -= 1;
                    return;
                }
            }

            return error.NotFound;
        }

        pub fn process(self: *Self, key: *const Key) Response {
            std.debug.assert(self.is_valid());

            if (!key.down) {
                return .pass;
            }

            const c = character.from_keycode(key.value);

            if (c == 0) {
                if (key.value == keycode.back) {
                    _ = self.buffer.pop();
                }
                return .pass;
            }

            self.buffer.push(c);

            if (key.value == keycode.@"return") {
                const result = self.try_execute();
                self.buffer.clear();
                return result;
            }

            return .pass;
        }

        fn try_execute(self: *Self) Response {
            std.debug.assert(self.is_valid());

            const len = self.buffer.length();

            if (len < 2) {
                return .pass;
            }

            const first = self.buffer.get(0) orelse return .pass;

            if (first != self.trigger) {
                return .pass;
            }

            var name_end: u32 = 1;

            while (name_end < len) : (name_end += 1) {
                const c = self.buffer.get(name_end) orelse break;

                if (c == ' ' or c == '\r' or c == '\n') {
                    break;
                }
            }

            if (name_end <= 1) {
                return .pass;
            }

            var name_buf: [name_max]u8 = undefined;
            const name_len = name_end - 1;

            if (name_len > name_max) {
                return .pass;
            }

            for (0..name_len) |i| {
                name_buf[i] = self.buffer.get(@intCast(i + 1)) orelse return .pass;
            }

            const name = name_buf[0..name_len];

            var args_start = name_end;

            while (args_start < len) : (args_start += 1) {
                const c = self.buffer.get(args_start) orelse break;

                if (c != ' ') {
                    break;
                }
            }

            var args_buf: [buffer_max]u8 = undefined;
            var args_len: u32 = 0;

            var i = args_start;

            while (i < len and args_len < buffer_max) : (i += 1) {
                const c = self.buffer.get(i) orelse break;

                if (c == '\r' or c == '\n') {
                    break;
                }

                args_buf[args_len] = c;
                args_len += 1;
            }

            const args = args_buf[0..args_len];

            for (&self.entries) |*entry| {
                if (entry.active and std.mem.eql(u8, entry.get_name(), name)) {
                    if (entry.invoke(name, args)) |response| {
                        return response;
                    }
                }
            }

            return .pass;
        }

        fn find_empty_slot(self: *const Self) ?u8 {
            for (0..capacity) |i| {
                if (!self.entries[i].active) {
                    return @intCast(i);
                }
            }

            return null;
        }

        pub fn clear(self: *Self) void {
            for (&self.entries) |*entry| {
                entry.active = false;
            }

            self.count = 0;
            self.buffer.clear();
        }
    };
}
