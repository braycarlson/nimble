const std = @import("std");

pub const key_count: u32 = 256;
pub const iteration_max: u32 = 0xFFFFFFFF;

pub fn EventStore(comptime Event: type, comptime max_events: u32) type {
    return struct {
        const Self = @This();

        events: [max_events]Event = undefined,
        count: u32 = 0,
        initialized: bool = true,

        pub fn init() Self {
            const result = Self{};

            std.debug.assert(result.count == 0);
            std.debug.assert(result.initialized);

            return result;
        }

        pub fn is_valid(self: *const Self) bool {
            std.debug.assert(@intFromPtr(self) != 0);

            const valid_count = self.count <= max_events;
            const valid_init = self.initialized;
            const result = valid_count and valid_init;

            return result;
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.count = 0;

            std.debug.assert(self.count == 0);
            std.debug.assert(self.is_valid());
        }

        pub fn add(self: *Self, event: Event) void {
            std.debug.assert(self.is_valid());

            if (self.count >= max_events) {
                return;
            }

            std.debug.assert(self.count < max_events);

            self.events[self.count] = event;
            self.count += 1;

            std.debug.assert(self.count <= max_events);
            std.debug.assert(self.is_valid());
        }

        pub fn get(self: *const Self, index: u32) ?Event {
            std.debug.assert(self.is_valid());

            if (index >= self.count) {
                return null;
            }

            std.debug.assert(index < self.count);
            std.debug.assert(index < max_events);

            const result = self.events[index];

            return result;
        }

        pub fn slice(self: *const Self) []const Event {
            std.debug.assert(self.is_valid());

            const result = self.events[0..self.count];

            std.debug.assert(result.len == self.count);
            std.debug.assert(result.len <= max_events);

            return result;
        }

        pub fn get_at_tick(self: *const Self, tick: u32) ?Event {
            std.debug.assert(self.is_valid());

            var i: u32 = 0;

            while (i < self.count and i < max_events) : (i += 1) {
                std.debug.assert(i < self.count);
                std.debug.assert(i < max_events);

                if (self.events[i].tick == tick) {
                    return self.events[i];
                }
            }

            std.debug.assert(i == self.count or i == max_events);

            return null;
        }

        pub fn count_at_tick(self: *const Self, tick: u32) u32 {
            std.debug.assert(self.is_valid());

            var result: u32 = 0;
            var i: u32 = 0;

            while (i < self.count and i < max_events) : (i += 1) {
                std.debug.assert(i < self.count);
                std.debug.assert(i < max_events);

                if (self.events[i].tick == tick) {
                    result += 1;
                }
            }

            std.debug.assert(i == self.count or i == max_events);
            std.debug.assert(result <= self.count);

            return result;
        }

        pub fn get_at_tick_by_index(self: *const Self, tick: u32, index: u32) ?Event {
            std.debug.assert(self.is_valid());

            var found: u32 = 0;
            var i: u32 = 0;

            while (i < self.count and i < max_events) : (i += 1) {
                std.debug.assert(i < self.count);
                std.debug.assert(i < max_events);

                if (self.events[i].tick == tick) {
                    if (found == index) {
                        return self.events[i];
                    }

                    found += 1;
                }
            }

            std.debug.assert(i == self.count or i == max_events);

            return null;
        }

        pub fn get_max_tick(self: *const Self) u32 {
            std.debug.assert(self.is_valid());

            var max: u32 = 0;
            var i: u32 = 0;

            while (i < self.count and i < max_events) : (i += 1) {
                std.debug.assert(i < self.count);
                std.debug.assert(i < max_events);

                if (self.events[i].tick > max) {
                    max = self.events[i].tick;
                }
            }

            std.debug.assert(i == self.count or i == max_events);

            return max;
        }

        pub fn count_in_range(self: *const Self, start: u32, end: u32) u32 {
            std.debug.assert(self.is_valid());
            std.debug.assert(end >= start);

            var result: u32 = 0;
            var i: u32 = 0;

            while (i < self.count and i < max_events) : (i += 1) {
                std.debug.assert(i < self.count);
                std.debug.assert(i < max_events);

                const tick = self.events[i].tick;

                if (tick >= start and tick <= end) {
                    result += 1;
                }
            }

            std.debug.assert(i == self.count or i == max_events);
            std.debug.assert(result <= self.count);

            return result;
        }

        pub fn get_next_tick(self: *const Self, current: u32) u32 {
            std.debug.assert(self.is_valid());

            var i: u32 = 0;

            while (i < self.count and i < max_events) : (i += 1) {
                std.debug.assert(i < self.count);
                std.debug.assert(i < max_events);

                if (self.events[i].tick > current) {
                    const result = self.events[i].tick;

                    std.debug.assert(result > current);

                    return result;
                }
            }

            std.debug.assert(i == self.count or i == max_events);

            return current;
        }

        pub fn get_prev_tick(self: *const Self, current: u32) u32 {
            std.debug.assert(self.is_valid());

            var prev: u32 = 0;
            var i: u32 = 0;

            while (i < self.count and i < max_events) : (i += 1) {
                std.debug.assert(i < self.count);
                std.debug.assert(i < max_events);

                const tick = self.events[i].tick;

                if (tick >= current) {
                    break;
                }

                prev = tick;
            }

            std.debug.assert(i <= max_events);
            std.debug.assert(prev <= current);

            return prev;
        }
    };
}

