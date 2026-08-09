const std = @import("std");

const base = @import("base.zig");
const character = @import("../character.zig");
const circular = @import("../buffer/circular.zig");
const key_event = @import("../event/key.zig");
const keycode = @import("../keycode.zig");
const response_mod = @import("../response.zig");

const Mutex = @import("../sync.zig").Mutex;
const assert = std.debug.assert;
const Keycode = keycode.Keycode;
const Key = key_event.Key;
const Response = response_mod.Response;

pub const name_max: u32 = 32;
pub const buffer_max: u32 = 128;
pub const capacity_default: u32 = 32;
pub const capacity_max: u32 = 128;

pub const Error = base.BaseError || error{
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

    pub fn get_id(entry: *const Entry) u32 {
        return entry.id;
    }

    pub fn get_callback(entry: *const Entry) ?Callback {
        return entry.callback;
    }

    pub fn get_context(entry: *const Entry) ?*anyopaque {
        return entry.context;
    }

    pub fn is_active(entry: *const Entry) bool {
        return entry.active;
    }

    pub fn get_name(entry: *const Entry) []const u8 {
        assert(entry.name_len <= name_max);

        return entry.name[0..entry.name_len];
    }

    pub fn invoke(entry: *Entry, name: []const u8, args: []const u8) ?Response {
        assert(entry.active);

        if (entry.callback) |cb| {
            if (entry.context) |ctx| {
                return cb(ctx, name, args);
            }
        }

        return null;
    }

    pub fn is_valid(entry: *const Entry) bool {
        if (!entry.active) {
            return true;
        }

        const id_valid = entry.id >= 1;
        const callback_valid = entry.callback != null;
        const context_valid = entry.context != null;
        const name_valid = entry.name_len > 0 and entry.name_len <= name_max;

        return id_valid and callback_valid and context_valid and name_valid;
    }
};

const Invocation = struct {
    callback: Callback,
    context: *anyopaque,
    name: [name_max]u8,
    name_len: u8,
    args: [buffer_max]u8,
    args_len: u32,
};

const NameScan = struct {
    len: u8,
    end: u32,
};

