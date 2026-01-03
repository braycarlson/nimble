const std = @import("std");

const key_event = @import("../event/key.zig");
const response_mod = @import("../response.zig");

const Key = key_event.Key;
const Response = response_mod.Response;

pub const Next = struct {
    context: *anyopaque,
    call: *const fn (context: *anyopaque, key: *const Key) Response,

    pub fn invoke(self: *const Next, key: *const Key) Response {
        std.debug.assert(@intFromPtr(self.context) != 0);
        std.debug.assert(@intFromPtr(self.call) != 0);
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
        std.debug.assert(@intFromPtr(self.pointer) != 0);
        std.debug.assert(@intFromPtr(self.vtable) != 0);
        std.debug.assert(key.is_valid());

        const result = self.vtable.process(self.pointer, key, next);

        std.debug.assert(result.is_valid());

        return result;
    }

    pub fn from(comptime T: type, pointer: *T) Middleware {
        std.debug.assert(@intFromPtr(pointer) != 0);

        const impl = struct {
            fn process(p: *anyopaque, k: *const Key, n: *const Next) Response {
                std.debug.assert(@intFromPtr(p) != 0);
                std.debug.assert(k.is_valid());

                const context: *T = @ptrCast(@alignCast(p));
                const result = context.process(k, n);

                std.debug.assert(result.is_valid());

                return result;
            }
        };

        const result = Middleware{
            .pointer = pointer,
            .vtable = &.{ .process = impl.process },
        };

        std.debug.assert(@intFromPtr(result.pointer) != 0);

        return result;
    }
};

pub fn Pipeline(comptime capacity: u8) type {
    return struct {
        const Self = @This();

        items: [capacity]?Middleware = [_]?Middleware{null} ** capacity,
        count: u8 = 0,

        const ChainContext = struct {
            pipeline: *Self,
            index: u8,
            final: *const fn (key: *const Key) Response,
        };

        pub fn init() Self {
            const result = Self{};

            std.debug.assert(result.count == 0);
            std.debug.assert(capacity > 0);

            return result;
        }

        pub fn add(self: *Self, comptime T: type, pointer: *T) !u8 {
            std.debug.assert(self.count <= capacity);
            std.debug.assert(@intFromPtr(pointer) != 0);

            if (self.count >= capacity) {
                return error.PipelineFull;
            }

            const slot = self.count;

            std.debug.assert(slot < capacity);

            self.items[slot] = Middleware.from(T, pointer);
            self.count += 1;

            std.debug.assert(self.count <= capacity);
            std.debug.assert(self.items[slot] != null);

            return slot;
        }

        pub fn remove(self: *Self, slot: u8) !void {
            std.debug.assert(self.count <= capacity);

            if (slot >= self.count) {
                return error.InvalidSlot;
            }

            std.debug.assert(slot < self.count);

            var index: u8 = slot;
            var i: u8 = 0;

            while (i < capacity) : (i += 1) {
                std.debug.assert(i < capacity);

                if (index >= self.count - 1) {
                    break;
                }

                self.items[index] = self.items[index + 1];
                index += 1;
            }

            self.items[self.count - 1] = null;
            self.count -= 1;

            std.debug.assert(self.count <= capacity);
        }

        pub fn process(self: *Self, key: *const Key, final: *const fn (key: *const Key) Response) Response {
            std.debug.assert(self.count <= capacity);
            std.debug.assert(key.is_valid());

            return self.process_at(0, key, final);
        }

        fn process_at(self: *Self, index: u8, key: *const Key, final: *const fn (key: *const Key) Response) Response {
            std.debug.assert(self.count <= capacity);
            std.debug.assert(key.is_valid());

            if (index >= self.count) {
                return final(key);
            }

            std.debug.assert(index < self.count);

            if (self.items[index]) |middleware| {
                var chain = ChainContext{
                    .pipeline = self,
                    .index = index + 1,
                    .final = final,
                };

                const next = Next{
                    .context = &chain,
                    .call = chain_call,
                };

                const result = middleware.process(key, &next);

                std.debug.assert(result.is_valid());

                return result;
            }

            return self.process_at(index + 1, key, final);
        }

        fn chain_call(context: *anyopaque, key: *const Key) Response {
            std.debug.assert(@intFromPtr(context) != 0);
            std.debug.assert(key.is_valid());

            const chain: *ChainContext = @ptrCast(@alignCast(context));

            const result = chain.pipeline.process_at(chain.index, key, chain.final);

            std.debug.assert(result.is_valid());

            return result;
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.count <= capacity);

            var i: u8 = 0;

            while (i < capacity) : (i += 1) {
                std.debug.assert(i < capacity);

                self.items[i] = null;
            }

            self.count = 0;

            std.debug.assert(self.count == 0);
            std.debug.assert(i == capacity);
        }
    };
}