pub fn TickTracker(comptime max_tick_default: u32) type {
    return struct {
        const Self = @This();

        current: u32 = 0,
        max: u32 = max_tick_default,
        initialized: bool = true,

        pub fn init() Self {
            const result = Self{};

            std.debug.assert(result.current == 0);
            std.debug.assert(result.max == max_tick_default);
            std.debug.assert(result.initialized);

            return result;
        }

        pub fn is_valid(self: *const Self) bool {
            std.debug.assert(@intFromPtr(self) != 0);

            const valid_bounds = self.current <= self.max or self.max == 0;
            const valid_init = self.initialized;
            const result = valid_bounds and valid_init;

            return result;
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.current = 0;
            self.max = max_tick_default;

            std.debug.assert(self.current == 0);
            std.debug.assert(self.max == max_tick_default);
            std.debug.assert(self.is_valid());
        }

        pub fn set(self: *Self, tick: u32) void {
            std.debug.assert(self.is_valid());

            self.current = tick;

            std.debug.assert(self.current == tick);
        }

        pub fn update_max(self: *Self, tick: u32) void {
            std.debug.assert(self.is_valid());

            if (tick > self.max) {
                self.max = tick;
            }

            std.debug.assert(self.max >= tick);
        }

        pub fn step_forward(self: *Self) void {
            std.debug.assert(self.is_valid());

            const prev = self.current;

            if (self.current < self.max) {
                self.current += 1;
            }

            std.debug.assert(self.current <= self.max);
            std.debug.assert(self.current >= prev);
        }

        pub fn step_backward(self: *Self) void {
            std.debug.assert(self.is_valid());

            const prev = self.current;

            if (self.current > 0) {
                self.current -= 1;
            }

            std.debug.assert(self.current <= self.max);
            std.debug.assert(self.current <= prev);
        }

        pub fn get_progress(self: *const Self) f32 {
            std.debug.assert(self.is_valid());

            if (self.max == 0) {
                return 1.0;
            }

            std.debug.assert(self.max > 0);

            const current_f: f32 = @floatFromInt(self.current);
            const max_f: f32 = @floatFromInt(self.max);
            const result = current_f / max_f;

            std.debug.assert(result >= 0.0);
            std.debug.assert(result <= 1.0 or self.current > self.max);

            return result;
        }
    };
}

pub fn SeedStore() type {
    return struct {
        const Self = @This();

        value: u64 = 0,
        initialized: bool = true,

        pub fn init() Self {
            const result = Self{};

            std.debug.assert(result.value == 0);
            std.debug.assert(result.initialized);

            return result;
        }

        pub fn is_valid(self: *const Self) bool {
            std.debug.assert(@intFromPtr(self) != 0);

            const result = self.initialized;

            return result;
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.is_valid());

            self.value = 0;

            std.debug.assert(self.value == 0);
            std.debug.assert(self.is_valid());
        }

        pub fn set(self: *Self, lo: u32, hi: u32) void {
            std.debug.assert(self.is_valid());

            const hi_shifted: u64 = @as(u64, hi) << 32;
            const lo_extended: u64 = @as(u64, lo);

            self.value = hi_shifted | lo_extended;

            std.debug.assert(self.get_lo() == lo);
            std.debug.assert(self.get_hi() == hi);
        }

        pub fn get_lo(self: *const Self) u32 {
            std.debug.assert(self.is_valid());

            const result: u32 = @truncate(self.value);

            return result;
        }

        pub fn get_hi(self: *const Self) u32 {
            std.debug.assert(self.is_valid());

            const result: u32 = @truncate(self.value >> 32);

            return result;
        }
    };
}

pub fn KeyboardState() type {
    return struct {
        const Self = @This();

        keys_down: [key_count]bool = [_]bool{false} ** key_count,
        initialized: bool = true,

        pub fn init() Self {
            const result = Self{};

            std.debug.assert(result.count() == 0);
            std.debug.assert(result.initialized);

            return result;
        }

        pub fn is_valid(self: *const Self) bool {
            std.debug.assert(@intFromPtr(self) != 0);

            const result = self.initialized;

            return result;
        }

        pub fn clear(self: *Self) void {
            std.debug.assert(self.is_valid());

            @memset(&self.keys_down, false);

            std.debug.assert(self.count() == 0);
            std.debug.assert(self.is_valid());
        }

        pub fn set_down(self: *Self, keycode: u8, down: bool) void {
            std.debug.assert(self.is_valid());
            std.debug.assert(keycode < key_count);

            self.keys_down[keycode] = down;

            std.debug.assert(self.keys_down[keycode] == down);
        }

        pub fn is_down(self: *const Self, keycode: u8) bool {
            std.debug.assert(self.is_valid());
            std.debug.assert(keycode < key_count);

            const result = self.keys_down[keycode];

            return result;
        }

        pub fn count(self: *const Self) u32 {
            std.debug.assert(@intFromPtr(self) != 0);

            var result: u32 = 0;
            var i: u32 = 0;

            while (i < key_count) : (i += 1) {
                std.debug.assert(i < key_count);

                if (self.keys_down[i]) {
                    result += 1;
                }
            }

            std.debug.assert(i == key_count);
            std.debug.assert(result <= key_count);

            return result;
        }
    };
}
