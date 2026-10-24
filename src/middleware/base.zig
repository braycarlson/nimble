const std = @import("std");

const key_event = @import("../event/key.zig");
const keycode = @import("../keycode.zig");
const response = @import("../response.zig");
const sync = @import("../sync.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Keycode = keycode.Keycode;
const Mutex = sync.Mutex;
const Response = response.Response;

pub const CapacityError = error{MiddlewareExhausted};
pub const RequestError = error{HandleUnknown};

pub const Next = struct {
    context: *anyopaque,
    call: *const fn (context: *anyopaque, key: *const Key) Response,

    pub fn invoke(next: *const Next, key: *const Key) Response {
        assert(key.is_valid());

        const result = next.call(next.context, key);

        assert(result.is_valid());

        return result;
    }
};

pub const Middleware = struct {
    pointer: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        process: *const fn (pointer: *anyopaque, key: *const Key, next: *const Next) Response,
    };

    pub fn process(middleware: *const Middleware, key: *const Key, next: *const Next) Response {
        assert(key.is_valid());

        const result = middleware.vtable.process(middleware.pointer, key, next);

        assert(result.is_valid());

        return result;
    }

    pub fn from(comptime T: type, pointer: *T) Middleware {
        comptime assert_middleware(T);

        const impl = struct {
            fn process(p: *anyopaque, k: *const Key, n: *const Next) Response {
                assert(k.is_valid());

                const context: *T = @ptrCast(@alignCast(p));
                const result = context.process(k, n);

                assert(result.is_valid());

                return result;
            }

            const vtable = VTable{ .process = @This().process };
        };

        const result = Middleware{
            .pointer = pointer,
            .vtable = &impl.vtable,
        };

        return result;
    }
};

pub fn PipelineType(comptime capacity: u8) type {
    return struct {
        const Instance = @This();

        items: [capacity]?Middleware = @splat(null),
        count: u8 = 0,
        mutex: Mutex = .{},

        const Snapshot = struct {
            items: [capacity]Middleware,
            count: u8,
            final: Next,
        };

        pub fn init() Instance {
            const result = Instance{};

            assert(result.count == 0);
            assert(capacity > 0);

            return result;
        }

        pub fn add(instance: *Instance, comptime T: type, pointer: *T) CapacityError!u8 {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            if (instance.count >= capacity) {
                return error.MiddlewareExhausted;
            }

            const slot = instance.find_empty_slot() orelse return error.MiddlewareExhausted;

            assert(slot < capacity);

            instance.items[slot] = Middleware.from(T, pointer);
            instance.count += 1;

            assert(instance.count <= capacity);
            assert(instance.items[slot] != null);

            return slot;
        }

        pub fn remove(instance: *Instance, slot: u8) RequestError!void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            if (slot >= capacity) {
                return error.HandleUnknown;
            }

            assert(slot < capacity);

            if (instance.items[slot] == null) {
                return error.HandleUnknown;
            }

            instance.items[slot] = null;
            instance.count -= 1;

            assert(instance.count <= capacity);
            assert(instance.items[slot] == null);
        }

        fn find_empty_slot(instance: *const Instance) ?u8 {
            assert(instance.count <= capacity);

            var i: u8 = 0;

            while (i < capacity) : (i += 1) {
                if (instance.items[i] == null) {
                    return i;
                }
            }

            assert(i == capacity);

            return null;
        }

        pub fn process(instance: *Instance, key: *const Key, final: Next) Response {
            assert(key.is_valid());

            var snapshot = Snapshot{
                .items = undefined,
                .count = 0,
                .final = final,
            };

            instance.snapshot_items(&snapshot);

            assert(snapshot.count <= capacity);

            const result = stage_process(0, &snapshot, key);

            assert(result.is_valid());

            return result;
        }

        fn snapshot_items(instance: *Instance, snapshot: *Snapshot) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);
            assert(snapshot.count == 0);

            var i: u8 = 0;

            while (i < capacity) : (i += 1) {
                if (instance.items[i]) |middleware| {
                    assert(snapshot.count < capacity);

                    snapshot.items[snapshot.count] = middleware;
                    snapshot.count += 1;
                }
            }

            assert(i == capacity);
            assert(snapshot.count == instance.count);
        }

        fn stage_process(comptime index: u8, snapshot: *Snapshot, key: *const Key) Response {
            assert(key.is_valid());
            assert(snapshot.count <= capacity);

            if (index == capacity) {
                return snapshot.final.invoke(key);
            } else {
                if (index >= snapshot.count) {
                    return snapshot.final.invoke(key);
                }

                const next = Next{
                    .context = snapshot,
                    .call = stage_call(index + 1),
                };

                const result = snapshot.items[index].process(key, &next);

                assert(result.is_valid());

                return result;
            }
        }

        fn stage_call(
            comptime index: u8,
        ) *const fn (context: *anyopaque, key: *const Key) Response {
            const impl = struct {
                fn call(context: *anyopaque, key: *const Key) Response {
                    assert(key.is_valid());

                    const snapshot: *Snapshot = @ptrCast(@alignCast(context));
                    const result = stage_process(index, snapshot, key);

                    assert(result.is_valid());

                    return result;
                }
            };

            return impl.call;
        }

        pub fn clear(instance: *Instance) void {
            instance.mutex.lock();
            defer instance.mutex.unlock();

            assert(instance.count <= capacity);

            var i: u8 = 0;

            while (i < capacity) : (i += 1) {
                instance.items[i] = null;
            }

            instance.count = 0;

            assert(instance.count == 0);
            assert(i == capacity);
        }
    };
}

