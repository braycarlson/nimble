const std = @import("std");

const contract = @import("../contract.zig");
const device = @import("device.zig");
const evdev = @import("evdev.zig");
const hotplug = @import("hotplug.zig");
const rescue = @import("rescue.zig");
const state = @import("state.zig");
const suspension = @import("suspension.zig");
const time = @import("time.zig");
const timer = @import("timer.zig");
const uinput = @import("uinput.zig");

const assert = std.debug.assert;
const linux = std.os.linux;
const log = std.log.scoped(.nimble);
const posix = std.posix;

pub const Mode = contract.Mode;
pub const Options = contract.Options;

pub const Error = error{
    AlreadyOpen,
    EpollFailed,
    InputGroupMissing,
    NoDevices,
    SynthesisUnavailable,
    UinputInaccessible,
};

pub const discard_batch_max: u16 = 64;
pub const discard_reads_max: u8 = 64;
pub const grab_settle_poll_ms: u32 = 5;
pub const grab_settle_wait_ms_max: u32 = 2000;
pub const chain_lock_retry_max: u8 = 200;
pub const chain_lock_retry_delay_ms: u32 = 10;
pub const chain_lock_path_bytes_max: u16 = 128;
pub const reselect_delay_ms: i64 = 1000;
pub const rescue_regrab_delay_ms: i64 = 3000;
pub const jitter_slot_count: u32 = 16;
pub const jitter_slot_ms: i64 = 53;
pub const jitter_regrab_factor: i64 = 4;
pub const chain_lock_depth_max: u8 = 4;

pub const Selection = enum(u8) {
    secured,
    absent,
    contended,

    pub fn is_valid(selection: Selection) bool {
        return @intFromEnum(selection) <= 2;
    }
};

comptime {
    assert(discard_batch_max > 0);
    assert(discard_reads_max > 0);
    assert(grab_settle_poll_ms > 0);
    assert(grab_settle_wait_ms_max > grab_settle_poll_ms);
    assert(chain_lock_retry_max > 0);
    assert(chain_lock_retry_delay_ms > 0);
    assert(chain_lock_path_bytes_max > 64);
    assert(reselect_delay_ms > 0);
    assert(rescue_regrab_delay_ms > reselect_delay_ms);
    assert(jitter_slot_count > 1);
    assert(jitter_slot_ms > 0);
    assert(jitter_regrab_factor > 0);
    assert(jitter_slot_count * jitter_slot_ms < reselect_delay_ms);
    assert(chain_lock_depth_max > 1);
}

pub const Session = struct {
    devices: device.List = .{},
    keyboard_out: uinput.Device = .{},
    mouse_out: uinput.Device = .{},
    options: Options = .{},
    claim: device.Claim = .{},
    epoll: posix.fd_t = -1,
    reselect_ms: i64 = 0,
    opened: bool = false,

    pub fn is_valid(session: *const Session) bool {
        if (!session.devices.is_valid()) {
            return false;
        }

        if (!session.claim.is_valid()) {
            return false;
        }

        if (session.opened) {
            return session.epoll >= 0;
        }

        return true;
    }

    pub fn grabs(session: *const Session) bool {
        return session.opened and session.options.mode == .grab;
    }

    pub fn synthesises(session: *const Session) bool {
        return session.keyboard_out.is_open() and session.mouse_out.is_open();
    }
};

pub const ReleaseCallback = *const fn () void;

var session_global: Session = .{};
var chain_lock_fd: posix.fd_t = -1;
var chain_lock_depth: u8 = 0;
var grab_deferred: bool = false;
var grab_wanted: bool = false;

var release_callback: std.atomic.Value(?ReleaseCallback) =
    std.atomic.Value(?ReleaseCallback).init(null);

var regrab_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false);
var regrab_ms: i64 = 0;

