const std = @import("std");

const base = @import("base.zig");
const entry_mod = @import("entry.zig");
const filter_mod = @import("../filter.zig");

const WindowFilter = filter_mod.WindowFilter;

pub const length_max: u32 = 16;
pub const capacity_default: u32 = 8;
pub const capacity_max: u32 = 32;

pub const Error = base.BaseError || error{
    SequenceEmpty,
    SequenceTooLong,
    InvalidCharacter,
};

pub const Callback = *const fn (context: *anyopaque) void;

pub const Entry = struct {
    base: entry_mod.FilteredEntry(Callback, WindowFilter) = .{},
    pattern: [length_max]u8 = [_]u8{0} ** length_max,
    failure: [length_max]u32 = [_]u32{0} ** length_max,
    length: u32 = 0,
    position: u32 = 0,
    block_exempt: bool = false,

    pub fn get_id(self: *const Entry) u32 {
        return self.base.get_id();
    }

    pub fn get_callback(self: *const Entry) ?Callback {
        return self.base.get_callback();
    }

    pub fn get_context(self: *const Entry) ?*anyopaque {
        return self.base.get_context();
    }

    pub fn is_active(self: *const Entry) bool {
        return self.base.is_active();
    }

    pub fn matches_filter(self: *const Entry) bool {
        return self.base.matches_filter();
    }

    pub fn invoke(self: *const Entry) void {
        std.debug.assert(self.is_active());

        if (self.base.get_callback()) |cb| {
            if (self.base.get_context()) |ctx| {
                cb(ctx);
            }
        }
    }

    pub fn is_valid(self: *const Entry) bool {
        if (!self.is_active()) {
            return true;
        }

        const valid_base = self.base.is_valid();
        const valid_length = self.length > 0 and self.length <= length_max;
        const valid_position = self.position <= self.length;

        return valid_base and valid_length and valid_position;
    }

    pub fn push(self: *Entry, value: u8) bool {
        std.debug.assert(self.is_active());
        std.debug.assert(self.length > 0);
        std.debug.assert(self.position < self.length);

        const upper = std.ascii.toUpper(value);

        if (upper < 'A' or upper > 'Z') {
            self.position = 0;
            return false;
        }

        var position = self.position;

        while (position > 0 and upper != self.pattern[position]) {
            std.debug.assert(position <= length_max);

            position = self.failure[position - 1];
        }

        if (upper == self.pattern[position]) {
            position += 1;
        }

        self.position = position;

        if (self.position == self.length) {
            self.position = 0;
            return true;
        }

        std.debug.assert(self.position < self.length);

        return false;
    }

    pub fn reset(self: *Entry) void {
        self.position = 0;
    }
};

pub const Options = struct {
    filter: WindowFilter = .{},
    block_exempt: bool = false,
};

const Invocation = struct {
    callback: Callback,
    context: *anyopaque,
};

fn failure_compute(pattern: []const u8, failure: *[length_max]u32) void {
    std.debug.assert(pattern.len >= 1);
    std.debug.assert(pattern.len <= length_max);

    failure[0] = 0;

    var prefix_len: u32 = 0;
    var i: u32 = 1;

    while (i < pattern.len) : (i += 1) {
        while (prefix_len > 0 and pattern[i] != pattern[prefix_len]) {
            std.debug.assert(prefix_len <= length_max);

            prefix_len = failure[prefix_len - 1];
        }

        if (pattern[i] == pattern[prefix_len]) {
            prefix_len += 1;
        }

        failure[i] = prefix_len;

        std.debug.assert(failure[i] <= i);
    }
}

pub fn SequenceRegistry(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("SequenceRegistry capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("SequenceRegistry capacity exceeds maximum");
    }

    return struct {
        const Self = @This();

        const Base = base.BaseRegistry(Entry, capacity, .{
            .has_mutex = true,
        });

        base: Base = Base.init(),

        pub fn init() Self {
            return Self{};
        }

        pub fn is_valid(self: *const Self) bool {
            return self.base.is_valid();
        }

        pub fn register(
            self: *Self,
            pattern: []const u8,
            callback: Callback,
            context: ?*anyopaque,
            options: Options,
        ) Error!u32 {
            if (pattern.len == 0) {
                return error.SequenceEmpty;
            }

            if (pattern.len > length_max) {
                return error.SequenceTooLong;
            }

            for (pattern) |char| {
                const upper = std.ascii.toUpper(char);

                if (upper < 'A' or upper > 'Z') {
                    return error.InvalidCharacter;
                }
            }

            self.base.lock();
            defer self.base.unlock();

            std.debug.assert(self.is_valid());

            const allocation = self.base.allocate_locked() catch return error.RegistryFull;

            std.debug.assert(allocation.slot < capacity);
            std.debug.assert(allocation.id >= 1);

            var entry = Entry{
                .base = .{
                    .base = .{
                        .id = allocation.id,
                        .callback = callback,
                        .context = context,
                        .active = true,
                    },
                    .filter = options.filter,
                },
                .length = @intCast(pattern.len),
                .block_exempt = options.block_exempt,
            };

            for (pattern, 0..) |char, i| {
                entry.pattern[i] = std.ascii.toUpper(char);
            }

            failure_compute(entry.pattern[0..entry.length], &entry.failure);

            self.base.slot.entries[allocation.slot] = entry;

            std.debug.assert(self.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(self: *Self, id: u32) Error!void {
            std.debug.assert(id >= 1);

            _ = self.base.free_by_id(id) catch return error.NotFound;
        }

        pub fn process(self: *Self, value: u8, blocked: bool) bool {
            var invocations: [capacity]Invocation = undefined;
            var invocation_count: u32 = 0;
            var matched = false;

            {
                self.base.lock();
                defer self.base.unlock();

                std.debug.assert(self.is_valid());

                const entries = self.base.entries();

                for (entries) |*entry| {
                    if (!entry.is_active()) {
                        continue;
                    }

                    if (blocked and !entry.block_exempt) {
                        continue;
                    }

                    if (!entry.matches_filter()) {
                        continue;
                    }

                    if (entry.push(value)) {
                        matched = true;

                        const callback = entry.get_callback() orelse continue;
                        const context = entry.get_context() orelse continue;

                        std.debug.assert(invocation_count < capacity);

                        invocations[invocation_count] = Invocation{
                            .callback = callback,
                            .context = context,
                        };
                        invocation_count += 1;
                    }
                }
            }

            std.debug.assert(invocation_count <= capacity);

            for (invocations[0..invocation_count]) |inv| {
                inv.callback(inv.context);
            }

            return matched;
        }

        pub fn reset(self: *Self) void {
            self.base.lock();
            defer self.base.unlock();

            const entries = self.base.entries();

            for (entries) |*entry| {
                if (entry.is_active()) {
                    entry.reset();
                }
            }
        }

        pub fn clear(self: *Self) void {
            self.base.lock();
            defer self.base.unlock();

            self.base.clear_locked();
        }
    };
}
