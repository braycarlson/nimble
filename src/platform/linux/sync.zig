const std = @import("std");

const assert = std.debug.assert;

const linux = std.os.linux;

const unlocked: u32 = 0;
const locked: u32 = 1;
const contended: u32 = 2;

comptime {
    assert(unlocked < locked);
    assert(locked < contended);
}

pub const Mutex = struct {
    state: std.atomic.Value(u32) = std.atomic.Value(u32).init(unlocked),

    pub fn try_lock(mutex: *Mutex) bool {
        return mutex.state.cmpxchgStrong(unlocked, locked, .acquire, .monotonic) == null;
    }

    pub fn lock(mutex: *Mutex) void {
        if (mutex.state.cmpxchgStrong(unlocked, locked, .acquire, .monotonic) == null) {
            return;
        }

        while (mutex.state.swap(contended, .acquire) != unlocked) {
            wait(&mutex.state.raw);
        }
    }

    pub fn unlock(mutex: *Mutex) void {
        const previous = mutex.state.swap(unlocked, .release);

        assert(previous != unlocked);

        if (previous == contended) {
            wake(&mutex.state.raw);
        }
    }
};

fn wait(address: *const u32) void {
    _ = linux.futex_3arg(address, .{ .cmd = .WAIT, .private = true }, contended);
}

fn wake(address: *const u32) void {
    _ = linux.futex_3arg(address, .{ .cmd = .WAKE, .private = true }, 1);
}

const testing = std.testing;

test "an uncontended mutex locks and unlocks without parking" {
    var mutex = Mutex{};

    try testing.expect(mutex.try_lock());
    try testing.expect(!mutex.try_lock());

    mutex.unlock();

    try testing.expect(mutex.try_lock());

    mutex.unlock();
}

test "lock and unlock round trip" {
    var mutex = Mutex{};

    mutex.lock();
    mutex.unlock();

    mutex.lock();
    mutex.unlock();

    try testing.expect(mutex.try_lock());

    mutex.unlock();
}

test "a fresh mutex starts unlocked" {
    var mutex = Mutex{};

    try testing.expectEqual(unlocked, mutex.state.load(.monotonic));
}

test "contending threads serialise on the mutex" {
    const Shared = struct {
        mutex: Mutex = .{},
        counter: u64 = 0,

        fn bump(self: *@This()) void {
            var index: u32 = 0;

            while (index < 10_000) : (index += 1) {
                self.mutex.lock();
                defer self.mutex.unlock();

                self.counter += 1;
            }
        }
    };

    var shared = Shared{};

    const first = try std.Thread.spawn(.{}, Shared.bump, .{&shared});
    const second = try std.Thread.spawn(.{}, Shared.bump, .{&shared});

    first.join();
    second.join();

    try testing.expectEqual(@as(u64, 20_000), shared.counter);
}