pub fn open(requested: Options) Error!void {
    assert(requested.is_valid());

    if (session_global.opened) {
        return Error.AlreadyOpen;
    }

    assert(session_global.epoll < 0);

    try probe();

    session_global.options = requested;
    grab_wanted = requested.mode == .grab;

    regrab_requested.store(false, .seq_cst);
    errdefer close();

    try open_synthesis();

    claim_own();

    try open_epoll();
    try open_devices(true);

    register_hotplug();

    timer.set_watch(watch_added, watch_removed) catch return Error.EpollFailed;

    rescue.share_open();
    suspension.install();

    session_global.opened = true;

    assert(session_global.is_valid());
    assert(session_global.epoll >= 0);
    assert(suspension.is_installed());
}

pub fn close() void {
    suspension.uninstall();
    timer.clear_watch();

    _ = device.ungrab_all(&session_global.devices);

    release_pressed_outs();

    device.claim_close(&session_global.claim);

    session_global.keyboard_out.destroy();
    session_global.mouse_out.destroy();

    hotplug.close();
    state.clear_sources();
    session_global.devices.close_all();

    if (session_global.epoll >= 0) {
        _ = linux.close(session_global.epoll);
        session_global.epoll = -1;
    }

    rescue.reset();
    rescue.share_close();

    session_global.options = .{};
    session_global.reselect_ms = 0;
    session_global.opened = false;
    grab_wanted = false;
    regrab_ms = 0;

    regrab_requested.store(false, .seq_cst);

    assert(session_global.epoll < 0);
    assert(!session_global.synthesises());
    assert(session_global.claim.is_valid());
    assert(chain_lock_depth == 0);
    assert(chain_lock_fd < 0);
}

pub fn is_open() bool {
    return session_global.opened;
}

pub fn mode() Mode {
    return session_global.options.mode;
}

pub fn current() *Session {
    return &session_global;
}

pub fn refresh() void {
    assert(session_global.opened);
    assert(session_global.epoll >= 0);

    const keyboard_had = session_global.devices.count_grabbed(.keyboard) > 0;
    const mouse_had = session_global.devices.count_grabbed(.mouse) > 0;

    _ = device.close_dead(&session_global.devices);

    if (keyboard_had and session_global.devices.count_grabbed(.keyboard) == 0) {
        log.info("refresh: keyboard source lost, releasing held virtual keys", .{});

        session_global.keyboard_out.release_pressed();
    }

    if (mouse_had and session_global.devices.count_grabbed(.mouse) == 0) {
        log.info("refresh: mouse source lost, releasing held virtual keys", .{});

        session_global.mouse_out.release_pressed();
    }

    scan_new();

    if (session_global.options.mode == .grab) {
        ensure_kind(.keyboard);
        ensure_kind(.mouse);
    }

    rebuild_sources();

    assert(session_global.devices.is_valid());
    assert(session_global.claim.is_valid());
}

pub fn release_grab() void {
    const was_grabbing = session_global.opened and session_global.options.mode == .grab;

    if (was_grabbing) {
        log.info("release_grab: dropping every grab", .{});
    }

    _ = device.ungrab_all(&session_global.devices);

    release_pressed_outs();

    device.claim_hold(&session_global.claim, .keyboard);
    device.claim_hold(&session_global.claim, .mouse);

    session_global.options.mode = .observe;
    session_global.reselect_ms = 0;

    assert(session_global.options.mode == .observe);
    assert(session_global.reselect_ms == 0);

    if (was_grabbing) {
        notify_release();
    }
}

pub fn acquire_grab() void {
    if (!session_global.opened) {
        return;
    }

    if (!grab_wanted) {
        return;
    }

    regrab_requested.store(true, .seq_cst);

    assert(regrab_requested.load(.seq_cst));
}

pub fn set_release_callback(callback: ?ReleaseCallback) void {
    release_callback.store(callback, .seq_cst);
}

pub fn schedule_regrab() void {
    if (!session_global.opened) {
        return;
    }

    if (!grab_wanted) {
        return;
    }

    if (!session_global.options.rescue) {
        return;
    }

    regrab_ms = time.now_ms() + rescue_regrab_delay_ms + retry_jitter_ms() * jitter_regrab_factor;

    assert(regrab_ms > 0);
}

