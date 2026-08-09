const std = @import("std");

const win32 = @import("win32.zig");

pub const Mutex = struct {
    srwlock: win32.SRWLOCK = win32.srwlock_init,

    pub fn try_lock(mutex: *Mutex) bool {
        return win32.TryAcquireSRWLockExclusive(&mutex.srwlock) != 0;
    }

    pub fn lock(mutex: *Mutex) void {
        win32.AcquireSRWLockExclusive(&mutex.srwlock);
    }

    pub fn unlock(mutex: *Mutex) void {
        win32.ReleaseSRWLockExclusive(&mutex.srwlock);
    }
};

const testing = std.testing;

test "an uncontended mutex locks and unlocks without blocking" {
    var mutex = Mutex{};

    try testing.expect(mutex.try_lock());

    mutex.unlock();

    mutex.lock();
    mutex.unlock();
}

test "a fresh mutex starts unlocked" {
    const mutex = Mutex{};

    try testing.expect(mutex.srwlock.ptr == null);
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
