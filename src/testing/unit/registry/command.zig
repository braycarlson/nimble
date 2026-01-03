const std = @import("std");
const input = @import("input");

const command = input.registry.command;
const key_event = input.event.key;
const response_mod = input.response;

const CommandRegistry = command.CommandRegistry;
const Key = key_event.Key;
const Response = response_mod.Response;

fn make_test_key(value: u8, down: bool) Key {
    return Key{
        .value = value,
        .scan = 0,
        .down = down,
        .injected = false,
        .extended = false,
        .extra = 0,
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

    fn pass_callback(ctx: *anyopaque, name: []const u8, args: []const u8) Response {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.invoked = true;
        _ = name;
        _ = args;
        return .pass;
    }

    fn get_name(self: *const TestContext) []const u8 {
        return self.command_name[0..self.name_len];
    }

    fn get_args(self: *const TestContext) []const u8 {
        return self.command_args[0..self.args_len];
    }
};

test "CommandRegistry: init creates valid registry" {
    var registry = CommandRegistry(8).init();

    try std.testing.expect(registry.is_valid());
}

test "CommandRegistry: register command" {
    var registry = CommandRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register("test", TestContext.callback, &ctx);

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "CommandRegistry: register multiple commands" {
    var registry = CommandRegistry(8).init();
    var ctx1 = TestContext{};
    var ctx2 = TestContext{};

    const id1 = try registry.register("cmd1", TestContext.callback, &ctx1);
    const id2 = try registry.register("cmd2", TestContext.callback, &ctx2);

    try std.testing.expect(id1 != id2);
    try std.testing.expect(registry.is_valid());
}

test "CommandRegistry: registry full error" {
    var registry = CommandRegistry(2).init();
    var ctx = TestContext{};

    _ = try registry.register("cmd1", TestContext.callback, &ctx);
    _ = try registry.register("cmd2", TestContext.callback, &ctx);

    const result = registry.register("cmd3", TestContext.callback, &ctx);

    try std.testing.expectError(error.RegistryFull, result);
}

test "CommandRegistry: invalid name error for empty name" {
    var registry = CommandRegistry(8).init();
    var ctx = TestContext{};

    const result = registry.register("", TestContext.callback, &ctx);

    try std.testing.expectError(error.InvalidName, result);
}

test "CommandRegistry: invalid name error for too long name" {
    var registry = CommandRegistry(8).init();
    var ctx = TestContext{};

    const long_name = "this_name_is_way_too_long_for_a_command";
    const result = registry.register(long_name, TestContext.callback, &ctx);

    try std.testing.expectError(error.InvalidName, result);
}

test "CommandRegistry: already registered error" {
    var registry = CommandRegistry(8).init();
    var ctx = TestContext{};

    _ = try registry.register("test", TestContext.callback, &ctx);

    const result = registry.register("test", TestContext.callback, &ctx);

    try std.testing.expectError(error.AlreadyRegistered, result);
}

test "CommandRegistry: unregister command" {
    var registry = CommandRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register("test", TestContext.callback, &ctx);

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "CommandRegistry: unregister not found error" {
    var registry = CommandRegistry(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.NotFound, result);
}

test "CommandRegistry: clear removes all commands" {
    var registry = CommandRegistry(8).init();
    var ctx = TestContext{};

    _ = try registry.register("cmd1", TestContext.callback, &ctx);
    _ = try registry.register("cmd2", TestContext.callback, &ctx);

    registry.clear();

    try std.testing.expect(registry.is_valid());

    _ = try registry.register("cmd1", TestContext.callback, &ctx);
}

test "CommandRegistry: enabled field controls processing" {
    var registry = CommandRegistry(8).init();

    try std.testing.expect(registry.enabled);

    registry.enabled = false;

    try std.testing.expect(!registry.enabled);

    registry.enabled = true;

    try std.testing.expect(registry.enabled);
}

test "CommandRegistry: set_prefix updates prefix" {
    var registry = CommandRegistry(8).init();

    registry.set_prefix('/');

    try std.testing.expectEqual(@as(u8, '/'), registry.prefix);

    registry.set_prefix('!');

    try std.testing.expectEqual(@as(u8, '!'), registry.prefix);
}

test "CommandRegistry: default prefix is colon" {
    const registry = CommandRegistry(8).init();

    try std.testing.expectEqual(@as(u8, ':'), registry.prefix);
}

test "Entry: default state" {
    const Entry = command.Entry;

    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.id);
    try std.testing.expect(entry.callback == null);
    try std.testing.expect(entry.context == null);
    try std.testing.expect(!entry.active);
}

test "Entry: is_active" {
    const Entry = command.Entry;

    var entry = Entry{};

    try std.testing.expect(!entry.is_active());

    entry.active = true;

    try std.testing.expect(entry.is_active());
}

test "constants: valid ranges" {
    try std.testing.expect(command.name_max >= 1);
    try std.testing.expect(command.buffer_max >= command.name_max);
    try std.testing.expect(command.capacity_default >= 1);
    try std.testing.expect(command.capacity_max >= command.capacity_default);
}
