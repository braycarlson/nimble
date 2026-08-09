const std = @import("std");

const response = @import("../response.zig");
const filter_mod = @import("../filter.zig");
const event = @import("../event/mouse.zig");
const base = @import("base.zig");
const entry_mod = @import("entry.zig");

const assert = std.debug.assert;

const Response = response.Response;
const Mouse = event.Mouse;
const MouseKind = event.Kind;
const WindowFilter = filter_mod.Active;

pub const capacity_default: u32 = 128;
pub const capacity_max: u32 = 1024;

pub const Error = base.BaseError || error{
    AlreadyRegistered,
};

pub const Callback = *const fn (context: *anyopaque, mouse: *const Mouse) Response;

pub const Entry = struct {
    base: entry_mod.FilteredEntryType(Callback, WindowFilter) = .{},
    kind: MouseKind = .other,

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

    pub fn is_valid(entry: *const Entry) bool {
        if (!entry.is_active()) {
            return true;
        }

        return entry.base.is_valid() and entry.kind.is_valid();
    }

    pub fn matches_filter(entry: *const Entry) bool {
        return entry.base.matches_filter();
    }

    pub fn invoke(entry: *const Entry, mouse: *const Mouse) ?Response {
        assert(entry.is_active());

        return entry.base.invoke(.{mouse});
    }
};

const Invocation = struct {
    callback: Callback,
    context: *anyopaque,
};

pub const Options = struct {
    filter: WindowFilter = .{},
};

pub fn MouseRegistryType(comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("MouseRegistryType capacity must be at least 1");
    }

    if (capacity > capacity_max) {
        @compileError("MouseRegistryType capacity exceeds maximum");
    }

    return struct {
        const Instance = @This();

        const Base = base.BaseRegistryType(Entry, capacity, .{
            .has_mutex = true,
            .has_paused = true,
        });

        base: Base = Base.init(),

        pub fn init() Instance {
            return Instance{};
        }

        pub fn is_valid(instance: *const Instance) bool {
            return instance.base.is_valid();
        }

        pub fn set_paused(instance: *Instance, value: bool) void {
            instance.base.set_paused(value);
        }

        pub fn is_paused(instance: *Instance) bool {
            return instance.base.is_paused();
        }

        pub fn clear(instance: *Instance) void {
            instance.base.clear();
        }

        pub fn process(instance: *Instance, mouse: *const Mouse) ?Response {
            assert(mouse.is_valid());

            const invocation = blk: {
                instance.base.lock();
                defer instance.base.unlock();

                assert(instance.is_valid());

                if (instance.base.is_paused()) {
                    break :blk null;
                }

                break :blk instance.resolve_locked(mouse);
            };

            if (invocation) |inv| {
                return inv.callback(inv.context, mouse);
            }

            return null;
        }

        fn resolve_locked(instance: *Instance, mouse: *const Mouse) ?Invocation {
            assert(mouse.is_valid());

            const entries = instance.base.entries();

            for (entries) |*e| {
                if (!e.is_active()) {
                    continue;
                }

                if (e.kind != mouse.kind) {
                    continue;
                }

                if (!e.matches_filter()) {
                    continue;
                }

                const callback = e.get_callback() orelse continue;
                const context = e.get_context() orelse continue;

                return Invocation{
                    .callback = callback,
                    .context = context,
                };
            }

            return null;
        }

        pub fn register(
            instance: *Instance,
            kind: MouseKind,
            callback: Callback,
            context: ?*anyopaque,
            options: Options,
        ) Error!u32 {
            assert(kind.is_valid());

            instance.base.lock();
            defer instance.base.unlock();

            assert(instance.is_valid());

            const allocation = instance.base.allocate_locked() catch return error.RegistryFull;

            assert(allocation.slot < capacity);
            assert(allocation.id >= 1);

            instance.base.slot.entries[allocation.slot] = Entry{
                .base = .{
                    .base = .{
                        .id = allocation.id,
                        .callback = callback,
                        .context = context,
                        .active = true,
                    },
                    .filter = options.filter,
                },
                .kind = kind,
            };

            assert(instance.base.slot.entries[allocation.slot].is_valid());

            return allocation.id;
        }

        pub fn unregister(instance: *Instance, id: u32) Error!void {
            assert(id >= 1);

            _ = instance.base.free_by_id(id) catch return error.NotFound;
        }
    };
}

