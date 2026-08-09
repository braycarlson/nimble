const std = @import("std");

const platform = @import("platform.zig");

pub const Mutex = platform.sync.Mutex;

const testing = std.testing;

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