pub fn regrab_if_requested() void {
    const requested = regrab_requested.load(.seq_cst);
    const due = regrab_ms > 0 and time.now_ms() >= regrab_ms;

    if (!requested and !due) {
        return;
    }

    regrab_requested.store(false, .seq_cst);

    regrab_ms = 0;

    if (!session_global.opened) {
        return;
    }

    assert(grab_wanted);

    if (session_global.options.mode == .grab) {
        return;
    }

    session_global.options.mode = .grab;

    log.info("regrab: restoring grab mode", .{});

    rescue.reset();
    refresh();

    assert(session_global.options.mode == .grab);
}

fn notify_release() void {
    const callback = release_callback.load(.seq_cst) orelse return;

    callback();
}

pub fn reselect_if_due() void {
    if (session_global.reselect_ms == 0) {
        return;
    }

    assert(session_global.opened);
    assert(session_global.reselect_ms > 0);

    if (time.now_ms() < session_global.reselect_ms) {
        return;
    }

    session_global.reselect_ms = 0;

    refresh();
}

pub fn suspend_if_requested() void {
    if (!suspension.pending()) {
        return;
    }

    assert(session_global.opened);

    _ = device.ungrab_all(&session_global.devices);

    release_pressed_outs();

    suspension.clear();
    suspension.stop_self();

    discard_pending_events();
    refresh();
    rescue.reset();

    assert(!suspension.pending());
}

fn release_pressed_outs() void {
    session_global.keyboard_out.release_pressed();
    session_global.mouse_out.release_pressed();
}

fn discard_pending_events() void {
    var index: u8 = 0;

    while (index < session_global.devices.count) : (index += 1) {
        discard_device_events(session_global.devices.devices[index].fd);
    }

    assert(index == session_global.devices.count);
}

fn discard_device_events(fd: posix.fd_t) void {
    assert(fd >= 0);

    var batch: [discard_batch_max]evdev.Event = undefined;
    var reads: u8 = 0;

    while (reads < discard_reads_max) : (reads += 1) {
        const count = evdev.read_events(fd, &batch) catch return;

        if (count == 0) {
            return;
        }
    }

    assert(reads <= discard_reads_max);
}

fn probe() Error!void {
    device.probe_permissions() catch |err| return switch (err) {
        error.InputGroupMissing => Error.InputGroupMissing,
        error.UinputInaccessible => Error.UinputInaccessible,
        else => Error.NoDevices,
    };
}

fn open_epoll() Error!void {
    assert(session_global.epoll < 0);

    const created = linux.epoll_create1(linux.EPOLL.CLOEXEC);

    if (posix.errno(created) != .SUCCESS) {
        return Error.EpollFailed;
    }

    session_global.epoll = @intCast(created);

    assert(session_global.epoll >= 0);
}

fn open_synthesis() Error!void {
    if (!session_global.options.synthesis) {
        return;
    }

    const role: uinput.Role = if (session_global.options.mode == .grab) .relay else .inject;

    session_global.keyboard_out = uinput.create(.keyboard, role) catch {
        return Error.SynthesisUnavailable;
    };

    session_global.mouse_out = uinput.create(.mouse, role) catch {
        return Error.SynthesisUnavailable;
    };

    assert(session_global.synthesises());
}

fn open_devices(settle: bool) Error!void {
    assert(session_global.devices.count == 0);
    assert(session_global.epoll >= 0);

    device.scan(&session_global.devices) catch {
        session_global.devices.close_all();

        return Error.NoDevices;
    };

    if (session_global.devices.count == 0) {
        return Error.NoDevices;
    }

    if (session_global.options.mode == .grab) {
        select_sources(settle);
    }
    errdefer unwind_devices();

    var index: u8 = 0;

    while (index < session_global.devices.count) : (index += 1) {
        const fd = session_global.devices.devices[index].fd;
        const added = state.add_source(fd);

        assert(device.origin_of(fd) != .own);
        assert(added);

        try watch(fd);
    }

    assert(index == session_global.devices.count);
    assert(session_global.devices.count <= state.source_count_max);
}

fn unwind_devices() void {
    unwatch_devices();

    _ = device.ungrab_all(&session_global.devices);

    state.clear_sources();
    session_global.devices.close_all();

    assert(session_global.devices.count == 0);
}

