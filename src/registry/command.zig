const std = @import("std");

const buffer_mod = @import("../buffer/root.zig");
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
    name: [name_max]u8 = [_]u8{0} ** name_max,
    name_len: u32 = 0,
    active: bool = false,

    pub fn get_id(self: *const Entry) u32 {
        return self.id;
    }

    pub fn is_active(self: *const Entry) bool {
        return self.active;
    }

    pub fn is_valid(self: *const Entry) bool {
        if (!self.active) {
            return true;
        }

        return self.callback != null and self.name_len >= 1 and self.name_len <= name_max and self.id >= 1;
    }

    pub fn get_name(self: *const Entry) []const u8 {
        std.debug.assert(self.active);

        return self.name[0..self.name_len];
    }

    pub fn matches_name(self: *const Entry, name: []const u8) bool {
        std.debug.assert(self.active);

        if (name.len != self.name_len) {
            return false;
        }

        return std.mem.eql(u8, self.name[0..self.name_len], name);
    }
};

pub const ResolveResult = struct {
    name: []const u8,
    backspace_count: u32,
};

pub fn CommandRegistry(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("CommandRegistry capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("CommandRegistry capacity exceeds maximum");
    }

    return struct {
        const Self = @This();

        const RollingBuffer = buffer_mod.RollingBuffer(buffer_max);

        entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
        count: u32 = 0,
        id_next: u32 = 1,

        buffer: RollingBuffer = RollingBuffer.init(),

        prefix: u8 = ':',
        resolve_key: u8 = keycode.tab,
        cancel_key: u8 = keycode.escape,
        enabled: bool = true,

        last_backspace_count: u32 = 0,

        pub fn init() Self {
            return Self{};
        }

        pub fn is_valid(self: *const Self) bool {
            return self.buffer.is_valid() and self.resolve_key != self.cancel_key;
        }

        pub fn register(
            self: *Self,
            name: []const u8,
            callback: Callback,
            context: ?*anyopaque,
        ) Error!u32 {
            std.debug.assert(self.is_valid());

            if (name.len == 0 or name.len > name_max) {
                return error.InvalidName;
            }

            if (self.find_by_name(name) != null) {
                return error.AlreadyRegistered;
            }

            const slot = self.find_empty_slot() orelse return error.RegistryFull;

            self.entries[slot] = Entry{
                .id = self.id_next,
                .callback = callback,
                .context = context,
                .name = [_]u8{0} ** name_max,
                .name_len = @intCast(name.len),
                .active = true,
            };

            @memcpy(self.entries[slot].name[0..name.len], name);

            self.id_next += 1;
            self.count += 1;

            return self.entries[slot].id;
        }

        pub fn unregister(self: *Self, id: u32) Error!void {
            std.debug.assert(id >= 1);

            for (&self.entries) |*e| {
                if (e.active and e.id == id) {
                    e.active = false;
                    self.count -= 1;
                    return;
                }
            }

            return error.NotFound;
        }

        pub fn process(self: *Self, key: *const Key) ?Response {
            std.debug.assert(self.is_valid());

            if (!self.enabled or !key.down) {
                return null;
            }

            if (key.value == self.cancel_key) {
                self.reset();
                return null;
            }

            if (key.value == self.resolve_key) {
                return self.resolve();
            }

            if (self.invalidates_buffer(key)) {
                self.reset();
                return null;
            }

            if (key.value == keycode.back) {
                _ = self.buffer.pop();
                return null;
            }

            if (key.value == keycode.space) {
                self.buffer.push(' ');
                return null;
            }

            if (key.value == keycode.@"return") {
                self.buffer.push('\n');
                return null;
            }

            if (character.from_key(key)) |c| {
                self.buffer.push(c);
            }

            return null;
        }

        fn resolve(self: *Self) ?Response {
            if (self.buffer.is_empty()) {
                return null;
            }

            const result = self.find_command_at_end() orelse return null;

            self.last_backspace_count = result.backspace_count;

            self.reset();

            const entry = self.find_by_name(result.name) orelse return null;
            const callback = entry.callback orelse return null;
            const context = entry.context orelse return null;

            return callback(context, result.name, &[_]u8{});
        }

        fn find_command_at_end(self: *Self) ?ResolveResult {
            const text = self.buffer.slice();

            if (text.len == 0) {
                return null;
            }

            var prefix_pos: ?u32 = null;
            var i: u32 = @intCast(text.len);

            while (i > 0) {
                i -= 1;

                const c = text[i];

                if (character.is_whitespace(c)) {
                    break;
                }

                if (c == self.prefix) {
                    prefix_pos = i;
                    break;
                }
            }

            if (prefix_pos == null) {
                return null;
            }

            const cmd_start = prefix_pos.? + 1;

            if (cmd_start >= text.len) {
                return null;
            }

            const cmd_name = self.buffer.slice_from(cmd_start);

            if (cmd_name.len == 0 or cmd_name.len > name_max) {
                return null;
            }

            if (!self.is_registered(cmd_name)) {
                return null;
            }

            return ResolveResult{
                .name = cmd_name,
                .backspace_count = @intCast(text.len - prefix_pos.?),
            };
        }

        fn invalidates_buffer(self: *Self, key: *const Key) bool {
            _ = self;

            if (key.modifiers.ctrl() or key.modifiers.alt()) {
                return true;
            }

            return switch (key.value) {
                keycode.left, keycode.right, keycode.up, keycode.down => true,
                keycode.home, keycode.end, keycode.prior, keycode.next => true,
                keycode.insert, keycode.delete => true,
                else => false,
            };
        }

        fn reset(self: *Self) void {
            self.buffer.clear();
        }

        fn is_registered(self: *Self, name: []const u8) bool {
            return self.find_by_name(name) != null;
        }

        fn find_by_name(self: *Self, name: []const u8) ?*const Entry {
            for (&self.entries) |*e| {
                if (e.active and e.matches_name(name)) {
                    return e;
                }
            }

            return null;
        }

        fn find_empty_slot(self: *Self) ?u32 {
            for (self.entries, 0..) |e, i| {
                if (!e.active) {
                    return @intCast(i);
                }
            }

            return null;
        }

        pub fn get_last_backspace_count(self: *Self) u32 {
            return self.last_backspace_count;
        }

        pub fn set_enabled(self: *Self, value: bool) void {
            self.enabled = value;
        }

        pub fn set_prefix(self: *Self, char: u8) void {
            self.prefix = char;
        }

        pub fn set_resolve_key(self: *Self, value: u8) void {
            std.debug.assert(value != self.cancel_key);

            self.resolve_key = value;
        }

        pub fn clear(self: *Self) void {
            self.reset();

            for (&self.entries) |*e| {
                e.active = false;
            }

            self.count = 0;
        }
    };
}
