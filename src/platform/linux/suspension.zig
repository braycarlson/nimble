const std = @import("std");

const assert = std.debug.assert;
const posix = std.posix;

requested: std.atomic.Value(bool) = .init(false),
installed: bool = false,
previous: posix.Sigaction = undefined,

const Suspension = @This();

pub const Handler = *const fn (signal: Signal) callconv(.c) void;
pub const Signal = posix.SIG;

pub fn install(suspension: *Suspension, handler: Handler) void {
    assert(!suspension.installed);

    const action = posix.Sigaction{
        .handler = .{ .handler = handler },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };

    posix.sigaction(.TSTP, &action, &suspension.previous);

    suspension.installed = true;

    suspension.requested.store(false, .seq_cst);

    assert(suspension.installed);
    assert(!suspension.pending());
}

pub fn uninstall(suspension: *Suspension) void {
    if (!suspension.installed) {
        return;
    }

    posix.sigaction(.TSTP, &suspension.previous, null);

    suspension.installed = false;

    suspension.requested.store(false, .seq_cst);

    assert(!suspension.installed);
    assert(!suspension.pending());
}

pub fn is_installed(suspension: *const Suspension) bool {
    return suspension.installed;
}

pub fn pending(suspension: *const Suspension) bool {
    return suspension.requested.load(.seq_cst);
}

pub fn request(suspension: *Suspension) void {
    suspension.requested.store(true, .seq_cst);

    assert(suspension.pending());
}

pub fn clear(suspension: *Suspension) void {
    suspension.requested.store(false, .seq_cst);

    assert(!suspension.pending());
}

pub fn stop_self() void {
    posix.raise(.STOP) catch return;
}

const testing = std.testing;

fn ignore(_: Signal) callconv(.c) void {}

test "the suspension starts uninstalled with nothing pending" {
    const suspension: Suspension = .{};

    try testing.expect(!suspension.is_installed());
    try testing.expect(!suspension.pending());
}

test "uninstalling an uninstalled suspension is inert" {
    var suspension: Suspension = .{};

    suspension.uninstall();

    try testing.expect(!suspension.is_installed());
    try testing.expect(!suspension.pending());
}

test "install and uninstall are symmetric and clear the request" {
    var suspension: Suspension = .{};

    suspension.install(ignore);

    try testing.expect(suspension.is_installed());

    suspension.request();

    try testing.expect(suspension.pending());

    suspension.uninstall();

    try testing.expect(!suspension.is_installed());
    try testing.expect(!suspension.pending());
}

test "clear drops a pending request" {
    var suspension: Suspension = .{};

    suspension.request();

    try testing.expect(suspension.pending());

    suspension.clear();

    try testing.expect(!suspension.pending());
}
