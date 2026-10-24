const std = @import("std");

const builder = @import("builder/mouse.zig");
const mouse_event = @import("event/mouse.zig");
const mouse_registry = @import("registry/mouse.zig");
const platform = @import("platform.zig");
const response_module = @import("response.zig");
const runtime = @import("runtime.zig");
const sync = @import("sync.zig");

const assert = std.debug.assert;

const MouseEvent = mouse_event.MouseEvent;
const Mutex = sync.Mutex;
const Response = response_module.Response;

pub const CapacityError = mouse_registry.CapacityError;

pub const PlatformError = error{HookInstallFailed};
pub const RequestError = error{HookDuplicate} || mouse_registry.RequestError;

pub const MouseCapacity = struct {
    binding_count_max: u32 = 0,
};

pub const MouseOptions = struct {
    pass_injected: bool = true,
};

pub fn MouseType(comptime capacity: MouseCapacity) type {
    return struct {
        const Instance = @This();
        const Source = platform.backend.mouse.SourceType(Instance);

        const Registry = if (capacity.binding_count_max > 0)
            mouse_registry.MouseRegistryType(capacity.binding_count_max)
        else
            void;

        options: MouseOptions = .{},
        registry: Registry = if (capacity.binding_count_max > 0) Registry.init() else {},
        blocked: std.atomic.Value(bool) = .init(false),
        running: std.atomic.Value(bool) = .init(false),
        mutex: Mutex = .{},
        source: Source = Source.init(),

        pub const Binding = enum(u32) { _ };

        pub fn init(instance: *Instance, options: MouseOptions) void {
            instance.* = .{ .options = options };

            assert(!instance.is_running());
            assert(!instance.is_blocked());
        }

        pub fn deinit(instance: *Instance) void {
            instance.stop();

            instance.* = undefined;
        }

        pub fn bind(instance: *Instance, kind: MouseEvent.Kind) builder.BindBuilderType(Instance) {
            comptime require();

            assert(kind.is_valid());

            return .{ .hook = instance, .kind = kind };
        }

        pub fn block(instance: *Instance) void {
            instance.blocked.store(true, .seq_cst);

            assert(instance.is_blocked());
        }

        pub fn is_blocked(instance: *const Instance) bool {
            return instance.blocked.load(.seq_cst);
        }

        pub fn is_running(instance: *const Instance) bool {
            return instance.running.load(.seq_cst);
        }

        pub fn process(instance: *Instance, event: *const MouseEvent) Response {
            assert(event.is_valid());

            return runtime.clamp(instance.resolve(event));
        }

        pub fn start(instance: *Instance) (PlatformError || RequestError)!void {
            assert(runtime.is_open());

            instance.mutex.lock();
            defer instance.mutex.unlock();

            if (instance.is_running()) return;

            try instance.source.install(instance);

            instance.running.store(true, .seq_cst);

            assert(instance.is_running());
        }

        pub fn stop(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            if (!instance.is_running()) return;

            instance.running.store(false, .seq_cst);

            instance.source.remove();

            assert(!instance.is_running());
        }

        pub fn unbind(instance: *Instance, handle: Binding) RequestError!void {
            comptime require();

            return instance.registry.unregister(@backingInt(handle));
        }

        pub fn unblock(instance: *Instance) void {
            instance.blocked.store(false, .seq_cst);

            assert(!instance.is_blocked());
        }

        fn require() void {
            if (Registry == void) {
                @compileError("nimble: this mouse hook was built without bindings, " ++
                    "so set binding_count_max in its MouseCapacity");
            }
        }

        fn resolve(instance: *Instance, event: *const MouseEvent) Response {
            assert(event.is_valid());

            if (instance.options.pass_injected) {
                if (event.injected) return .pass;
            }

            if (instance.is_blocked()) return .consume;
            if (Registry == void) return .pass;
            return instance.registry.process(event) orelse .pass;
        }
    };
}

const testing = std.testing;

const mock = platform.mock;

const Counter = struct {
    hits: u32 = 0,

    fn on_click(counter: *Counter, _: *const MouseEvent) Response {
        counter.hits += 1;

        return .consume;
    }
};

const left_down = MouseEvent.from_button(.{ .button = .left, .down = true }, .{});

test MouseType {
    mock.reset();

    try runtime.open(.{ .mode = .grab });
    defer runtime.close();

    const Mouse = MouseType(.{ .binding_count_max = 2 });

    var mouse: Mouse = undefined;

    mouse.init(.{});
    defer mouse.deinit();

    var counter = Counter{};

    const click = try mouse.bind(.left_down).on(Counter, &counter, Counter.on_click);

    try mouse.start();
    defer mouse.stop();

    mock.loop.push_mouse(left_down);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), counter.hits);

    try mouse.unbind(click);

    mock.loop.push_mouse(left_down);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), counter.hits);
    try testing.expectEqual(Response.pass, mock.loop.response_at(1));
}

test MouseCapacity {
    const Bare = MouseType(.{});
    const Bound = MouseType(.{ .binding_count_max = 4 });

    try testing.expect(@FieldType(Bare, "registry") == void);
    try testing.expect(@FieldType(Bound, "registry") != void);
    try testing.expect(@sizeOf(Bare) < @sizeOf(Bound));
}

test MouseOptions {
    mock.reset();

    try runtime.open(.{ .mode = .grab });
    defer runtime.close();

    const Mouse = MouseType(.{ .binding_count_max = 1 });

    var mouse: Mouse = undefined;

    mouse.init(.{});
    defer mouse.deinit();

    var counter = Counter{};

    _ = try mouse.bind(.left_down).on(Counter, &counter, Counter.on_click);

    try mouse.start();
    defer mouse.stop();

    var injected = left_down;

    injected.injected = true;

    mock.loop.push_mouse(injected);
    mock.loop.push_mouse(left_down);
    mock.loop.run();

    try testing.expectEqual(@as(u32, 1), counter.hits);
    try testing.expectEqual(Response.pass, mock.loop.response_at(0));
    try testing.expectEqual(Response.consume, mock.loop.response_at(1));
}
