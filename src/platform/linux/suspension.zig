const std = @import("std");

const assert = std.debug.assert;
const posix = std.posix;

var requested = std.atomic.Value(bool).init(false);
var installed: bool = false;
var previous: posix.Sigaction = undefined;

pub fn install() void {
    assert(!installed);

    const action = posix.Sigaction{
        .handler = .{ .handler = on_terminal_stop },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };

    posix.sigaction(.TSTP, &action, &previous);

    installed = true;

    requested.store(false, .seq_cst);

    assert(installed);
    assert(!pending());
}

pub fn uninstall() void {
    if (!installed) {
        return;
    }

    posix.sigaction(.TSTP, &previous, null);

    installed = false;

    requested.store(false, .seq_cst);

    assert(!installed);
    assert(!pending());
}

pub fn is_installed() bool {
    return installed;
}

pub fn pending() bool {
    return requested.load(.seq_cst);
}

pub fn clear() void {
    requested.store(false, .seq_cst);

    assert(!pending());
}

pub fn stop_self() void {
    posix.raise(.STOP) catch return;
}

fn on_terminal_stop(_: posix.SIG) callconv(.c) void {
    requested.store(true, .seq_cst);
}

const testing = std.testing;

test "the suspension starts uninstalled with nothing pending" {
    try testing.expect(!is_installed());
    try testing.expect(!pending());
}

test "uninstalling an uninstalled suspension is inert" {
    uninstall();

    try testing.expect(!is_installed());
    try testing.expect(!pending());
}

test "install and uninstall are symmetric and clear the request" {
    install();

    try testing.expect(is_installed());

    on_terminal_stop(.TSTP);

    try testing.expect(pending());

    uninstall();

    try testing.expect(!is_installed());
    try testing.expect(!pending());
}

test "clear drops a pending request" {
    on_terminal_stop(.TSTP);

    try testing.expect(pending());

    clear();

    try testing.expect(!pending());
}