fn assert_middleware(comptime T: type) void {
    const message = "nimble: middleware " ++ @typeName(T) ++
        " needs pub fn process(*" ++ @typeName(T) ++ ", *const Key, *const Next) Response";

    if (!@hasDecl(T, "process")) {
        @compileError(message);
    }

    const Expected = fn (*T, *const Key, *const Next) Response;

    if (@TypeOf(T.process) != Expected) {
        @compileError(message);
    }
}

const testing = std.testing;

test Next {
    const Upper = struct {
        seen: u32 = 0,

        pub fn process(upper: *@This(), key: *const Key, next: *const Next) Response {
            upper.seen += 1;

            return next.invoke(key);
        }
    };

    var pipeline = PipelineType(2).init();
    var upper = Upper{};

    _ = try pipeline.add(Upper, &upper);

    var context: u8 = 0;
    const key = make_key(.a);

    try testing.expectEqual(Response.pass, pipeline.process(&key, final_next(&context)));
    try testing.expectEqual(@as(u32, 1), upper.seen);
}

fn make_key(value: Keycode) Key {
    return Key{
        .value = value,
        .down = true,
        .injected = false,
        .modifiers = .{},
    };
}

fn final_pass(_: *anyopaque, key: *const Key) Response {
    assert(key.is_valid());

    return .pass;
}

fn final_next(context: *u8) Next {
    return Next{
        .context = context,
        .call = final_pass,
    };
}

const Tagger = struct {
    calls: u32 = 0,

    pub fn process(tagger: *Tagger, key: *const Key, next: *const Next) Response {
        tagger.calls += 1;

        return next.invoke(key);
    }
};

const Consumer = struct {
    calls: u32 = 0,

    pub fn process(consumer: *Consumer, _: *const Key, _: *const Next) Response {
        consumer.calls += 1;

        return .consume;
    }
};

test "an empty pipeline calls the final handler" {
    var pipeline = PipelineType(4).init();
    var context: u8 = 0;
    const key = make_key(.a);

    try testing.expectEqual(Response.pass, pipeline.process(&key, final_next(&context)));
}