pub fn CommandRegistryType(comptime capacity: u8) type {
    const Buffer = circular.CircularBufferType(buffer_max);

    return struct {
        const Instance = @This();

        entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
        count: u8 = 0,
        next_id: u32 = 1,
        buffer: Buffer = Buffer.init(),
        trigger: u8 = ':',
        enabled: bool = true,
        mutex: Mutex = .{},

        pub fn init() Instance {
            return Instance{};
        }

        pub fn is_valid(instance: *const Instance) bool {
            const count_valid = instance.count <= capacity;
            const next_id_valid = instance.next_id >= 1;
            const buffer_valid = instance.buffer.is_valid();

            return count_valid and next_id_valid and buffer_valid;
        }

        pub fn register(
            instance: *Instance,
            name: []const u8,
            callback: Callback,
            context: anytype,
        ) Error!u32 {
            if (name.len == 0 or name.len > name_max) {
                return error.InvalidName;
            }

            for (name) |c| {
                if (!std.ascii.isAlphanumeric(c) and c != '_') {
                    return error.InvalidName;
                }
            }

            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.is_valid());

            for (&instance.entries) |*entry| {
                if (entry.active and std.mem.eql(u8, entry.get_name(), name)) {
                    return error.AlreadyRegistered;
                }
            }

            const slot = instance.find_empty_slot() orelse return error.RegistryFull;

            const id = instance.next_id;
            instance.next_id += 1;

            instance.entries[slot] = Entry{
                .id = id,
                .callback = callback,
                .context = @ptrCast(@alignCast(context)),
                .active = true,
                .name = undefined,
                .name_len = @intCast(name.len),
            };

            @memcpy(instance.entries[slot].name[0..name.len], name);

            instance.count += 1;

            assert(instance.entries[slot].is_valid());

            return id;
        }

        pub fn unregister(instance: *Instance, id: u32) Error!void {
            assert(id >= 1);

            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.is_valid());

            for (&instance.entries) |*entry| {
                if (entry.id == id and entry.active) {
                    entry.active = false;
                    instance.count -= 1;
                    return;
                }
            }

            return error.NotFound;
        }

        pub fn process(instance: *Instance, key: *const Key) Response {
            assert(key.is_valid());

            const invocation = blk: {
                instance.mutex.lock();
                defer instance.mutex.unlock();

                assert(instance.is_valid());

                break :blk instance.process_locked(key);
            };

            if (invocation) |inv| {
                assert(inv.name_len >= 1);
                assert(inv.args_len <= buffer_max);

                const name = inv.name[0..inv.name_len];
                const args = inv.args[0..inv.args_len];

                return inv.callback(inv.context, name, args);
            }

            return .pass;
        }

        fn process_locked(instance: *Instance, key: *const Key) ?Invocation {
            assert(instance.is_valid());
            assert(key.is_valid());

            if (!instance.enabled) {
                return null;
            }

            if (!key.down) {
                return null;
            }

            const c = character.from_keycode(key.value);

            if (c == 0) {
                if (key.value == Keycode.backspace) {
                    _ = instance.buffer.pop();
                }
                return null;
            }

            if (instance.buffer.length() >= buffer_max - 1) {
                instance.buffer.clear();
                return null;
            }

            instance.buffer.push(c);

            if (key.value == Keycode.enter) {
                const invocation = instance.try_execute_locked();
                instance.buffer.clear();
                return invocation;
            }

            return null;
        }

        fn try_execute_locked(instance: *Instance) ?Invocation {
            assert(instance.is_valid());

            const len = instance.buffer.length();

            if (len < 2) {
                return null;
            }

            const first = instance.buffer.get(0) orelse return null;

            if (first != instance.trigger) {
                return null;
            }

            var name_buf: [name_max]u8 = undefined;
            const name_scan = instance.scan_name_locked(&name_buf) orelse return null;

            var args_buf: [buffer_max]u8 = undefined;
            const args_len = instance.scan_args_locked(name_scan.end, &args_buf);

            assert(name_scan.len >= 1);
            assert(args_len <= buffer_max);

            const name = name_buf[0..name_scan.len];

            for (&instance.entries) |*entry| {
                if (!entry.active) {
                    continue;
                }

                if (!std.mem.eql(u8, entry.get_name(), name)) {
                    continue;
                }

                const callback = entry.callback orelse continue;
                const context = entry.context orelse continue;

                return Invocation{
                    .callback = callback,
                    .context = context,
                    .name = name_buf,
                    .name_len = name_scan.len,
                    .args = args_buf,
                    .args_len = args_len,
                };
            }

            return null;
        }

        fn scan_name_locked(instance: *Instance, name_out: *[name_max]u8) ?NameScan {
            const len = instance.buffer.length();

            assert(len >= 2);

            var name_end: u32 = 1;

            while (name_end < len) : (name_end += 1) {
                const c = instance.buffer.get(name_end) orelse break;

                if (c == ' ' or c == '\r' or c == '\n') {
                    break;
                }
            }

            if (name_end <= 1) {
                return null;
            }

            const name_len = name_end - 1;

            if (name_len > name_max) {
                return null;
            }

            for (0..name_len) |i| {
                name_out[i] = instance.buffer.get(@intCast(i + 1)) orelse return null;
            }

            assert(name_len <= name_max);

            return NameScan{
                .len = @intCast(name_len),
                .end = name_end,
            };
        }

        fn scan_args_locked(instance: *Instance, name_end: u32, args_out: *[buffer_max]u8) u32 {
            const len = instance.buffer.length();

            assert(name_end <= len);

            var args_start = name_end;

            while (args_start < len) : (args_start += 1) {
                const c = instance.buffer.get(args_start) orelse break;

                if (c != ' ') {
                    break;
                }
            }

            var args_len: u32 = 0;
            var i = args_start;

            while (i < len and args_len < buffer_max) : (i += 1) {
                const c = instance.buffer.get(i) orelse break;

                if (c == '\r' or c == '\n') {
                    break;
                }

                args_out[args_len] = c;
                args_len += 1;
            }

            assert(args_len <= buffer_max);

            return args_len;
        }

        fn find_empty_slot(instance: *const Instance) ?u8 {
            for (0..capacity) |i| {
                if (!instance.entries[i].active) {
                    const slot: u8 = @intCast(i);

                    assert(slot < capacity);

                    return slot;
                }
            }

            return null;
        }

        pub fn clear(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.is_valid());

            for (&instance.entries) |*entry| {
                entry.active = false;
            }

            instance.count = 0;
            instance.buffer.clear();

            assert(instance.count == 0);
        }
    };
}

