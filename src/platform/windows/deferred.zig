const std = @import("std");

const key_event = @import("../../event/key.zig");
const win32 = @import("win32.zig");

const assert = std.debug.assert;
const log = std.log.scoped(.nimble_remote);

const Key = key_event.Key;

pub const Entry = struct {
    run: *const fn (entry: *const Entry) void,
    owner: *anyopaque,
    generation: u32 = 0,
    id: u32 = 0,
    key: ?Key = null,
};

pub const entry_count_max: u8 = 64;

var entries: [entry_count_max]Entry = undefined;
var entry_count: u8 = 0;
var timer: usize = 0;

pub fn push(entry: Entry) void {
    assert(entry_count <= entry_count_max);

    if (entry_count == entry_count_max) {
        log.warn("deferred: the queue is full, dropping a notification", .{});

        return;
    }

    entries[entry_count] = entry;
    entry_count += 1;

    if (timer != 0) return;

    timer = win32.SetTimer(null, 0, 0, fire);

    if (timer == 0) drain();
}

fn fire(_: ?win32.HWND, _: u32, _: usize, _: u32) callconv(.c) void {
    _ = win32.KillTimer(null, timer);

    timer = 0;

    drain();
}

fn drain() void {
    var batch: [entry_count_max]Entry = undefined;

    const count = entry_count;

    assert(count <= entry_count_max);

    @memcpy(batch[0..count], entries[0..count]);

    entry_count = 0;

    for (batch[0..count]) |*entry| {
        entry.run(entry);
    }
}

const testing = std.testing;
const time = @import("time.zig");

const pump_ms_max: i64 = 1000;
const pump_message_max: u32 = 64;

const Recorder = struct {
    order: [entry_count_max + 1]u32 = @splat(0),
    count: u32 = 0,

    fn run(entry: *const Entry) void {
        const recorder: *Recorder = @ptrCast(@alignCast(entry.owner));

        recorder.order[recorder.count] = entry.id;
        recorder.count += 1;
    }
};

fn pump(recorder: *const Recorder, count: u32, duration_ms: i64) void {
    assert(duration_ms <= pump_ms_max);

    const start_ms = time.now_ms();

    var message: win32.MSG = std.mem.zeroes(win32.MSG);

    while (time.now_ms() - start_ms < duration_ms) {
        if (recorder.count >= count) break;

        var dispatched: u32 = 0;

        while (dispatched < pump_message_max) : (dispatched += 1) {
            if (win32.PeekMessageW(&message, null, 0, 0, win32.PM_REMOVE) == 0) break;

            _ = win32.DispatchMessageW(&message);
        }

        win32.Sleep(5);
    }
}

test "an entry runs once the message loop turns, not when it is pushed" {
    var recorder = Recorder{};

    push(.{ .run = Recorder.run, .owner = &recorder, .id = 7 });

    try testing.expectEqual(@as(u32, 0), recorder.count);

    pump(&recorder, 1, pump_ms_max);

    try testing.expectEqual(@as(u32, 1), recorder.count);
    try testing.expectEqual(@as(u32, 7), recorder.order[0]);
}

test "entries run in the order they were pushed" {
    var recorder = Recorder{};

    push(.{ .run = Recorder.run, .owner = &recorder, .id = 1 });
    push(.{ .run = Recorder.run, .owner = &recorder, .id = 2 });
    push(.{ .run = Recorder.run, .owner = &recorder, .id = 3 });

    pump(&recorder, 3, pump_ms_max);

    try testing.expectEqualSlices(u32, &.{ 1, 2, 3 }, recorder.order[0..recorder.count]);
}

test "a full queue drops what does not fit" {
    testing.log_level = .err;

    var recorder = Recorder{};
    var id: u32 = 0;

    while (id <= entry_count_max) : (id += 1) {
        push(.{ .run = Recorder.run, .owner = &recorder, .id = id });
    }

    pump(&recorder, entry_count_max + 1, 200);

    try testing.expectEqual(@as(u32, entry_count_max), recorder.count);
    try testing.expectEqual(@as(u32, entry_count_max - 1), recorder.order[entry_count_max - 1]);
}
