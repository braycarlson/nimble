const std = @import("std");
const input = @import("input");

const key_event = input.event.key;
const middleware = input.middleware;
const response = input.response;

const Key = key_event.Key;
const Next = middleware.Next;
const Pipeline = middleware.Pipeline;
const Response = response.Response;

const testing = std.testing;

fn make_key(value: u8) Key {
    return Key{
        .value = value,
        .scan = 0,
        .down = true,
        .injected = false,
        .extended = false,
        .extra = 0,
        .modifiers = .{},
    };
}

fn final_pass(key: *const Key) Response {
    std.debug.assert(key.is_valid());

    return .pass;
}

const Tagger = struct {
    calls: u32 = 0,

    pub fn process(self: *Tagger, key: *const Key, next: *const Next) Response {
        self.calls += 1;

        return next.invoke(key);
    }
};

const Consumer = struct {
    calls: u32 = 0,

    pub fn process(self: *Consumer, _: *const Key, _: *const Next) Response {
        self.calls += 1;

        return .consume;
    }
};

test "Pipeline.process empty calls final" {
    var pipeline = Pipeline(4).init();
    const key = make_key('A');

    try testing.expectEqual(Response.pass, pipeline.process(&key, final_pass));
}

test "Pipeline.process runs chain to final" {
    var pipeline = Pipeline(4).init();
    var first = Tagger{};
    var second = Tagger{};

    _ = try pipeline.add(Tagger, &first);
    _ = try pipeline.add(Tagger, &second);

    const key = make_key('A');
    const result = pipeline.process(&key, final_pass);

    try testing.expectEqual(Response.pass, result);
    try testing.expectEqual(@as(u32, 1), first.calls);
    try testing.expectEqual(@as(u32, 1), second.calls);
}

test "Pipeline.process middleware consumes" {
    var pipeline = Pipeline(4).init();
    var blocker = Consumer{};
    var after = Tagger{};

    _ = try pipeline.add(Consumer, &blocker);
    _ = try pipeline.add(Tagger, &after);

    const key = make_key('A');
    const result = pipeline.process(&key, final_pass);

    try testing.expectEqual(Response.consume, result);
    try testing.expectEqual(@as(u32, 1), blocker.calls);
    try testing.expectEqual(@as(u32, 0), after.calls);
}

test "Pipeline.remove keeps handles stable" {
    var pipeline = Pipeline(4).init();
    var first = Tagger{};
    var second = Consumer{};
    var third = Tagger{};

    const first_slot = try pipeline.add(Tagger, &first);
    const second_slot = try pipeline.add(Consumer, &second);
    const third_slot = try pipeline.add(Tagger, &third);

    try testing.expectEqual(@as(u8, 2), third_slot);

    try pipeline.remove(first_slot);
    try pipeline.remove(second_slot);

    const key = make_key('A');
    const result = pipeline.process(&key, final_pass);

    try testing.expectEqual(Response.pass, result);
    try testing.expectEqual(@as(u32, 0), first.calls);
    try testing.expectEqual(@as(u32, 0), second.calls);
    try testing.expectEqual(@as(u32, 1), third.calls);
}

test "Pipeline.remove empty slot" {
    var pipeline = Pipeline(2).init();

    try testing.expectError(error.NotFound, pipeline.remove(0));
}

test "Pipeline.remove invalid slot" {
    var pipeline = Pipeline(2).init();

    try testing.expectError(error.InvalidSlot, pipeline.remove(2));
}

test "Pipeline.remove twice returns not found" {
    var pipeline = Pipeline(2).init();
    var first = Tagger{};

    const slot = try pipeline.add(Tagger, &first);

    try pipeline.remove(slot);
    try testing.expectError(error.NotFound, pipeline.remove(slot));
}

test "Pipeline.add reuses removed slot" {
    var pipeline = Pipeline(2).init();
    var first = Tagger{};
    var second = Tagger{};
    var third = Tagger{};

    const first_slot = try pipeline.add(Tagger, &first);
    const second_slot = try pipeline.add(Tagger, &second);

    try testing.expectEqual(@as(u8, 1), second_slot);
    try pipeline.remove(first_slot);

    const reused_slot = try pipeline.add(Tagger, &third);

    try testing.expectEqual(first_slot, reused_slot);
}

test "Pipeline.add full" {
    var pipeline = Pipeline(1).init();
    var first = Tagger{};
    var second = Tagger{};

    _ = try pipeline.add(Tagger, &first);

    try testing.expectError(error.PipelineFull, pipeline.add(Tagger, &second));
}

test "Pipeline.clear removes all middleware" {
    var pipeline = Pipeline(4).init();
    var first = Tagger{};
    var second = Tagger{};

    _ = try pipeline.add(Tagger, &first);
    _ = try pipeline.add(Tagger, &second);

    pipeline.clear();

    const key = make_key('A');
    const result = pipeline.process(&key, final_pass);

    try testing.expectEqual(Response.pass, result);
    try testing.expectEqual(@as(u32, 0), first.calls);
    try testing.expectEqual(@as(u32, 0), second.calls);
}
