const std = @import("std");

const platform = @import("platform.zig");

pub const Condition = platform.sync.Condition;
pub const Mutex = platform.sync.Mutex;

const testing = std.testing;

test "a broadcast wakes a waiter once its predicate holds" {
    const Shared = struct {
        condition: Condition = .{},
        mutex: Mutex = .{},
        ready: bool = false,
        woken: bool = false,

        fn ready_wait(shared: *@This()) void {
            shared.mutex.lock();
            defer shared.mutex.unlock();

            while (!shared.ready) {
                shared.condition.wait(&shared.mutex);
            }

            shared.woken = true;
        }
    };

    var shared = Shared{};
    const waiter = try std.Thread.spawn(.{}, Shared.ready_wait, .{&shared});

    {
        shared.mutex.lock();
        defer shared.mutex.unlock();

        shared.ready = true;

        shared.condition.broadcast();
    }

    waiter.join();

    try testing.expect(shared.woken);
}

test "two threads alternate turns through a condition without losing a wakeup" {
    const round_count: u32 = 10_000;

    const Shared = struct {
        condition: Condition = .{},
        mutex: Mutex = .{},
        turn: u32 = 0,

        fn turns_take(shared: *@This(), parity: u32) void {
            var round: u32 = 0;

            while (round < round_count) : (round += 1) {
                shared.mutex.lock();
                defer shared.mutex.unlock();

                while (shared.turn % 2 != parity) {
                    shared.condition.wait(&shared.mutex);
                }

                shared.turn += 1;

                shared.condition.broadcast();
            }
        }
    };

    var shared = Shared{};
    const even = try std.Thread.spawn(.{}, Shared.turns_take, .{ &shared, 0 });
    const odd = try std.Thread.spawn(.{}, Shared.turns_take, .{ &shared, 1 });

    even.join();
    odd.join();

    try testing.expectEqual(2 * round_count, shared.turn);
}

test Mutex {
    var mutex: Mutex = .{};

    mutex.lock();

    try testing.expect(!mutex.try_lock());

    mutex.unlock();

    try testing.expect(mutex.try_lock());

    mutex.unlock();
}

test "the host mutex locks, blocks a second acquire, and releases" {
    var mutex = Mutex{};

    try testing.expect(mutex.try_lock());
    try testing.expect(!mutex.try_lock());

    mutex.unlock();

    mutex.lock();
    mutex.unlock();

    try testing.expect(mutex.try_lock());

    mutex.unlock();
}

test "a mutex guards a shared counter across threads" {
    const Shared = struct {
        mutex: Mutex = .{},
        counter: u64 = 0,

        fn bump(self: *@This()) void {
            var index: u32 = 0;

            while (index < 5_000) : (index += 1) {
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

    try testing.expectEqual(@as(u64, 10_000), shared.counter);
}