fn claim_own() void {
    const held = chain_lock_hold(true);
    defer chain_lock_drop(held);

    device.claim_open(&session_global.claim);

    if (session_global.options.mode == .grab) {
        device.claim_hold(&session_global.claim, .keyboard);
        device.claim_hold(&session_global.claim, .mouse);
    }

    assert(session_global.claim.is_valid());
}

fn scan_new() void {
    var index: u8 = 0;

    while (index < device.device_index_max) : (index += 1) {
        if (session_global.devices.count == device.device_count_max) {
            return;
        }

        var buffer: [device.path_bytes_max]u8 = @splat(0);
        const path = device.build_path(&buffer, index) orelse continue;

        if (session_global.devices.find_path(std.mem.span(path)) != null) {
            continue;
        }

        const opened = device.open_at(index) orelse continue;

        session_global.devices.devices[session_global.devices.count] = opened;
        session_global.devices.count += 1;

        watch(opened.fd) catch {
            evdev.close(opened.fd);
            session_global.devices.count -= 1;
        };
    }

    assert(session_global.devices.is_valid());
}

fn rebuild_sources() void {
    state.clear_sources();

    var index: u8 = 0;

    while (index < session_global.devices.count) : (index += 1) {
        const added = state.add_source(session_global.devices.devices[index].fd);

        assert(added);
    }

    assert(index == session_global.devices.count);
}

fn ensure_kind(kind: device.Kind) void {
    assert(session_global.options.mode == .grab);
    assert(kind != .other);

    const grabbed = session_global.devices.count_grabbed(kind);

    if (grabbed == 0) {
        reselect_kind(kind);

        return;
    }

    const direct = session_global.devices.count_grabbed_origin(kind, .direct);

    if (direct > 0) {
        extend_direct(kind);
    }

    _ = device.close_where(&session_global.devices, kind, .not_grabbed);

    assert(session_global.devices.count_grabbed(kind) > 0);
}

fn extend_direct(kind: device.Kind) void {
    const total = session_global.devices.count_of_origin(kind, .direct);
    const grabbed_before = session_global.devices.count_grabbed_origin(kind, .direct);

    assert(grabbed_before > 0);
    assert(grabbed_before <= total);

    if (grabbed_before == total) {
        return;
    }

    const added = device.grab_all(&session_global.devices, kind, .direct);

    if (grabbed_before + added < total) {
        schedule_reselect();
    }
}

fn reselect_kind(kind: device.Kind) void {
    assert(session_global.options.mode == .grab);
    assert(kind != .other);

    const held = chain_lock_hold(false);

    if (!held) {
        schedule_reselect();

        return;
    }
    defer chain_lock_drop(held);

    grab_deferred = false;

    const selection = select_kind(kind);

    assert(selection.is_valid());

    log.info("reselect {s}: {s}{s}", .{
        @tagName(kind),
        @tagName(selection),
        if (grab_deferred) " (deferred: keys held)" else "",
    });

    if (grab_deferred or selection == .contended) {
        schedule_reselect();
    }
}

fn schedule_reselect() void {
    session_global.reselect_ms = time.now_ms() + reselect_delay_ms + retry_jitter_ms();

    assert(session_global.reselect_ms > 0);
}

fn retry_jitter_ms() i64 {
    const slot = uinput.pid_self() % jitter_slot_count;

    assert(slot < jitter_slot_count);

    return @as(i64, slot) * jitter_slot_ms;
}

fn select_sources(settle: bool) void {
    assert(session_global.options.mode == .grab);

    if (settle and !wait_for_keys_released()) {
        schedule_reselect();

        return;
    }

    const held = chain_lock_hold(settle);

    if (!held) {
        schedule_reselect();

        return;
    }
    defer chain_lock_drop(held);

    grab_deferred = false;

    const keyboard = select_kind(.keyboard);
    const mouse = select_kind(.mouse);

    assert(keyboard.is_valid());
    assert(mouse.is_valid());

    session_global.reselect_ms = if (grab_deferred)
        time.now_ms() + reselect_delay_ms
    else
        reselect_deadline(keyboard, mouse);

    assert(session_global.devices.is_valid());
    assert(session_global.claim.is_valid());
}