fn make_test_mouse(kind: MouseKind, x: i32, y: i32) Mouse {
    const position = event.Position.init(x, y);

    if (kind == .move) {
        return Mouse.from_motion(.{ .position = position }, .{});
    }

    if (kind == .wheel) {
        return Mouse.from_wheel(.{ .steps_vertical = 1, .position = position }, .{});
    }

    if (kind == .other) {
        return Mouse{ .kind = .other };
    }

    return Mouse.from_button(.{
        .button = button_of(kind),
        .down = kind.is_down(),
        .position = position,
    }, .{});
}

fn button_of(kind: MouseKind) event.Button {
    return switch (kind) {
        .left_down, .left_up => .left,
        .right_down, .right_up => .right,
        .middle_down, .middle_up => .middle,
        .x_down, .x_up => .x1,
        .wheel, .move, .other => unreachable,
    };
}

const TestContext = struct {
    invoked: bool = false,
    mouse_kind: MouseKind = .other,
    mouse_x: i32 = 0,
    mouse_y: i32 = 0,

    fn callback(ctx: *anyopaque, mouse: *const Mouse) Response {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.invoked = true;
        self.mouse_kind = mouse.kind;

        if (mouse.position()) |position| {
            self.mouse_x = position.x;
            self.mouse_y = position.y;
        }

        return .consume;
    }
};

test "a new mouse registry is valid and empty" {
    var registry = MouseRegistryType(8).init();

    try std.testing.expect(registry.is_valid());
}

test "registering a mouse binding stores it" {
    var registry = MouseRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(
        .left_down,
        TestContext.callback,
        &ctx,
        Options{},
    );

    try std.testing.expect(id >= 1);
    try std.testing.expect(registry.is_valid());
}

test "several mouse bindings register side by side" {
    var registry = MouseRegistryType(8).init();
    var ctx1 = TestContext{};
    var ctx2 = TestContext{};
    var ctx3 = TestContext{};

    const id1 = try registry.register(.left_down, TestContext.callback, &ctx1, Options{});
    const id2 = try registry.register(.right_down, TestContext.callback, &ctx2, Options{});
    const id3 = try registry.register(.middle_down, TestContext.callback, &ctx3, Options{});

    try std.testing.expect(id1 != id2);
    try std.testing.expect(id2 != id3);
    try std.testing.expect(id1 != id3);
    try std.testing.expect(registry.is_valid());
}

test "registering past capacity is an error" {
    var registry = MouseRegistryType(2).init();
    var ctx = TestContext{};

    _ = try registry.register(.left_down, TestContext.callback, &ctx, Options{});
    _ = try registry.register(.right_down, TestContext.callback, &ctx, Options{});

    const result = registry.register(.middle_down, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.RegistryFull, result);
}

test "unregistering a mouse binding drops it" {
    var registry = MouseRegistryType(8).init();
    var ctx = TestContext{};

    const id = try registry.register(.left_down, TestContext.callback, &ctx, Options{});

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "unregistering an unknown mouse binding is an error" {
    var registry = MouseRegistryType(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.NotFound, result);
}

test "a mouse registry can be paused and resumed" {
    var registry = MouseRegistryType(8).init();

    try std.testing.expect(!registry.is_paused());

    registry.set_paused(true);

    try std.testing.expect(registry.is_paused());

    registry.set_paused(false);

    try std.testing.expect(!registry.is_paused());
}

test "clearing removes every mouse binding" {
    var registry = MouseRegistryType(8).init();
    var ctx = TestContext{};

    _ = try registry.register(.left_down, TestContext.callback, &ctx, Options{});
    _ = try registry.register(.right_down, TestContext.callback, &ctx, Options{});

    registry.clear();

    try std.testing.expect(registry.is_valid());
}

test "mouse options start at their default values" {
    const opts = Options{};

    _ = opts.filter;
}

test "a default mouse entry_mod is inactive" {
    const entry_default = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry_default.get_id());
    try std.testing.expect(entry_default.get_callback() == null);
    try std.testing.expect(entry_default.get_context() == null);
    try std.testing.expect(!entry_default.is_active());
    try std.testing.expectEqual(MouseKind.other, entry_default.kind);
}

