const std = @import("std");

const Runtime = @import("runtime.zig");
const win32 = @import("win32.zig");

const assert = std.debug.assert;

stopped: std.atomic.Value(bool) = .init(false),
claim_depth: std.atomic.Value(u32) = .init(0),
thread_id: std.atomic.Value(std.Thread.Id) = .init(0),

const Loop = @This();

const iteration_count_max: u32 = 1024;

comptime {
    assert(iteration_count_max > 0);
}

pub fn claim_thread(loop: *Loop) void {
    const current = std.Thread.getCurrentId();
    const previous = loop.claim_depth.fetchAdd(1, .seq_cst);

    if (previous == 0) {
        loop.thread_id.store(current, .seq_cst);
    }

    assert(loop.thread_id.load(.seq_cst) == current);
    assert(loop.claim_depth.load(.seq_cst) >= 1);
}

pub fn release_thread(loop: *Loop) void {
    if (loop.claim_depth.load(.seq_cst) == 0) {
        return;
    }

    const previous = loop.claim_depth.fetchSub(1, .seq_cst);

    assert(previous >= 1);

    if (previous == 1) {
        loop.thread_id.store(0, .seq_cst);
    }
}

pub fn is_claimed(loop: *const Loop) bool {
    return loop.claim_depth.load(.seq_cst) > 0;
}

pub fn is_loop_thread(loop: *const Loop) bool {
    if (!loop.is_claimed()) {
        return false;
    }

    return loop.thread_id.load(.seq_cst) == std.Thread.getCurrentId();
}

pub fn run(loop: *Loop, runtime: *const Runtime) void {
    assert(runtime.is_open());

    loop.stopped.store(false, .seq_cst);

    loop.claim_thread();
    defer loop.release_thread();

    var message: win32.MSG = std.mem.zeroes(win32.MSG);

    while (!loop.stopped.load(.seq_cst)) {
        if (!runtime.is_open()) break;

        const status = win32.GetMessageW(&message, null, 0, 0);

        if (status <= 0) {
            loop.stopped.store(true, .seq_cst);

            break;
        }

        assert(status > 0);

        _ = win32.TranslateMessage(&message);
        _ = win32.DispatchMessageW(&message);
    }

    assert(loop.stopped.load(.seq_cst) or !runtime.is_open());
}

pub fn poll(loop: *Loop, runtime: *const Runtime, timeout_ms: u32) bool {
    assert(iteration_count_max > 0);

    if (loop.stopped.load(.seq_cst)) return false;
    if (!runtime.is_open()) return false;

    if (timeout_ms > 0) {
        _ = win32.MsgWaitForMultipleObjects(0, null, 0, timeout_ms, win32.QS_ALLINPUT);
    }

    var message: win32.MSG = std.mem.zeroes(win32.MSG);
    var count: u32 = 0;

    while (count < iteration_count_max) : (count += 1) {
        const available = win32.PeekMessageW(&message, null, 0, 0, win32.PM_REMOVE);

        if (available == 0) {
            break;
        }

        if (message.message == win32.WM_QUIT) {
            loop.stopped.store(true, .seq_cst);

            return false;
        }

        _ = win32.TranslateMessage(&message);
        _ = win32.DispatchMessageW(&message);
    }

    assert(count <= iteration_count_max);

    return !loop.stopped.load(.seq_cst);
}

pub fn stop(loop: *Loop) void {
    loop.stopped.store(true, .seq_cst);

    assert(loop.stopped.load(.seq_cst));

    if (loop.is_loop_thread()) {
        win32.PostQuitMessage(0);

        return;
    }

    if (!loop.is_claimed()) {
        return;
    }

    const target: u32 = @intCast(loop.thread_id.load(.seq_cst));

    _ = win32.PostThreadMessageW(target, win32.WM_QUIT, 0, 0);
}

const testing = std.testing;

test "polling a closed runtime reports the loop unrunnable" {
    var loop: Loop = .{};
    const runtime: Runtime = .{};

    try testing.expect(!runtime.is_open());
    try testing.expect(!loop.poll(&runtime, 0));
}

test "stopping before the loop is entered reports the loop unrunnable" {
    var loop: Loop = .{};
    var runtime: Runtime = .{};

    runtime.open(.{});
    defer runtime.close();

    try testing.expect(loop.poll(&runtime, 0));

    loop.stop();

    try testing.expect(!loop.poll(&runtime, 0));
}

test "a thread claim nests and releases back to unclaimed" {
    var loop: Loop = .{};

    loop.release_thread();

    try testing.expect(!loop.is_claimed());
    try testing.expect(!loop.is_loop_thread());

    loop.claim_thread();
    loop.claim_thread();

    try testing.expect(loop.is_claimed());
    try testing.expect(loop.is_loop_thread());

    loop.release_thread();

    try testing.expect(loop.is_loop_thread());

    loop.release_thread();

    try testing.expect(!loop.is_claimed());
    try testing.expect(!loop.is_loop_thread());
}

test "releasing an unclaimed loop thread is inert" {
    var loop: Loop = .{};

    loop.release_thread();
    loop.release_thread();

    try testing.expect(!loop.is_claimed());
    try testing.expectEqual(@as(std.Thread.Id, 0), loop.thread_id.load(.seq_cst));
}
