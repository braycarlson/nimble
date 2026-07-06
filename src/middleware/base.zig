const std = @import("std");

const key_event = @import("../event/key.zig");
const response = @import("../response.zig");

const Mutex = @import("../mutex.zig").Mutex;

const Key = key_event.Key;
const Response = response.Response;

pub const Next = struct {
    context: *anyopaque,
    call: *const fn (context: *anyopaque, key: *const Key) Response,

    pub fn invoke(self: *const Next, key: *const Key) Response {
        std.debug.assert(key.is_valid());

        const result = self.call(self.context, key);

        std.debug.assert(result.is_valid());

        return result;
    }
};

pub const Middleware = struct {
    pointer: *anyopaque,
    vtable: *const VTable,

    const VTable = struct {
        process: *const fn (pointer: *anyopaque, key: *const Key, next: *const Next) Response,
    };

    pub fn process(self: *const Middleware, key: *const Key, next: *const Next) Response {
        std.debug.assert(key.is_valid());

        const result = self.vtable.process(self.pointer, key, next);

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn from(comptime T: type, pointer: *T) Middleware {
        const impl = struct {
            fn process(p: *anyopaque, k: *const Key, n: *const Next) Response {
                std.debug.assert(k.is_valid());

                const context: *T = @ptrCast(@alignCast(p));
                const result = context.process(k, n);

                std.debug.assert(result.is_valid());

                return result;
            }

            const vtable = VTable{ .process = @This().process };
        };

        const result = Middleware{
            .pointer = pointer,
            .vtable = &impl.vtable,
        };

        return result;
    }
};

pub fn Pipeline(comptime capacity: u8) type {
    return struct {
        const Self = @This();

        items: [capacity]?Middleware = [_]?Middleware{null} ** capacity,
        count: u8 = 0,
        mutex: Mutex = .{},

        const Snapshot = struct {
            items: [capacity]Middleware,
            count: u8,
            final: *const fn (key: *const Key) Response,
        };

        pub fn init() Self {
            const result = Self{};

            std.debug.assert(result.count == 0);
            std.debug.assert(capacity > 0);

            return result;
        }

        pub fn add(self: *Self, comptime T: type, pointer: *T) !u8 {
            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);

            if (self.count >= capacity) {
                return error.PipelineFull;
            }

            const slot = self.find_empty_slot() orelse return error.PipelineFull;

            std.debug.assert(slot < capacity);

            self.items[slot] = Middleware.from(T, pointer);
            self.count += 1;

            std.debug.assert(self.count <= capacity);
            std.debug.assert(self.items[slot] != null);

            return slot;
        }

        pub fn remove(self: *Self, slot: u8) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);

            if (slot >= capacity) {
                return error.InvalidSlot;
            }

            std.debug.assert(slot < capacity);

            if (self.items[slot] == null) {
                return error.NotFound;
            }

            self.items[slot] = null;
            self.count -= 1;

            std.debug.assert(self.count <= capacity);
            std.debug.assert(self.items[slot] == null);
        }

        fn find_empty_slot(self: *const Self) ?u8 {
            std.debug.assert(self.count <= capacity);

            var i: u8 = 0;

            while (i < capacity) : (i += 1) {
                if (self.items[i] == null) {
                    return i;
                }
            }

            std.debug.assert(i == capacity);

            return null;
        }

        pub fn process(self: *Self, key: *const Key, final: *const fn (key: *const Key) Response) Response {
            std.debug.assert(key.is_valid());

            var snapshot = Snapshot{
                .items = undefined,
                .count = 0,
                .final = final,
            };

            self.snapshot_items(&snapshot);

            std.debug.assert(snapshot.count <= capacity);

            const result = stage_process(0, &snapshot, key);

            std.debug.assert(result.is_valid());

            return result;
        }

        fn snapshot_items(self: *Self, snapshot: *Snapshot) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);
            std.debug.assert(snapshot.count == 0);

            var i: u8 = 0;

            while (i < capacity) : (i += 1) {
                if (self.items[i]) |middleware| {
                    std.debug.assert(snapshot.count < capacity);

                    snapshot.items[snapshot.count] = middleware;
                    snapshot.count += 1;
                }
            }

            std.debug.assert(i == capacity);
            std.debug.assert(snapshot.count == self.count);
        }

        fn stage_process(comptime index: u8, snapshot: *Snapshot, key: *const Key) Response {
            std.debug.assert(key.is_valid());
            std.debug.assert(snapshot.count <= capacity);

            if (index == capacity) {
                return snapshot.final(key);
            } else {
                if (index >= snapshot.count) {
                    return snapshot.final(key);
                }

                const next = Next{
                    .context = snapshot,
                    .call = stage_call(index + 1),
                };

                const result = snapshot.items[index].process(key, &next);

                std.debug.assert(result.is_valid());

                return result;
            }
        }

        fn stage_call(comptime index: u8) *const fn (context: *anyopaque, key: *const Key) Response {
            const impl = struct {
                fn call(context: *anyopaque, key: *const Key) Response {
                    std.debug.assert(key.is_valid());

                    const snapshot: *Snapshot = @ptrCast(@alignCast(context));
                    const result = stage_process(index, snapshot, key);

                    std.debug.assert(result.is_valid());

                    return result;
                }
            };

            return impl.call;
        }

        pub fn clear(self: *Self) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.assert(self.count <= capacity);

            var i: u8 = 0;

            while (i < capacity) : (i += 1) {
                self.items[i] = null;
            }

            self.count = 0;

            std.debug.assert(self.count == 0);
            std.debug.assert(i == capacity);
        }
    };
}