const TestContext = struct {
    invoked: bool = false,
    command_name: [32]u8 = [_]u8{0} ** 32,
    command_args: [128]u8 = [_]u8{0} ** 128,
    name_len: usize = 0,
    args_len: usize = 0,

    fn callback(ctx: *anyopaque, name: []const u8, args: []const u8) Response {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.invoked = true;

        const name_copy_len = @min(name.len, self.command_name.len);
        @memcpy(self.command_name[0..name_copy_len], name[0..name_copy_len]);
        self.name_len = name_copy_len;

        const args_copy_len = @min(args.len, self.command_args.len);
        @memcpy(self.command_args[0..args_copy_len], args[0..args_copy_len]);
        self.args_len = args_copy_len;

        return .consume;
    }

    fn get_name(context: *const TestContext) []const u8 {
        return context.command_name[0..context.name_len];
    }
};

test "a new command registry is valid and empty" {
    var registry = CommandRegistryType(8).init();

    try std.testing.expect(registry.is_valid());
}

test "registering a command stores it" {
    var registry = CommandRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register("test", TestContext.callback, &ctx);

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "several commands register side by side" {
    var registry = CommandRegistryType(8).init();
    var ctx1 = TestContext{};
    var ctx2 = TestContext{};

    const id1 = try registry.register("cmd1", TestContext.callback, &ctx1);
    const id2 = try registry.register("cmd2", TestContext.callback, &ctx2);

    try std.testing.expect(id1 != id2);
    try std.testing.expect(registry.is_valid());
}

test "registering past capacity is an error" {
    var registry = CommandRegistryType(2).init();
    var ctx = TestContext{};

    _ = try registry.register("cmd1", TestContext.callback, &ctx);
    _ = try registry.register("cmd2", TestContext.callback, &ctx);

    const result = registry.register("cmd3", TestContext.callback, &ctx);

    try std.testing.expectError(error.RegistryFull, result);
}

test "an empty command name is an error" {
    var registry = CommandRegistryType(8).init();
    var ctx = TestContext{};

    const result = registry.register("", TestContext.callback, &ctx);

    try std.testing.expectError(error.InvalidName, result);
}

test "an over long command name is an error" {
    var registry = CommandRegistryType(8).init();
    var ctx = TestContext{};

    const long_name = "this_name_is_way_too_long_for_a_command";
    const result = registry.register(long_name, TestContext.callback, &ctx);

    try std.testing.expectError(error.InvalidName, result);
}

test "registering the same command twice is an error" {
    var registry = CommandRegistryType(8).init();
    var ctx = TestContext{};

    _ = try registry.register("test", TestContext.callback, &ctx);

    const result = registry.register("test", TestContext.callback, &ctx);

    try std.testing.expectError(error.AlreadyRegistered, result);
}

test "unregistering a command drops it" {
    var registry = CommandRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register("test", TestContext.callback, &ctx);

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "unregistering an unknown command is an error" {
    var registry = CommandRegistryType(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.NotFound, result);
}

test "clearing removes every command" {
    var registry = CommandRegistryType(8).init();
    var ctx = TestContext{};

    _ = try registry.register("cmd1", TestContext.callback, &ctx);
    _ = try registry.register("cmd2", TestContext.callback, &ctx);

    registry.clear();

    try std.testing.expect(registry.is_valid());

    _ = try registry.register("cmd1", TestContext.callback, &ctx);
}

test "the enabled flag decides whether commands are processed" {
    var registry = CommandRegistryType(8).init();

    try std.testing.expect(registry.enabled);

    registry.enabled = false;

    try std.testing.expect(!registry.enabled);

    registry.enabled = true;

    try std.testing.expect(registry.enabled);
}

test "the trigger can be changed after construction" {
    var registry = CommandRegistryType(8).init();

    registry.trigger = '/';

    try std.testing.expectEqual(@as(u8, '/'), registry.trigger);

    registry.trigger = '!';

    try std.testing.expectEqual(@as(u8, '!'), registry.trigger);
}

test "the default trigger is a colon" {
    const registry = CommandRegistryType(8).init();

    try std.testing.expectEqual(@as(u8, ':'), registry.trigger);
}

test "a default command entry is inactive" {
    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.id);
    try std.testing.expect(entry.callback == null);
    try std.testing.expect(entry.context == null);
    try std.testing.expect(!entry.active);
}

test "a command entry reports whether it is active" {
    var entry = Entry{};

    try std.testing.expect(!entry.is_active());

    entry.active = true;

    try std.testing.expect(entry.is_active());
}

test "constants: valid ranges" {
    try std.testing.expect(name_max >= 1);
    try std.testing.expect(buffer_max >= name_max);
    try std.testing.expect(capacity_default >= 1);
    try std.testing.expect(capacity_max >= capacity_default);
}