test "a pipeline runs its chain through to the final handler" {
    var pipeline = PipelineType(4).init();
    var first = Tagger{};
    var second = Tagger{};

    _ = try pipeline.add(Tagger, &first);
    _ = try pipeline.add(Tagger, &second);

    var context: u8 = 0;
    const key = make_key(.a);
    const result = pipeline.process(&key, final_next(&context));

    try testing.expectEqual(Response.pass, result);
    try testing.expectEqual(@as(u32, 1), first.calls);
    try testing.expectEqual(@as(u32, 1), second.calls);
}

test "a middleware that consumes stops the chain" {
    var pipeline = PipelineType(4).init();
    var blocker = Consumer{};
    var after = Tagger{};

    _ = try pipeline.add(Consumer, &blocker);
    _ = try pipeline.add(Tagger, &after);

    var context: u8 = 0;
    const key = make_key(.a);
    const result = pipeline.process(&key, final_next(&context));

    try testing.expectEqual(Response.consume, result);
    try testing.expectEqual(@as(u32, 1), blocker.calls);
    try testing.expectEqual(@as(u32, 0), after.calls);
}

test "removing a middleware leaves the other handles stable" {
    var pipeline = PipelineType(4).init();
    var first = Tagger{};
    var second = Consumer{};
    var third = Tagger{};

    const slot_first = try pipeline.add(Tagger, &first);
    const slot_second = try pipeline.add(Consumer, &second);
    const slot_third = try pipeline.add(Tagger, &third);

    try testing.expectEqual(@as(u8, 2), slot_third);

    try pipeline.remove(slot_first);
    try pipeline.remove(slot_second);

    var context: u8 = 0;
    const key = make_key(.a);
    const result = pipeline.process(&key, final_next(&context));

    try testing.expectEqual(Response.pass, result);
    try testing.expectEqual(@as(u32, 0), first.calls);
    try testing.expectEqual(@as(u32, 0), second.calls);
    try testing.expectEqual(@as(u32, 1), third.calls);
}

test "removing an empty slot is reported" {
    var pipeline = PipelineType(2).init();

    const removed = pipeline.remove(0);

    try testing.expectError(error.HandleUnknown, removed);
}

test "removing an invalid slot is reported" {
    var pipeline = PipelineType(2).init();

    const removed = pipeline.remove(2);

    try testing.expectError(error.HandleUnknown, removed);
}

test "removing a middleware twice is reported" {
    var pipeline = PipelineType(2).init();
    var first = Tagger{};

    const slot = try pipeline.add(Tagger, &first);

    try pipeline.remove(slot);

    const repeated = pipeline.remove(slot);

    try testing.expectError(error.HandleUnknown, repeated);
}

test "a removed slot is handed out again" {
    var pipeline = PipelineType(2).init();
    var first = Tagger{};
    var second = Tagger{};
    var third = Tagger{};

    const slot_first = try pipeline.add(Tagger, &first);
    const slot_second = try pipeline.add(Tagger, &second);

    try testing.expectEqual(@as(u8, 1), slot_second);
    try pipeline.remove(slot_first);

    const reused_slot = try pipeline.add(Tagger, &third);

    try testing.expectEqual(slot_first, reused_slot);
}

test "a full pipeline refuses another middleware" {
    var pipeline = PipelineType(1).init();
    var first = Tagger{};
    var second = Tagger{};

    _ = try pipeline.add(Tagger, &first);

    try testing.expectError(error.MiddlewareExhausted, pipeline.add(Tagger, &second));
}

test "clearing a pipeline removes every middleware" {
    var pipeline = PipelineType(4).init();
    var first = Tagger{};
    var second = Tagger{};

    _ = try pipeline.add(Tagger, &first);
    _ = try pipeline.add(Tagger, &second);

    pipeline.clear();

    var context: u8 = 0;
    const key = make_key(.a);
    const result = pipeline.process(&key, final_next(&context));

    try testing.expectEqual(Response.pass, result);
    try testing.expectEqual(@as(u32, 0), first.calls);
    try testing.expectEqual(@as(u32, 0), second.calls);
}
