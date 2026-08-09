const Keycode = @import("../keycode.zig").Keycode;
const std = @import("std");

const base = @import("base.zig");
const entry_mod = @import("entry.zig");
const filter_mod = @import("../filter.zig");

const assert = std.debug.assert;

const WindowFilter = filter_mod.Active;

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
    base: entry_mod.FilteredEntryType(Callback, WindowFilter) = .{},
    pattern: [length_max]u8 = [_]u8{0} ** length_max,
    failure: [length_max]u32 = [_]u32{0} ** length_max,
    length: u32 = 0,
    position: u32 = 0,
    block_exempt: bool = false,

    pub fn get_id(entry: *const Entry) u32 {
        return entry.base.get_id();
    }

    pub fn get_callback(entry: *const Entry) ?Callback {
        return entry.base.get_callback();
    }

    pub fn get_context(entry: *const Entry) ?*anyopaque {
        return entry.base.get_context();
    }

    pub fn is_active(entry: *const Entry) bool {
        return entry.base.is_active();
    }

    pub fn matches_filter(entry: *const Entry) bool {
        return entry.base.matches_filter();
    }

    pub fn invoke(entry: *const Entry) void {
        assert(entry.is_active());

        if (entry.base.get_callback()) |cb| {
            if (entry.base.get_context()) |ctx| {
                cb(ctx);
            }
        }
    }

    pub fn is_valid(entry: *const Entry) bool {
        if (!entry.is_active()) {
            return true;
        }

        const valid_base = entry.base.is_valid();
        const valid_length = entry.length > 0 and entry.length <= length_max;
        const valid_position = entry.position <= entry.length;

        return valid_base and valid_length and valid_position;
    }

    pub fn push(entry: *Entry, value: Keycode) bool {
        assert(entry.is_active());
        assert(entry.length > 0);
        assert(entry.position < entry.length);

        if (!value.is_alpha()) {
            entry.position = 0;
            return false;
        }

        const upper = value.to_char().?;

        var position = entry.position;

        while (position > 0 and upper != entry.pattern[position]) {
            assert(position <= length_max);

            position = entry.failure[position - 1];
        }

        if (upper == entry.pattern[position]) {
            position += 1;
        }

        entry.position = position;

        if (entry.position == entry.length) {
            entry.position = 0;
            return true;
        }

        assert(entry.position < entry.length);

        return false;
    }

    pub fn reset(entry: *Entry) void {
        entry.position = 0;
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
    assert(pattern.len >= 1);
    assert(pattern.len <= length_max);

    failure[0] = 0;

    var prefix_len: u32 = 0;
    var i: u32 = 1;

    while (i < pattern.len) : (i += 1) {
        while (prefix_len > 0 and pattern[i] != pattern[prefix_len]) {
            assert(prefix_len <= length_max);

            prefix_len = failure[prefix_len - 1];
        }

        if (pattern[i] == pattern[prefix_len]) {
            prefix_len += 1;
        }

        failure[i] = prefix_len;

        assert(failure[i] <= i);
    }
}

pub fn SequenceRegistryType(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("SequenceRegistryType capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("SequenceRegistryType capacity exceeds maximum");
    }

    return struct {
        const Instance = @This();

        const Base = base.BaseRegistryType(Entry, capacity, .{
            .has_mutex = true,
        });

        base: Base = Base.init(),

        pub fn init() Instance {
            return Instance{};
        }

        pub fn is_valid(instance: *const Instance) bool {
            return instance.base.is_valid();
        }

        pub fn register(
            instance: *Instance,
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

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const allocation = instance.base.allocate_locked() catch return error.RegistryFull;

            assert(allocation.slot < capacity);
            assert(allocation.id >= 1);

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

            instance.base.slot.entries[allocation.slot] = entry;

            assert(instance.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(instance: *Instance, id: u32) Error!void {
            assert(id >= 1);

            _ = instance.base.free_by_id(id) catch return error.NotFound;
        }

        pub fn process(instance: *Instance, value: Keycode, blocked: bool) bool {
            var invocations: [capacity]Invocation = undefined;
            var invocation_count: u32 = 0;
            var matched = false;

            {
                instance.base.lock();
                defer instance.base.unlock();

                assert(instance.is_valid());

                const entries = instance.base.entries();

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

                        assert(invocation_count < capacity);

                        invocations[invocation_count] = Invocation{
                            .callback = callback,
                            .context = context,
                        };

                        invocation_count += 1;
                    }
                }
            }

            assert(invocation_count <= capacity);

            for (invocations[0..invocation_count]) |inv| {
                inv.callback(inv.context);
            }

            return matched;
        }

        pub fn reset(instance: *Instance) void {
            instance.base.lock();
            defer instance.base.unlock();

            const entries = instance.base.entries();

            for (entries) |*entry| {
                if (entry.is_active()) {
                    entry.reset();
                }
            }
        }

        pub fn clear(instance: *Instance) void {
            instance.base.lock();
            defer instance.base.unlock();

            instance.base.clear_locked();
        }
    };
}