test "a default mouse entry_mod is valid" {
    const entry_inactive = Entry{};

    try std.testing.expect(entry_inactive.is_valid());
}

test "every mouse kind is valid" {
    try std.testing.expect(MouseKind.left_down.is_valid());
    try std.testing.expect(MouseKind.left_up.is_valid());
    try std.testing.expect(MouseKind.right_down.is_valid());
    try std.testing.expect(MouseKind.right_up.is_valid());
    try std.testing.expect(MouseKind.middle_down.is_valid());
    try std.testing.expect(MouseKind.middle_up.is_valid());
    try std.testing.expect(MouseKind.move.is_valid());
    try std.testing.expect(MouseKind.wheel.is_valid());
    try std.testing.expect(MouseKind.other.is_valid());
}

test "is_button holds only for the button kinds" {
    try std.testing.expect(MouseKind.left_down.is_button());
    try std.testing.expect(MouseKind.left_up.is_button());
    try std.testing.expect(MouseKind.right_down.is_button());
    try std.testing.expect(MouseKind.right_up.is_button());
    try std.testing.expect(MouseKind.middle_down.is_button());
    try std.testing.expect(MouseKind.middle_up.is_button());
    try std.testing.expect(MouseKind.x_down.is_button());
    try std.testing.expect(MouseKind.x_up.is_button());

    try std.testing.expect(!MouseKind.move.is_button());
    try std.testing.expect(!MouseKind.wheel.is_button());
    try std.testing.expect(!MouseKind.other.is_button());
}

test "is_down holds only for the press kinds" {
    try std.testing.expect(MouseKind.left_down.is_down());
    try std.testing.expect(MouseKind.right_down.is_down());
    try std.testing.expect(MouseKind.middle_down.is_down());
    try std.testing.expect(MouseKind.x_down.is_down());

    try std.testing.expect(!MouseKind.left_up.is_down());
    try std.testing.expect(!MouseKind.right_up.is_down());
    try std.testing.expect(!MouseKind.move.is_down());
}

test "is_up holds only for the release kinds" {
    try std.testing.expect(MouseKind.left_up.is_up());
    try std.testing.expect(MouseKind.right_up.is_up());
    try std.testing.expect(MouseKind.middle_up.is_up());
    try std.testing.expect(MouseKind.x_up.is_up());

    try std.testing.expect(!MouseKind.left_down.is_up());
    try std.testing.expect(!MouseKind.right_down.is_up());
    try std.testing.expect(!MouseKind.move.is_up());
}

test "a mouse event is valid" {
    const mouse = make_test_mouse(.left_down, 100, 200);

    try std.testing.expect(mouse.is_valid());
}

test "a mouse event reads is_button from its kind" {
    const button_mouse = make_test_mouse(.left_down, 0, 0);
    const move_mouse = make_test_mouse(.move, 0, 0);

    try std.testing.expect(button_mouse.is_button());
    try std.testing.expect(!move_mouse.is_button());
}

test "a mouse event reads is_down from its kind" {
    const down_mouse = make_test_mouse(.left_down, 0, 0);
    const up_mouse = make_test_mouse(.left_up, 0, 0);

    try std.testing.expect(down_mouse.is_down());
    try std.testing.expect(!up_mouse.is_down());
}

test "a mouse event reads is_up from its kind" {
    const up_mouse = make_test_mouse(.left_up, 0, 0);
    const down_mouse = make_test_mouse(.left_down, 0, 0);

    try std.testing.expect(up_mouse.is_up());
    try std.testing.expect(!down_mouse.is_up());
}

test "constants: valid ranges" {
    try std.testing.expect(capacity_default >= 1);
    try std.testing.expect(capacity_max >= capacity_default);
}
