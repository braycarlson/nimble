const std = @import("std");
const input = @import("input");

const mouse_registry = input.registry.mouse;
const mouse_event = input.event.mouse;
const response_mod = input.response;
const filter_mod = input.filter;

const MouseRegistry = mouse_registry.MouseRegistry;
const Options = mouse_registry.Options;
const Entry = mouse_registry.Entry;
const Mouse = mouse_event.Mouse;
const MouseKind = mouse_event.Kind;
const Response = response_mod.Response;
const WindowFilter = filter_mod.WindowFilter;

fn make_test_mouse(kind: MouseKind, x: i32, y: i32) Mouse {
    return Mouse{
        .kind = kind,
        .x = x,
        .y = y,
        .extra = 0,
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
        self.mouse_x = mouse.x;
        self.mouse_y = mouse.y;
        return .consume;
    }

    fn pass_callback(ctx: *anyopaque, mouse: *const Mouse) Response {
        const self: *TestContext = @ptrCast(@alignCast(ctx));
        self.invoked = true;
        self.mouse_kind = mouse.kind;
        return .pass;
    }
};

test "MouseRegistry: init creates valid registry" {
    var registry = MouseRegistry(8).init();

    try std.testing.expect(registry.is_valid());
}

test "MouseRegistry: register binding" {
    var registry = MouseRegistry(8).init();
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

test "MouseRegistry: register multiple bindings" {
    var registry = MouseRegistry(8).init();
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

test "MouseRegistry: registry full error" {
    var registry = MouseRegistry(2).init();
    var ctx = TestContext{};

    _ = try registry.register(.left_down, TestContext.callback, &ctx, Options{});
    _ = try registry.register(.right_down, TestContext.callback, &ctx, Options{});

    const result = registry.register(.middle_down, TestContext.callback, &ctx, Options{});

    try std.testing.expectError(error.RegistryFull, result);
}

test "MouseRegistry: unregister binding" {
    var registry = MouseRegistry(8).init();
    var ctx = TestContext{};

    const id = try registry.register(.left_down, TestContext.callback, &ctx, Options{});

    try registry.unregister(id);

    try std.testing.expect(registry.is_valid());
}

test "MouseRegistry: unregister not found error" {
    var registry = MouseRegistry(8).init();

    const result = registry.unregister(999);

    try std.testing.expectError(error.NotFound, result);
}

test "MouseRegistry: pause and unpause" {
    var registry = MouseRegistry(8).init();

    try std.testing.expect(!registry.is_paused());

    registry.set_paused(true);

    try std.testing.expect(registry.is_paused());

    registry.set_paused(false);

    try std.testing.expect(!registry.is_paused());
}

test "MouseRegistry: clear removes all entries" {
    var registry = MouseRegistry(8).init();
    var ctx = TestContext{};

    _ = try registry.register(.left_down, TestContext.callback, &ctx, Options{});
    _ = try registry.register(.right_down, TestContext.callback, &ctx, Options{});

    registry.clear();

    try std.testing.expect(registry.is_valid());
}

test "Options: default values" {
    const opts = Options{};

    _ = opts.filter;
}

test "Entry: default state" {
    const entry = Entry{};

    try std.testing.expectEqual(@as(u32, 0), entry.get_id());
    try std.testing.expect(entry.get_callback() == null);
    try std.testing.expect(entry.get_context() == null);
    try std.testing.expect(!entry.is_active());
    try std.testing.expectEqual(MouseKind.other, entry.kind);
}

test "Entry: is_valid for inactive entry" {
    const entry = Entry{};

    try std.testing.expect(entry.is_valid());
}

test "MouseKind: is_valid" {
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

test "MouseKind: is_button" {
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

test "MouseKind: is_down" {
    try std.testing.expect(MouseKind.left_down.is_down());
    try std.testing.expect(MouseKind.right_down.is_down());
    try std.testing.expect(MouseKind.middle_down.is_down());
    try std.testing.expect(MouseKind.x_down.is_down());

    try std.testing.expect(!MouseKind.left_up.is_down());
    try std.testing.expect(!MouseKind.right_up.is_down());
    try std.testing.expect(!MouseKind.move.is_down());
}

test "MouseKind: is_up" {
    try std.testing.expect(MouseKind.left_up.is_up());
    try std.testing.expect(MouseKind.right_up.is_up());
    try std.testing.expect(MouseKind.middle_up.is_up());
    try std.testing.expect(MouseKind.x_up.is_up());

    try std.testing.expect(!MouseKind.left_down.is_up());
    try std.testing.expect(!MouseKind.right_down.is_up());
    try std.testing.expect(!MouseKind.move.is_up());
}

test "Mouse: is_valid" {
    const mouse = make_test_mouse(.left_down, 100, 200);

    try std.testing.expect(mouse.is_valid());
}

test "Mouse: is_button delegates to kind" {
    const button_mouse = make_test_mouse(.left_down, 0, 0);
    const move_mouse = make_test_mouse(.move, 0, 0);

    try std.testing.expect(button_mouse.is_button());
    try std.testing.expect(!move_mouse.is_button());
}

test "Mouse: is_down delegates to kind" {
    const down_mouse = make_test_mouse(.left_down, 0, 0);
    const up_mouse = make_test_mouse(.left_up, 0, 0);

    try std.testing.expect(down_mouse.is_down());
    try std.testing.expect(!up_mouse.is_down());
}

test "Mouse: is_up delegates to kind" {
    const up_mouse = make_test_mouse(.left_up, 0, 0);
    const down_mouse = make_test_mouse(.left_down, 0, 0);

    try std.testing.expect(up_mouse.is_up());
    try std.testing.expect(!down_mouse.is_up());
}

test "constants: valid ranges" {
    try std.testing.expect(mouse_registry.capacity_default >= 1);
    try std.testing.expect(mouse_registry.capacity_max >= mouse_registry.capacity_default);
}
