const std = @import("std");

const runtime = @import("runtime.zig");
const win32 = @import("win32.zig");

const assert = std.debug.assert;

pub const iteration_count_max: u32 = 1024;

var stopped: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var claim_depth: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
var thread_id: std.atomic.Value(std.Thread.Id) = std.atomic.Value(std.Thread.Id).init(0);

comptime {
    assert(iteration_count_max > 0);
}

pub fn claim_thread() void {
    const current = std.Thread.getCurrentId();
    const previous = claim_depth.fetchAdd(1, .seq_cst);

    if (previous == 0) {
        thread_id.store(current, .seq_cst);
    }

    assert(thread_id.load(.seq_cst) == current);
    assert(claim_depth.load(.seq_cst) >= 1);
}

pub fn release_thread() void {
    if (claim_depth.load(.seq_cst) == 0) {
        return;
    }

    const previous = claim_depth.fetchSub(1, .seq_cst);

    assert(previous >= 1);

    if (previous == 1) {
        thread_id.store(0, .seq_cst);
    }
}

pub fn is_claimed() bool {
    return claim_depth.load(.seq_cst) > 0;
}

pub fn is_loop_thread() bool {
    if (!is_claimed()) {
        return false;
    }

    return thread_id.load(.seq_cst) == std.Thread.getCurrentId();
}

pub fn run() void {
    assert(runtime.is_open());

    stopped.store(false, .seq_cst);

    claim_thread();
    defer release_thread();

    var message: win32.MSG = std.mem.zeroes(win32.MSG);

    while (!stopped.load(.seq_cst) and runtime.is_open()) {
        const status = win32.GetMessageW(&message, null, 0, 0);

        if (status <= 0) {
            stopped.store(true, .seq_cst);

            break;
        }

        assert(status > 0);

        _ = win32.TranslateMessage(&message);
        _ = win32.DispatchMessageW(&message);
    }

    assert(stopped.load(.seq_cst) or !runtime.is_open());
}

pub fn poll(timeout_ms: u32) bool {
    assert(iteration_count_max > 0);

    if (stopped.load(.seq_cst) or !runtime.is_open()) {
        return false;
    }

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
            stopped.store(true, .seq_cst);

            return false;
        }

        _ = win32.TranslateMessage(&message);
        _ = win32.DispatchMessageW(&message);
    }

    assert(count <= iteration_count_max);

    return !stopped.load(.seq_cst);
}

pub fn stop() void {
    stopped.store(true, .seq_cst);

    assert(stopped.load(.seq_cst));

    if (is_loop_thread()) {
        win32.PostQuitMessage(0);

        return;
    }

    if (!is_claimed()) {
        return;
    }

    const target: u32 = @intCast(thread_id.load(.seq_cst));

    _ = win32.PostThreadMessageW(target, win32.WM_QUIT, 0, 0);
}

const testing = std.testing;

test "polling a closed runtime reports the loop unrunnable" {
    runtime.close();

    stopped.store(false, .seq_cst);

    try testing.expect(!runtime.is_open());
    try testing.expect(!poll(0));
}

test "stopping before the loop is entered reports the loop unrunnable" {
    runtime.close();

    try runtime.open(.{});
    defer runtime.close();

    stopped.store(false, .seq_cst);

    try testing.expect(poll(0));

    stop();

    try testing.expect(!poll(0));

    stopped.store(false, .seq_cst);
}

test "a thread claim nests and releases back to unclaimed" {
    release_thread();

    try testing.expect(!is_claimed());
    try testing.expect(!is_loop_thread());

    claim_thread();
    claim_thread();

    try testing.expect(is_claimed());
    try testing.expect(is_loop_thread());

    release_thread();

    try testing.expect(is_loop_thread());

    release_thread();

    try testing.expect(!is_claimed());
    try testing.expect(!is_loop_thread());
}

test "releasing an unclaimed loop thread is inert" {
    release_thread();
    release_thread();

    try testing.expect(!is_claimed());
    try testing.expectEqual(@as(std.Thread.Id, 0), thread_id.load(.seq_cst));
}
