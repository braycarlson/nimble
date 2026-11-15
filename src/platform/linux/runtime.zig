const std = @import("std");

const Clipboard = @import("clipboard.zig");
const device = @import("device.zig");
const evdev = @import("evdev.zig");
const Hotplug = @import("hotplug.zig");
const interface = @import("../interface.zig");
const Monitor = @import("monitor.zig");
const Rescue = @import("rescue.zig");
const State = @import("state.zig");
const Suspension = @import("suspension.zig");
const time = @import("time.zig");
const Timer = @import("timer.zig");
const uinput = @import("uinput.zig");

const assert = std.debug.assert;
const linux = std.os.linux;
const log = std.log.scoped(.nimble);
const posix = std.posix;

const Mode = interface.Mode;
const Options = interface.Options;
const ReleaseCallback = interface.ReleaseCallback;

session: Session = .{},
chain_lock_fd: posix.fd_t = -1,
chain_lock_depth: u8 = 0,
grab_deferred: bool = false,
grab_wanted: bool = false,
release_callback: ?ReleaseCallback = null,
regrab_requested: std.atomic.Value(bool) = .init(false),
regrab_ms: i64 = 0,
peers: Peers,

const Runtime = @This();

pub const Peers = struct {
    clipboard: *Clipboard,
    hotplug: *Hotplug,
    monitor: *Monitor,
    rescue: *Rescue,
    state: *State,
    suspension: *Suspension,
    timer: *Timer,
};

pub const Error = error{
    DevicesMissing,
    DisplayInvalid,
    EpollFailed,
    InputGroupMissing,
    SynthesisUnavailable,
    UinputInaccessible,
};

const display_default = "wayland-0";
const display_bytes_max: u16 = Monitor.socket_bytes_max;

const discard_batch_max: u16 = 64;
const discard_reads_max: u8 = 64;
const grab_settle_poll_ms: u32 = 5;
const grab_settle_wait_ms_max: u32 = 2000;
const chain_lock_retry_max: u8 = 200;
const chain_lock_retry_delay_ms: u32 = 10;
const chain_lock_path_bytes_max: u16 = 128;
const reselect_delay_ms: i64 = 1000;
const rescue_regrab_delay_ms: i64 = 3000;
const jitter_slot_count: u32 = 16;
const jitter_slot_ms: i64 = 53;
pub const jitter_regrab_factor: i64 = 4;
const chain_lock_depth_max: u8 = 4;