fn reselect_deadline(keyboard: Selection, mouse: Selection) i64 {
    assert(keyboard.is_valid());
    assert(mouse.is_valid());

    if (keyboard == .secured or mouse == .secured) {
        return 0;
    }

    if (keyboard != .contended and mouse != .contended) {
        return 0;
    }

    const deadline = time.now_ms() + reselect_delay_ms;

    assert(deadline > 0);

    return deadline;
}

fn select_kind(kind: device.Kind) Selection {
    assert(kind.is_valid());
    assert(kind != .other);
    assert(chain_lock_depth > 0);

    const present = session_global.devices.count_of(kind) > 0;

    if (any_key_down()) {
        grab_deferred = true;
    }

    if (!elder_present(kind)) {
        const total = session_global.devices.count_of_origin(kind, .direct);
        const direct = device.grab_all(&session_global.devices, kind, .direct);

        assert(direct <= total);

        if (direct > 0 and direct == total) {
            return select_secured(kind);
        }

        if (direct > 0) {
            _ = device.ungrab_where(&session_global.devices, kind, .direct);
        }
    }

    if (chain_kind(kind)) {
        return select_secured(kind);
    }

    _ = device.close_where(&session_global.devices, kind, .not_grabbed);

    device.claim_hold(&session_global.claim, kind);

    if (present) {
        return .contended;
    }

    return .absent;
}

fn elder_present(kind: device.Kind) bool {
    assert(kind != .other);

    const out = out_of(kind);

    if (!out.is_open()) {
        return false;
    }

    const own = device.Order{ .stamp_ms = out.stamp_ms, .pid = uinput.pid_self() };

    return device.chain_elder_present(&session_global.devices, kind, own);
}

fn select_secured(kind: device.Kind) Selection {
    assert(kind != .other);

    _ = device.close_where(&session_global.devices, kind, .not_grabbed);

    device.claim_release(&session_global.claim, kind);

    assert(session_global.claim.is_valid());

    return .secured;
}

fn chain_kind(kind: device.Kind) bool {
    assert(kind.is_valid());
    assert(session_global.options.mode == .grab);

    const out = out_of(kind);

    if (!out.is_open()) {
        return false;
    }

    const own = device.Order{ .stamp_ms = out.stamp_ms, .pid = uinput.pid_self() };

    return device.grab_chain(&session_global.devices, kind, own) != null;
}

fn out_of(kind: device.Kind) *const uinput.Device {
    return switch (kind) {
        .keyboard => &session_global.keyboard_out,
        .mouse => &session_global.mouse_out,
        .other => unreachable,
    };
}

fn chain_lock_hold(blocking: bool) bool {
    assert(chain_lock_depth < chain_lock_depth_max);

    if (chain_lock_depth > 0) {
        assert(chain_lock_fd >= 0);

        chain_lock_depth += 1;

        return true;
    }

    assert(chain_lock_fd < 0);

    const attempt_max: u8 = if (blocking) chain_lock_retry_max else 1;
    const fd = chain_lock_acquire(attempt_max) orelse return false;

    chain_lock_fd = fd;
    chain_lock_depth = 1;

    assert(chain_lock_fd >= 0);
    assert(chain_lock_depth == 1);

    return true;
}

fn chain_lock_drop(held: bool) void {
    if (!held) {
        return;
    }

    assert(chain_lock_depth > 0);
    assert(chain_lock_fd >= 0);

    chain_lock_depth -= 1;

    if (chain_lock_depth > 0) {
        return;
    }

    chain_lock_release(chain_lock_fd);

    chain_lock_fd = -1;

    assert(chain_lock_fd < 0);
    assert(chain_lock_depth == 0);
}