const testing = std.testing;

fn noop_callback(_: *anyopaque) void {}

const CountContext = struct {
    count: u32 = 0,

    fn callback(context: *anyopaque) void {
        const self: *CountContext = @ptrCast(@alignCast(context));
        self.count += 1;
    }
};

test "registering a valid pattern stores it" {
    var reg = SequenceRegistryType(8).init();
    var context: u8 = 0;

    const id = try reg.register("abc", noop_callback, &context, .{});

    try testing.expect(id >= 1);
    try testing.expectEqual(@as(u32, 1), reg.base.count());
    try testing.expect(reg.is_valid());
}

test "an invalid character is an error and leaks no count" {
    var reg = SequenceRegistryType(4).init();
    var context: u8 = 0;

    const result = reg.register("a1b", noop_callback, &context, .{});

    try testing.expectError(error.InvalidCharacter, result);

    try testing.expectEqual(@as(u32, 0), reg.base.count());
    try testing.expect(reg.is_valid());
}

test "repeated invalid registers leave the capacity intact" {
    var reg = SequenceRegistryType(4).init();
    var context: u8 = 0;

    for (0..16) |_| {
        const result = reg.register("9", noop_callback, &context, .{});

        try testing.expectError(error.InvalidCharacter, result);
    }

    try testing.expectEqual(@as(u32, 0), reg.base.count());

    _ = try reg.register("aa", noop_callback, &context, .{});
    _ = try reg.register("bb", noop_callback, &context, .{});
    _ = try reg.register("cc", noop_callback, &context, .{});
    _ = try reg.register("dd", noop_callback, &context, .{});

    try testing.expectEqual(@as(u32, 4), reg.base.count());
    try testing.expectError(error.RegistryFull, reg.register("ee", noop_callback, &context, .{}));
}

test "a sequence matches its exact pattern" {
    var reg = SequenceRegistryType(4).init();
    var context = CountContext{};

    _ = try reg.register("abc", CountContext.callback, &context, .{});

    try testing.expect(!reg.process(.a, false));
    try testing.expect(!reg.process(.b, false));
    try testing.expect(reg.process(.c, false));
    try testing.expectEqual(@as(u32, 1), context.count);
}

test "the repeated prefix pattern AAB matches AAAB" {
    var reg = SequenceRegistryType(4).init();
    var context = CountContext{};

    _ = try reg.register("AAB", CountContext.callback, &context, .{});

    try testing.expect(!reg.process(.a, false));
    try testing.expect(!reg.process(.a, false));
    try testing.expect(!reg.process(.a, false));
    try testing.expect(reg.process(.b, false));
    try testing.expectEqual(@as(u32, 1), context.count);
}

test "the repeated prefix pattern AABAA matches overlapping input" {
    var reg = SequenceRegistryType(4).init();
    var context = CountContext{};

    _ = try reg.register("AABAA", CountContext.callback, &context, .{});

    try testing.expect(!reg.process(.a, false));
    try testing.expect(!reg.process(.a, false));
    try testing.expect(!reg.process(.a, false));
    try testing.expect(!reg.process(.b, false));
    try testing.expect(!reg.process(.a, false));
    try testing.expect(reg.process(.a, false));
    try testing.expectEqual(@as(u32, 1), context.count);
}

test "non alphabetic input resets sequence progress" {
    var reg = SequenceRegistryType(4).init();
    var context = CountContext{};

    _ = try reg.register("ab", CountContext.callback, &context, .{});

    try testing.expect(!reg.process(.a, false));
    try testing.expect(!reg.process(.digit_1, false));
    try testing.expect(!reg.process(.b, false));
    try testing.expectEqual(@as(u32, 0), context.count);
}