pub const Selection = enum(u8) {
    secured,
    absent,
    contended,

    pub fn is_valid(selection: Selection) bool {
        return @backingInt(selection) <= 2;
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
    inputs: device.List = .{},
    keyboard_out: uinput.Device = .{},
    mouse_out: uinput.Device = .{},
    options: Options = .{},
    claim: device.Claim = .{},
    epoll: posix.fd_t = -1,
    reselect_ms: i64 = 0,
    opened: bool = false,

    pub fn is_valid(session: *const Session) bool {
        if (!session.inputs.is_valid()) {
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

pub fn open(runtime: *Runtime, requested: Options, handler: Suspension.Handler) Error!void {
    assert(requested.is_valid());
    assert(!runtime.session.opened);
    assert(runtime.session.epoll < 0);

    try probe();
    try runtime.configure_display(&requested);

    runtime.session.options = requested;
    runtime.session.options.wayland_display = null;
    runtime.session.options.xdg_runtime_dir = null;
    runtime.grab_wanted = requested.mode == .grab;

    runtime.regrab_requested.store(false, .seq_cst);
    errdefer runtime.close();

    try runtime.open_synthesis();

    runtime.claim_own();

    try runtime.open_epoll();
    try runtime.open_devices(true);

    runtime.register_hotplug();

    const timer_watch = Timer.Watch{
        .context = runtime,
        .add = watch_added,
        .remove = watch_removed,
    };

    runtime.peers.timer.set_watch(timer_watch) catch return Error.EpollFailed;

    runtime.peers.rescue.share_open();
    runtime.peers.suspension.install(handler);

    runtime.session.opened = true;

    assert(runtime.session.is_valid());
    assert(runtime.session.epoll >= 0);
    assert(runtime.peers.suspension.is_installed());
}

pub fn close(runtime: *Runtime) void {
    runtime.peers.suspension.uninstall();
    runtime.peers.timer.clear_watch();

    _ = device.ungrab_all(&runtime.session.inputs);

    runtime.release_pressed_outs();

    device.claim_close(&runtime.session.claim);

    runtime.session.keyboard_out.destroy();
    runtime.session.mouse_out.destroy();

    runtime.peers.hotplug.close();
    runtime.peers.state.clear_sources();
    runtime.session.inputs.close_all();

    if (runtime.session.epoll >= 0) {
        _ = linux.close(runtime.session.epoll);
        runtime.session.epoll = -1;
    }

    runtime.peers.rescue.reset();
    runtime.peers.rescue.share_close();

    runtime.peers.clipboard.unconfigure();
    runtime.peers.monitor.unconfigure();

    runtime.session.options = .{};
    runtime.session.reselect_ms = 0;
    runtime.session.opened = false;
    runtime.grab_wanted = false;
    runtime.regrab_ms = 0;

    runtime.regrab_requested.store(false, .seq_cst);

    assert(runtime.session.epoll < 0);
    assert(!runtime.session.synthesises());
    assert(runtime.session.claim.is_valid());
    assert(runtime.chain_lock_depth == 0);
    assert(runtime.chain_lock_fd < 0);
}

pub fn is_open(runtime: *const Runtime) bool {
    return runtime.session.opened;
}

pub fn mode(runtime: *const Runtime) Mode {
    return runtime.session.options.mode;
}

pub fn refresh(runtime: *Runtime) void {
    assert(runtime.session.opened);
    assert(runtime.session.epoll >= 0);

    const keyboard_had = runtime.session.inputs.count_grabbed(.keyboard) > 0;
    const mouse_had = runtime.session.inputs.count_grabbed(.mouse) > 0;

    _ = device.close_dead(&runtime.session.inputs);

    if (keyboard_had) {
        if (runtime.session.inputs.count_grabbed(.keyboard) == 0) {
            log.info("refresh: keyboard source lost, releasing held virtual keys", .{});

            runtime.session.keyboard_out.release_pressed();
        }
    }

    if (mouse_had) {
        if (runtime.session.inputs.count_grabbed(.mouse) == 0) {
            log.info("refresh: mouse source lost, releasing held virtual keys", .{});

            runtime.session.mouse_out.release_pressed();
        }
    }

    runtime.scan_new();

    if (runtime.session.options.mode == .grab) {
        runtime.ensure_kind(.keyboard);
        runtime.ensure_kind(.mouse);
    }

    runtime.rebuild_sources();

    assert(runtime.session.inputs.is_valid());
    assert(runtime.session.claim.is_valid());
}

pub fn release_grab(runtime: *Runtime) void {
    const was_grabbing = runtime.session.opened and runtime.session.options.mode == .grab;

    if (was_grabbing) {
        log.info("release_grab: dropping every grab", .{});
    }

    _ = device.ungrab_all(&runtime.session.inputs);

    runtime.release_pressed_outs();

    device.claim_hold(&runtime.session.claim, .keyboard);
    device.claim_hold(&runtime.session.claim, .mouse);

    runtime.session.options.mode = .observe;
    runtime.session.reselect_ms = 0;

    assert(runtime.session.options.mode == .observe);
    assert(runtime.session.reselect_ms == 0);

    if (was_grabbing) {
        runtime.notify_release();
    }
}

pub fn acquire_grab(runtime: *Runtime) void {
    if (!runtime.session.opened) {
        return;
    }

    if (!runtime.grab_wanted) {
        return;
    }

    runtime.regrab_requested.store(true, .seq_cst);

    assert(runtime.regrab_requested.load(.seq_cst));
}

pub fn set_release_callback(runtime: *Runtime, callback: ?ReleaseCallback) void {
    runtime.release_callback = callback;
}

pub fn schedule_regrab(runtime: *Runtime) void {
    if (!runtime.session.opened) {
        return;
    }

    if (!runtime.grab_wanted) {
        return;
    }

    if (!runtime.session.options.rescue) {
        return;
    }

    const jitter_ms = retry_jitter_ms() * jitter_regrab_factor;

    runtime.regrab_ms = time.now_ms() + rescue_regrab_delay_ms + jitter_ms;

    assert(runtime.regrab_ms > 0);
}

pub fn regrab_if_requested(runtime: *Runtime) void {
    const requested = runtime.regrab_requested.load(.seq_cst);
    const due = runtime.regrab_ms > 0 and time.now_ms() >= runtime.regrab_ms;

    if (!requested) {
        if (!due) return;
    }

    runtime.regrab_requested.store(false, .seq_cst);

    runtime.regrab_ms = 0;

    if (!runtime.session.opened) {
        return;
    }

    assert(runtime.grab_wanted);

    if (runtime.session.options.mode == .grab) {
        return;
    }

    runtime.session.options.mode = .grab;

    log.info("regrab: restoring grab mode", .{});

    runtime.peers.rescue.reset();
    runtime.refresh();

    assert(runtime.session.options.mode == .grab);
}

fn notify_release(runtime: *Runtime) void {
    const callback = runtime.release_callback orelse return;

    callback.invoke(callback.context);
}

pub fn reselect_if_due(runtime: *Runtime) void {
    if (runtime.session.reselect_ms == 0) {
        return;
    }

    assert(runtime.session.opened);
    assert(runtime.session.reselect_ms > 0);

    if (time.now_ms() < runtime.session.reselect_ms) {
        return;
    }

    runtime.session.reselect_ms = 0;

    runtime.refresh();
}

pub fn suspend_if_requested(runtime: *Runtime) void {
    if (!runtime.peers.suspension.pending()) {
        return;
    }

    assert(runtime.session.opened);

    _ = device.ungrab_all(&runtime.session.inputs);

    runtime.release_pressed_outs();

    runtime.peers.suspension.clear();

    Suspension.stop_self();

    runtime.discard_pending_events();
    runtime.refresh();
    runtime.peers.rescue.reset();

    assert(!runtime.peers.suspension.pending());
}

fn release_pressed_outs(runtime: *Runtime) void {
    runtime.session.keyboard_out.release_pressed();
    runtime.session.mouse_out.release_pressed();
}

fn discard_pending_events(runtime: *Runtime) void {
    var index: u8 = 0;

    while (index < runtime.session.inputs.count) : (index += 1) {
        discard_device_events(runtime.session.inputs.devices[index].fd);
    }

    assert(index == runtime.session.inputs.count);
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
        else => Error.DevicesMissing,
    };
}

fn display_configured(options: *const Options) bool {
    if (options.wayland_display != null) return true;
    return options.xdg_runtime_dir != null;
}

fn display_path(options: *const Options, buffer: *[display_bytes_max]u8) Error![]const u8 {
    assert(display_configured(options));

    const display = options.wayland_display orelse display_default;

    if (display.len == 0) {
        return Error.DisplayInvalid;
    }

    if (display[0] == '/') {
        if (display.len >= display_bytes_max) return Error.DisplayInvalid;
        return display;
    }

    const directory = options.xdg_runtime_dir orelse return Error.DisplayInvalid;

    const path = std.mem.print(buffer, "{s}/{s}", .{ directory, display }) catch {
        return Error.DisplayInvalid;
    };

    if (path.len >= display_bytes_max) {
        return Error.DisplayInvalid;
    }

    assert(path.len > display.len);

    return path;
}

fn configure_display(runtime: *Runtime, options: *const Options) Error!void {
    if (!display_configured(options)) return;

    var buffer: [display_bytes_max]u8 = undefined;

    const path = try display_path(options, &buffer);

    assert(path.len > 0);
    assert(path.len < display_bytes_max);

    const clipboard_configured = runtime.peers.clipboard.configure(path);
    const monitor_configured = runtime.peers.monitor.configure(path);

    assert(clipboard_configured);
    assert(monitor_configured);
}

fn open_epoll(runtime: *Runtime) Error!void {
    assert(runtime.session.epoll < 0);

    const created = linux.epoll_create1(linux.EPOLL.CLOEXEC);

    if (linux.errno(created) != .SUCCESS) {
        return Error.EpollFailed;
    }

    runtime.session.epoll = @intCast(created);

    assert(runtime.session.epoll >= 0);
}

fn open_synthesis(runtime: *Runtime) Error!void {
    if (!runtime.session.options.synthesis) {
        return;
    }

    const role: uinput.Role = if (runtime.session.options.mode == .grab) .relay else .inject;

    runtime.session.keyboard_out = uinput.create(.keyboard, role) catch {
        return Error.SynthesisUnavailable;
    };

    runtime.session.mouse_out = uinput.create(.mouse, role) catch {
        return Error.SynthesisUnavailable;
    };

    assert(runtime.session.synthesises());
}

fn open_devices(runtime: *Runtime, settle: bool) Error!void {
    assert(runtime.session.inputs.count == 0);
    assert(runtime.session.epoll >= 0);

    device.scan(&runtime.session.inputs) catch {
        runtime.session.inputs.close_all();

        return Error.DevicesMissing;
    };

    if (runtime.session.inputs.count == 0) {
        return Error.DevicesMissing;
    }

    if (runtime.session.options.mode == .grab) {
        runtime.select_sources(settle);
    }

    errdefer runtime.unwind_devices();

    var index: u8 = 0;

    while (index < runtime.session.inputs.count) : (index += 1) {
        const fd = runtime.session.inputs.devices[index].fd;
        const added = runtime.peers.state.add_source(fd);

        assert(device.origin_of(fd) != .own);
        assert(added);

        try runtime.watch(fd);
    }

    assert(index == runtime.session.inputs.count);
    assert(runtime.session.inputs.count <= State.source_count_max);
}

fn unwind_devices(runtime: *Runtime) void {
    runtime.unwatch_devices();

    _ = device.ungrab_all(&runtime.session.inputs);

    runtime.peers.state.clear_sources();
    runtime.session.inputs.close_all();

    assert(runtime.session.inputs.count == 0);
}

fn claim_own(runtime: *Runtime) void {
    const held = runtime.chain_lock_hold(true);
    defer runtime.chain_lock_drop(held);

    device.claim_open(&runtime.session.claim);

    if (runtime.session.options.mode == .grab) {
        device.claim_hold(&runtime.session.claim, .keyboard);
        device.claim_hold(&runtime.session.claim, .mouse);
    }

    assert(runtime.session.claim.is_valid());
}

fn scan_new(runtime: *Runtime) void {
    var index: u8 = 0;

    while (index < device.index_max) : (index += 1) {
        if (runtime.session.inputs.count == device.count_max) {
            return;
        }

        var buffer: [device.path_bytes_max]u8 = @splat(0);
        const path = device.build_path(&buffer, index) orelse continue;

        if (runtime.session.inputs.find_path(std.mem.span(path)) != null) {
            continue;
        }

        const opened = device.open_at(&runtime.session.inputs, index) orelse continue;

        runtime.session.inputs.devices[runtime.session.inputs.count] = opened;
        runtime.session.inputs.count += 1;

        runtime.watch(opened.fd) catch {
            evdev.close(opened.fd);
            runtime.session.inputs.count -= 1;
        };
    }

    assert(runtime.session.inputs.is_valid());
}

fn rebuild_sources(runtime: *Runtime) void {
    runtime.peers.state.clear_sources();

    var index: u8 = 0;

    while (index < runtime.session.inputs.count) : (index += 1) {
        const added = runtime.peers.state.add_source(runtime.session.inputs.devices[index].fd);

        assert(added);
    }

    assert(index == runtime.session.inputs.count);
}

fn ensure_kind(runtime: *Runtime, kind: device.Kind) void {
    assert(runtime.session.options.mode == .grab);
    assert(kind != .other);

    const grabbed = runtime.session.inputs.count_grabbed(kind);

    if (grabbed == 0) {
        runtime.reselect_kind(kind);

        return;
    }

    const direct = runtime.session.inputs.count_grabbed_origin(kind, .direct);

    if (direct > 0) {
        runtime.extend_direct(kind);
    }

    _ = device.close_where(&runtime.session.inputs, kind, .not_grabbed);

    assert(runtime.session.inputs.count_grabbed(kind) > 0);
}

fn extend_direct(runtime: *Runtime, kind: device.Kind) void {
    assert(kind != .other);

    const total = runtime.session.inputs.count_of_origin(kind, .direct);
    const grabbed_before = runtime.session.inputs.count_grabbed_origin(kind, .direct);

    assert(grabbed_before > 0);
    assert(grabbed_before <= total);

    if (grabbed_before == total) {
        return;
    }

    const added = device.grab_all(&runtime.session.inputs, kind, .direct);

    if (grabbed_before + added < total) {
        runtime.schedule_reselect();
    }
}

fn reselect_kind(runtime: *Runtime, kind: device.Kind) void {
    assert(runtime.session.options.mode == .grab);
    assert(kind != .other);

    const held = runtime.chain_lock_hold(false);

    if (!held) {
        runtime.schedule_reselect();

        return;
    }

    defer runtime.chain_lock_drop(held);

    runtime.grab_deferred = false;

    const selection = runtime.select_kind(kind);

    assert(selection.is_valid());

    log.info("reselect {s}: {s}{s}", .{
        @tagName(kind),
        @tagName(selection),
        if (runtime.grab_deferred) " (deferred: keys held)" else "",
    });

    if (runtime.grab_deferred) {
        runtime.schedule_reselect();
    } else {
        if (selection == .contended) runtime.schedule_reselect();
    }
}

fn schedule_reselect(runtime: *Runtime) void {
    runtime.session.reselect_ms = time.now_ms() + reselect_delay_ms + retry_jitter_ms();

    assert(runtime.session.reselect_ms > 0);
}

fn retry_jitter_ms() i64 {
    const slot = uinput.pid_self() % jitter_slot_count;

    assert(slot < jitter_slot_count);

    return @as(i64, slot) * jitter_slot_ms;
}

fn select_sources(runtime: *Runtime, settle: bool) void {
    assert(runtime.session.options.mode == .grab);

    if (settle) {
        if (!runtime.wait_for_keys_released()) {
            runtime.schedule_reselect();

            return;
        }
    }

    const held = runtime.chain_lock_hold(settle);

    if (!held) {
        runtime.schedule_reselect();

        return;
    }

    defer runtime.chain_lock_drop(held);

    runtime.grab_deferred = false;

    const keyboard = runtime.select_kind(.keyboard);
    const mouse = runtime.select_kind(.mouse);

    assert(keyboard.is_valid());
    assert(mouse.is_valid());

    runtime.session.reselect_ms = if (runtime.grab_deferred)
        time.now_ms() + reselect_delay_ms
    else
        reselect_deadline(keyboard, mouse);

    assert(runtime.session.inputs.is_valid());
    assert(runtime.session.claim.is_valid());
}

fn reselect_deadline(keyboard: Selection, mouse: Selection) i64 {
    assert(keyboard.is_valid());
    assert(mouse.is_valid());

    if (keyboard == .secured) return 0;
    if (mouse == .secured) return 0;

    if (keyboard != .contended) {
        if (mouse != .contended) return 0;
    }

    const deadline = time.now_ms() + reselect_delay_ms;

    assert(deadline > 0);

    return deadline;
}

fn select_kind(runtime: *Runtime, kind: device.Kind) Selection {
    assert(kind.is_valid());
    assert(kind != .other);
    assert(runtime.chain_lock_depth > 0);

    const present = runtime.session.inputs.count_of(kind) > 0;

    if (runtime.any_key_down()) {
        runtime.grab_deferred = true;
    }

    if (!runtime.elder_present(kind)) {
        const total = runtime.session.inputs.count_of_origin(kind, .direct);
        const direct = device.grab_all(&runtime.session.inputs, kind, .direct);

        assert(direct <= total);

        if (direct > 0) {
            if (direct == total) return runtime.select_secured(kind);

            _ = device.ungrab_where(&runtime.session.inputs, kind, .direct);
        }
    }

    if (runtime.chain_kind(kind)) {
        return runtime.select_secured(kind);
    }

    _ = device.close_where(&runtime.session.inputs, kind, .not_grabbed);

    device.claim_hold(&runtime.session.claim, kind);

    if (present) {
        return .contended;
    }

    return .absent;
}

fn elder_present(runtime: *const Runtime, kind: device.Kind) bool {
    assert(kind != .other);

    const out = runtime.out_of(kind);

    if (!out.is_open()) {
        return false;
    }

    const own = device.Order{ .stamp_ms = out.stamp_ms, .pid = uinput.pid_self() };
    return device.chain_elder_present(&runtime.session.inputs, kind, own);
}

fn select_secured(runtime: *Runtime, kind: device.Kind) Selection {
    assert(kind != .other);

    _ = device.close_where(&runtime.session.inputs, kind, .not_grabbed);

    device.claim_release(&runtime.session.claim, kind);

    assert(runtime.session.claim.is_valid());

    return .secured;
}

fn chain_kind(runtime: *Runtime, kind: device.Kind) bool {
    assert(kind.is_valid());
    assert(runtime.session.options.mode == .grab);

    const out = runtime.out_of(kind);

    if (!out.is_open()) {
        return false;
    }

    const own = device.Order{ .stamp_ms = out.stamp_ms, .pid = uinput.pid_self() };
    return device.grab_chain(&runtime.session.inputs, kind, own) != null;
}

fn out_of(runtime: *const Runtime, kind: device.Kind) *const uinput.Device {
    return switch (kind) {
        .keyboard => &runtime.session.keyboard_out,
        .mouse => &runtime.session.mouse_out,
        .other => unreachable,
    };
}

fn chain_lock_hold(runtime: *Runtime, blocking: bool) bool {
    assert(runtime.chain_lock_depth < chain_lock_depth_max);

    if (runtime.chain_lock_depth > 0) {
        assert(runtime.chain_lock_fd >= 0);

        runtime.chain_lock_depth += 1;

        return true;
    }

    assert(runtime.chain_lock_fd < 0);

    const attempt_max: u8 = if (blocking) chain_lock_retry_max else 1;
    const fd = chain_lock_acquire(attempt_max) orelse return false;

    runtime.chain_lock_fd = fd;
    runtime.chain_lock_depth = 1;

    assert(runtime.chain_lock_fd >= 0);
    assert(runtime.chain_lock_depth == 1);

    return true;
}

fn chain_lock_drop(runtime: *Runtime, held: bool) void {
    if (!held) {
        return;
    }

    assert(runtime.chain_lock_depth > 0);
    assert(runtime.chain_lock_fd >= 0);

    runtime.chain_lock_depth -= 1;

    if (runtime.chain_lock_depth > 0) {
        return;
    }

    chain_lock_release(runtime.chain_lock_fd);

    runtime.chain_lock_fd = -1;

    assert(runtime.chain_lock_fd < 0);
    assert(runtime.chain_lock_depth == 0);
}

fn chain_lock_acquire(attempt_max: u8) ?posix.fd_t {
    assert(attempt_max > 0);

    const fd = chain_lock_open() orelse return null;

    var attempt: u8 = 0;

    while (attempt < attempt_max) : (attempt += 1) {
        const status = linux.flock(fd, posix.LOCK.EX | posix.LOCK.NB);

        if (linux.errno(status) == .SUCCESS) {
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
    assert(path[0] != 0);

    const flags = posix.O{ .ACCMODE = .RDWR, .CREAT = true, .CLOEXEC = true };
    return posix.openatZ(posix.AT.FDCWD, path, flags, 0o600) catch null;
}

fn chain_lock_path(
    buffer: *[chain_lock_path_bytes_max]u8,
    comptime format: []const u8,
) ?[*:0]const u8 {
    const room = buffer[0 .. chain_lock_path_bytes_max - 1];
    const written = std.mem.print(room, format, .{linux.getuid()}) catch return null;

    assert(written.len < chain_lock_path_bytes_max);

    buffer[written.len] = 0;

    return @ptrCast(buffer);
}

fn register_hotplug(runtime: *Runtime) void {
    assert(runtime.session.epoll >= 0);

    if (!runtime.peers.hotplug.open()) {
        return;
    }

    runtime.watch(runtime.peers.hotplug.handle()) catch runtime.peers.hotplug.close();
}

fn wait_for_keys_released(runtime: *Runtime) bool {
    var waited: u32 = 0;

    while (waited < grab_settle_wait_ms_max) : (waited += grab_settle_poll_ms) {
        assert(waited < grab_settle_wait_ms_max);

        if (!runtime.any_key_down()) {
            return true;
        }

        time.sleep_ms(grab_settle_poll_ms);
    }

    return !runtime.any_key_down();
}

fn any_key_down(runtime: *const Runtime) bool {
    var index: u8 = 0;

    while (index < runtime.session.inputs.count) : (index += 1) {
        if (device_key_down(runtime.session.inputs.devices[index].fd)) {
            return true;
        }
    }

    assert(index == runtime.session.inputs.count);

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

fn unwatch_devices(runtime: *Runtime) void {
    var index: u8 = 0;

    while (index < runtime.session.inputs.count) : (index += 1) {
        runtime.unwatch(runtime.session.inputs.devices[index].fd);
    }

    assert(index == runtime.session.inputs.count);
}

pub fn watch(runtime: *Runtime, fd: posix.fd_t) Error!void {
    assert(fd >= 0);

    if (runtime.session.epoll < 0) {
        return;
    }

    var wake = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .fd = fd } };
    const status = linux.epoll_ctl(runtime.session.epoll, linux.EPOLL.CTL_ADD, fd, &wake);

    if (linux.errno(status) != .SUCCESS) {
        return Error.EpollFailed;
    }
}

pub fn unwatch(runtime: *Runtime, fd: posix.fd_t) void {
    if (runtime.session.epoll < 0) return;
    if (fd < 0) return;

    _ = linux.epoll_ctl(runtime.session.epoll, linux.EPOLL.CTL_DEL, fd, null);
}

fn watch_added(context: *anyopaque, fd: posix.fd_t) Timer.WatchError!void {
    const runtime: *Runtime = @ptrCast(@alignCast(context));

    assert(fd >= 0);
    assert(runtime.session.epoll >= 0);

    runtime.watch(fd) catch return Timer.WatchError.WatchFailed;
}

fn watch_removed(context: *anyopaque, fd: posix.fd_t) void {
    const runtime: *Runtime = @ptrCast(@alignCast(context));

    assert(fd >= 0);

    runtime.unwatch(fd);
}

const testing = std.testing;

test "a fresh session is closed and owns nothing" {
    const fresh = Session{};

    try testing.expect(fresh.is_valid());
    try testing.expect(!fresh.opened);
    try testing.expect(!fresh.grabs());
    try testing.expect(!fresh.synthesises());
    try testing.expect(fresh.epoll < 0);
}

test "a closed runtime reports observe mode" {
    const runtime = Runtime{ .peers = undefined };

    try testing.expect(!runtime.is_open());
    try testing.expectEqual(Mode.observe, runtime.mode());
}

test "the runtime shares the interface vocabulary" {
    try testing.expectEqual(interface.Mode, Mode);
    try testing.expectEqual(interface.Options, Options);
}

test "the selection covers exactly the outcomes a kind can reach" {
    try testing.expect(Selection.secured.is_valid());
    try testing.expect(Selection.absent.is_valid());
    try testing.expect(Selection.contended.is_valid());
    try testing.expectEqual(@as(u8, 3), @typeInfo(Selection).@"enum".field_names.len);
}

test "a reselect is scheduled only when contention left the session sourceless" {
    try testing.expectEqual(@as(i64, 0), reselect_deadline(.secured, .contended));
    try testing.expectEqual(@as(i64, 0), reselect_deadline(.contended, .secured));
    try testing.expectEqual(@as(i64, 0), reselect_deadline(.secured, .absent));
    try testing.expectEqual(@as(i64, 0), reselect_deadline(.absent, .absent));

    try testing.expect(reselect_deadline(.contended, .contended) > 0);
    try testing.expect(reselect_deadline(.contended, .absent) > 0);
    try testing.expect(reselect_deadline(.absent, .contended) > 0);
}

test "a session with no pending reselect ignores the due check" {
    var runtime = Runtime{ .peers = undefined };

    runtime.session.reselect_ms = 0;

    runtime.reselect_if_due();

    try testing.expectEqual(@as(i64, 0), runtime.session.reselect_ms);
}

test "the chain lock nests within one process and releases once at the end" {
    var runtime = Runtime{ .peers = undefined };

    try testing.expectEqual(@as(u8, 0), runtime.chain_lock_depth);
    try testing.expect(runtime.chain_lock_fd < 0);

    const outer = runtime.chain_lock_hold(true);

    if (!outer) {
        return error.SkipZigTest;
    }

    try testing.expectEqual(@as(u8, 1), runtime.chain_lock_depth);
    try testing.expect(runtime.chain_lock_fd >= 0);

    const inner = runtime.chain_lock_hold(false);

    try testing.expect(inner);
    try testing.expectEqual(@as(u8, 2), runtime.chain_lock_depth);

    runtime.chain_lock_drop(inner);

    try testing.expectEqual(@as(u8, 1), runtime.chain_lock_depth);
    try testing.expect(runtime.chain_lock_fd >= 0);

    runtime.chain_lock_drop(outer);

    try testing.expectEqual(@as(u8, 0), runtime.chain_lock_depth);
    try testing.expect(runtime.chain_lock_fd < 0);
}

test "dropping a lock that was never held leaves the depth alone" {
    var runtime = Runtime{ .peers = undefined };

    const depth = runtime.chain_lock_depth;

    runtime.chain_lock_drop(false);

    try testing.expectEqual(depth, runtime.chain_lock_depth);
    try testing.expect(runtime.chain_lock_fd < 0);
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
    try testing.expect(std.mem.find(u8, path[0..length], "nimble-chain") != null);
}

test "the display path joins the runtime directory and the display name" {
    var buffer: [display_bytes_max]u8 = undefined;

    try testing.expect(!display_configured(&.{}));

    const joined = try display_path(&.{
        .wayland_display = "wayland-1",
        .xdg_runtime_dir = "/run/user/1000",
    }, &buffer);

    try testing.expectEqualStrings("/run/user/1000/wayland-1", joined);

    const defaulted = try display_path(&.{ .xdg_runtime_dir = "/run/user/1000" }, &buffer);

    try testing.expectEqualStrings("/run/user/1000/wayland-0", defaulted);

    const absolute = try display_path(&.{ .wayland_display = "/tmp/wayland-9" }, &buffer);

    try testing.expectEqualStrings("/tmp/wayland-9", absolute);
}

test "a display path that cannot name a socket is a request error" {
    var buffer: [display_bytes_max]u8 = undefined;

    const long: [display_bytes_max]u8 = @splat('d');
    const relative = display_path(&.{ .wayland_display = "wayland-0" }, &buffer);
    const empty = display_path(&.{ .wayland_display = "" }, &buffer);
    const oversized = display_path(&.{ .wayland_display = "w", .xdg_runtime_dir = &long }, &buffer);

    try testing.expectError(Error.DisplayInvalid, relative);
    try testing.expectError(Error.DisplayInvalid, empty);
    try testing.expectError(Error.DisplayInvalid, oversized);
}