fn chain_lock_acquire(attempt_max: u8) ?posix.fd_t {
    assert(attempt_max > 0);

    const fd = chain_lock_open() orelse return null;

    var attempt: u8 = 0;

    while (attempt < attempt_max) : (attempt += 1) {
        const status = linux.flock(fd, posix.LOCK.EX | posix.LOCK.NB);

        if (posix.errno(status) == .SUCCESS) {
            return fd;
        }

        if (attempt + 1 < attempt_max) {
            time.sleep_ms(chain_lock_retry_delay_ms);
        }
    }

    assert(attempt == attempt_max);

    _ = linux.close(fd);

    return null;
}

fn chain_lock_release(fd: posix.fd_t) void {
    assert(fd >= 0);

    _ = linux.flock(fd, posix.LOCK.UN);
    _ = linux.close(fd);
}

fn chain_lock_open() ?posix.fd_t {
    var runtime_buffer: [chain_lock_path_bytes_max]u8 = @splat(0);
    var shared_buffer: [chain_lock_path_bytes_max]u8 = @splat(0);

    const runtime_path = chain_lock_path(&runtime_buffer, "/run/user/{d}/nimble-chain.lock");
    const shared_path = chain_lock_path(&shared_buffer, "/tmp/nimble-chain-{d}.lock");

    if (runtime_path) |path| {
        if (chain_lock_open_path(path)) |fd| {
            return fd;
        }
    }

    const path = shared_path orelse return null;

    return chain_lock_open_path(path);
}

fn chain_lock_open_path(path: [*:0]const u8) ?posix.fd_t {
    const flags = posix.O{ .ACCMODE = .RDWR, .CREAT = true, .CLOEXEC = true };

    return posix.openatZ(posix.AT.FDCWD, path, flags, 0o600) catch null;
}

fn chain_lock_path(
    buffer: *[chain_lock_path_bytes_max]u8,
    comptime format: []const u8,
) ?[*:0]const u8 {
    const room = buffer[0 .. chain_lock_path_bytes_max - 1];
    const written = std.fmt.bufPrint(room, format, .{linux.getuid()}) catch return null;

    assert(written.len < chain_lock_path_bytes_max);

    buffer[written.len] = 0;

    return @ptrCast(buffer);
}

fn register_hotplug() void {
    assert(session_global.epoll >= 0);

    if (!hotplug.open()) {
        return;
    }

    watch(hotplug.handle()) catch hotplug.close();
}

fn wait_for_keys_released() bool {
    var waited: u32 = 0;

    while (waited < grab_settle_wait_ms_max) : (waited += grab_settle_poll_ms) {
        assert(waited < grab_settle_wait_ms_max);

        if (!any_key_down()) {
            return true;
        }

        time.sleep_ms(grab_settle_poll_ms);
    }

    return !any_key_down();
}

fn any_key_down() bool {
    var index: u8 = 0;

    while (index < session_global.devices.count) : (index += 1) {
        if (device_key_down(session_global.devices.devices[index].fd)) {
            return true;
        }
    }

    assert(index == session_global.devices.count);

    return false;
}

fn device_key_down(fd: posix.fd_t) bool {
    assert(fd >= 0);

    var bits: [evdev.KEY_BYTES]u8 = @splat(0);

    evdev.key_state(fd, &bits) catch return false;

    for (bits) |byte| {
        if (byte != 0) {
            return true;
        }
    }

    return false;
}

fn unwatch_devices() void {
    var index: u8 = 0;

    while (index < session_global.devices.count) : (index += 1) {
        unwatch(session_global.devices.devices[index].fd);
    }

    assert(index == session_global.devices.count);
}

pub fn watch(fd: posix.fd_t) Error!void {
    assert(fd >= 0);

    if (session_global.epoll < 0) {
        return;
    }

    var wake = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .fd = fd } };
    const status = linux.epoll_ctl(session_global.epoll, linux.EPOLL.CTL_ADD, fd, &wake);

    if (posix.errno(status) != .SUCCESS) {
        return Error.EpollFailed;
    }
}

pub fn unwatch(fd: posix.fd_t) void {
    if (session_global.epoll < 0 or fd < 0) {
        return;
    }

    _ = linux.epoll_ctl(session_global.epoll, linux.EPOLL.CTL_DEL, fd, null);
}

fn watch_added(fd: posix.fd_t) timer.WatchError!void {
    watch(fd) catch return timer.WatchError.WatchFailed;
}

