const std = @import("std");

const key_event = @import("../../event.zig").key;
const win32 = @import("win32.zig");

const assert = std.debug.assert;
const log = std.log.scoped(.nimble_remote);

const Key = key_event.Key;

entries: [entry_count_max]Entry = undefined,
entry_count: u8 = 0,
timer: usize = 0,
procedure: win32.TIMERPROC = null,

const Deferred = @This();

pub const Entry = struct {
    run: *const fn (entry: *const Entry) void,
    owner: *anyopaque,
    generation: u32 = 0,
    id: u32 = 0,
    key: ?Key = null,
};

pub const entry_count_max: u8 = 64;

pub fn push(deferred: *Deferred, entry: Entry) void {
    assert(deferred.entry_count <= entry_count_max);
    assert(deferred.procedure != null);

    if (deferred.entry_count == entry_count_max) {
        log.warn("deferred: the queue is full, dropping a notification", .{});

        return;
    }

    deferred.entries[deferred.entry_count] = entry;
    deferred.entry_count += 1;

    if (deferred.timer != 0) return;

    deferred.timer = win32.SetTimer(null, 0, 0, deferred.procedure);

    if (deferred.timer == 0) deferred.drain();
}

pub fn fire(deferred: *Deferred) void {
    _ = win32.KillTimer(null, deferred.timer);

    deferred.timer = 0;

    deferred.drain();
}

fn drain(deferred: *Deferred) void {
    var batch: [entry_count_max]Entry = undefined;

    const count = deferred.entry_count;

    assert(count <= entry_count_max);

    @memcpy(batch[0..count], deferred.entries[0..count]);

    deferred.entry_count = 0;

    for (batch[0..count]) |*entry| {
        entry.run(entry);
    }
}

pub fn cancel(deferred: *Deferred) void {
    if (deferred.timer != 0) {
        _ = win32.KillTimer(null, deferred.timer);
    }

    deferred.timer = 0;
    deferred.entry_count = 0;

    assert(deferred.timer == 0);
    assert(deferred.entry_count == 0);
}