fn watch_removed(fd: posix.fd_t) void {
    unwatch(fd);
}

const testing = std.testing;

test "a fresh session_global is closed and owns nothing" {
    const fresh = Session{};

    try testing.expect(fresh.is_valid());
    try testing.expect(!fresh.opened);
    try testing.expect(!fresh.grabs());
    try testing.expect(!fresh.synthesises());
    try testing.expect(fresh.epoll < 0);
}

test "a closed runtime reports observe mode" {
    close();

    try testing.expect(!is_open());
    try testing.expectEqual(Mode.observe, mode());
}

test "the runtime shares the contract vocabulary" {
    try testing.expectEqual(contract.Mode, Mode);
    try testing.expectEqual(contract.Options, Options);
}

test "the selection covers exactly the outcomes a kind can reach" {
    try testing.expect(Selection.secured.is_valid());
    try testing.expect(Selection.absent.is_valid());
    try testing.expect(Selection.contended.is_valid());
    try testing.expectEqual(@as(u8, 3), @typeInfo(Selection).@"enum".fields.len);
}

test "a reselect is scheduled only when contention left the session_global sourceless" {
    try testing.expectEqual(@as(i64, 0), reselect_deadline(.secured, .contended));
    try testing.expectEqual(@as(i64, 0), reselect_deadline(.contended, .secured));
    try testing.expectEqual(@as(i64, 0), reselect_deadline(.secured, .absent));
    try testing.expectEqual(@as(i64, 0), reselect_deadline(.absent, .absent));

    try testing.expect(reselect_deadline(.contended, .contended) > 0);
    try testing.expect(reselect_deadline(.contended, .absent) > 0);
    try testing.expect(reselect_deadline(.absent, .contended) > 0);
}

test "a session_global with no pending reselect ignores the due check" {
    const saved = session_global.reselect_ms;
    defer session_global.reselect_ms = saved;

    session_global.reselect_ms = 0;

    reselect_if_due();

    try testing.expectEqual(@as(i64, 0), session_global.reselect_ms);
}

test "the chain lock nests within one process and releases once at the end" {
    try testing.expectEqual(@as(u8, 0), chain_lock_depth);
    try testing.expect(chain_lock_fd < 0);

    const outer = chain_lock_hold(true);

    if (!outer) {
        return error.SkipZigTest;
    }

    try testing.expectEqual(@as(u8, 1), chain_lock_depth);
    try testing.expect(chain_lock_fd >= 0);

    const inner = chain_lock_hold(false);

    try testing.expect(inner);
    try testing.expectEqual(@as(u8, 2), chain_lock_depth);

    chain_lock_drop(inner);

    try testing.expectEqual(@as(u8, 1), chain_lock_depth);
    try testing.expect(chain_lock_fd >= 0);

    chain_lock_drop(outer);

    try testing.expectEqual(@as(u8, 0), chain_lock_depth);
    try testing.expect(chain_lock_fd < 0);
}

test "dropping a lock that was never held leaves the depth alone" {
    const depth = chain_lock_depth;

    chain_lock_drop(false);

    try testing.expectEqual(depth, chain_lock_depth);
    try testing.expect(chain_lock_fd < 0);
}

test "the chain lock is exclusive while held and reusable after release" {
    const first = chain_lock_acquire(1) orelse return error.LockUnavailable;

    try testing.expect(chain_lock_acquire(1) == null);

    chain_lock_release(first);

    const second = chain_lock_acquire(1) orelse return error.LockUnavailable;

    chain_lock_release(second);
}

test "the chain lock path is bounded and null terminated" {
    var buffer: [chain_lock_path_bytes_max]u8 = @splat(0);
    const format = "/tmp/nimble-chain-{d}.lock";
    const path = chain_lock_path(&buffer, format) orelse return error.PathUnavailable;
    const length = std.mem.len(path);

    try testing.expect(length > 0);
    try testing.expect(length < chain_lock_path_bytes_max);
    try testing.expect(std.mem.indexOf(u8, path[0..length], "nimble-chain") != null);
}
