const std = @import("std");

const Mutex = @import("../sync.zig").Mutex;

const slot_mod = @import("slot.zig");

const assert = std.debug.assert;

pub const BaseError = error{
    NotFound,
    RegistryFull,
};

pub fn BaseRegistryType(
    comptime Entry: type,
    comptime capacity: u32,
    comptime options: Options,
) type {
    return struct {
        const Instance = @This();
        const Slot = slot_mod.SlotManagerType(Entry, capacity);

        slot: Slot = Slot.init(),
        paused: if (options.has_paused) bool else void = if (options.has_paused) false else {},
        mutex: if (options.has_mutex) Mutex else void = if (options.has_mutex) .{} else {},

        pub fn init() Instance {
            return Instance{};
        }

        pub fn is_valid(instance: *const Instance) bool {
            return instance.slot.is_valid();
        }

        pub fn count(instance: *const Instance) u32 {
            return instance.slot.count;
        }

        pub fn is_empty(instance: *const Instance) bool {
            return instance.slot.count == 0;
        }

        pub fn set_paused(instance: *Instance, value: bool) void {
            if (options.has_mutex) instance.mutex.lock();
            defer if (options.has_mutex) instance.mutex.unlock();

            if (options.has_paused) {
                instance.paused = value;
            }
        }

        pub fn is_paused(instance: *const Instance) bool {
            if (options.has_paused) {
                return instance.paused;
            }
            return false;
        }

        pub fn allocate(instance: *Instance) BaseError!struct { slot: u32, id: u32 } {
            if (options.has_mutex) instance.mutex.lock();
            defer if (options.has_mutex) instance.mutex.unlock();

            const allocation = instance.slot.allocate() orelse return error.RegistryFull;

            return .{
                .slot = allocation.slot,
                .id = allocation.id,
            };
        }

        pub fn allocate_locked(instance: *Instance) BaseError!struct { slot: u32, id: u32 } {
            const allocation = instance.slot.allocate() orelse return error.RegistryFull;

            return .{
                .slot = allocation.slot,
                .id = allocation.id,
            };
        }

        pub fn free_by_id(instance: *Instance, id: u32) BaseError!u32 {
            assert(id >= 1);

            if (options.has_mutex) instance.mutex.lock();
            defer if (options.has_mutex) instance.mutex.unlock();

            return instance.slot.free_by_id(id) orelse return error.NotFound;
        }

        pub fn free_by_id_locked(instance: *Instance, id: u32) BaseError!u32 {
            assert(id >= 1);

            return instance.slot.free_by_id(id) orelse return error.NotFound;
        }

        pub fn free_locked(instance: *Instance, slot: u32) BaseError!u32 {
            assert(slot < capacity);

            if (!instance.slot.entries[slot].is_active()) {
                return error.NotFound;
            }

            instance.slot.entries[slot] = .{};
            instance.slot.count -= 1;

            return slot;
        }

        pub fn get_by_id(instance: *Instance, id: u32) ?*Entry {
            assert(id >= 1);

            return instance.slot.get_by_id(id);
        }

        pub fn get(instance: *Instance, slot: u32) ?*Entry {
            assert(slot < capacity);

            return instance.slot.get(slot);
        }

        pub fn find_by_id(instance: *const Instance, id: u32) ?u32 {
            assert(id >= 1);

            return instance.slot.find_by_id(id);
        }

        pub fn clear(instance: *Instance) void {
            if (options.has_mutex) instance.mutex.lock();
            defer if (options.has_mutex) instance.mutex.unlock();

            instance.slot.clear();
        }

        pub fn clear_locked(instance: *Instance) void {
            instance.slot.clear();
        }

        pub fn lock(instance: *Instance) void {
            if (options.has_mutex) {
                instance.mutex.lock();
            }
        }

        pub fn unlock(instance: *Instance) void {
            if (options.has_mutex) {
                instance.mutex.unlock();
            }
        }

        pub fn iterator(instance: *Instance) Slot.Iterator {
            assert(instance.slot.count <= capacity);

            return instance.slot.iterator();
        }

        pub fn entries(instance: *Instance) *[capacity]Entry {
            assert(instance.slot.count <= capacity);

            return &instance.slot.entries;
        }
    };
}

pub const Options = struct {
    has_mutex: bool = false,
    has_paused: bool = false,
};

const testing = std.testing;

const TestEntry = struct {
    id: u32 = 0,
    active: bool = false,
    value: u32 = 0,

    pub fn is_active(entry: *const TestEntry) bool {
        return entry.active;
    }

    pub fn is_valid(entry: *const TestEntry) bool {
        if (!entry.active) return true;
        return entry.id >= 1;
    }

    pub fn get_id(entry: *const TestEntry) u32 {
        return entry.id;
    }
};

test "a fresh registry starts empty" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    const reg = Registry.init();

    try testing.expect(reg.is_valid());
    try testing.expectEqual(@as(u32, 0), reg.count());
    try testing.expect(reg.is_empty());
}

test "a registry can be built with a mutex" {
    const Registry = BaseRegistryType(TestEntry, 8, .{ .has_mutex = true });
    const reg = Registry.init();

    try testing.expect(reg.is_valid());
}

test "a registry can be built paused" {
    const Registry = BaseRegistryType(TestEntry, 8, .{ .has_paused = true });
    const reg = Registry.init();

    try testing.expect(reg.is_valid());
    try testing.expect(!reg.is_paused());
}

test "allocating gives a slot" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc = try reg.allocate();

    try testing.expect(alloc.id >= 1);
    try testing.expect(alloc.slot < 8);
}

test "allocating repeatedly gives distinct slots" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc1 = try reg.allocate();
    reg.slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    const alloc2 = try reg.allocate();
    reg.slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    try testing.expect(alloc1.id != alloc2.id);
    try testing.expect(alloc1.slot != alloc2.slot);
}

test "a full registry refuses another slot" {
    const Registry = BaseRegistryType(TestEntry, 2, .{});
    var reg = Registry.init();

    const alloc1 = try reg.allocate();
    reg.slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    const alloc2 = try reg.allocate();
    reg.slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    const result = reg.allocate();

    try testing.expectError(BaseError.RegistryFull, result);
}

test "freeing by id releases the slot" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc = try reg.allocate();
    reg.slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true };

    const freed = try reg.free_by_id(alloc.id);

    try testing.expectEqual(alloc.slot, freed);
}

test "freeing an unknown id is reported" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    var reg = Registry.init();

    const result = reg.free_by_id(999);

    try testing.expectError(BaseError.NotFound, result);
}

test "a registry returns an entry by id" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc = try reg.allocate();
    reg.slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true, .value = 42 };

    const entry = reg.get_by_id(alloc.id);

    try testing.expect(entry != null);
    try testing.expectEqual(@as(u32, 42), entry.?.value);
}

test "a registry returns nothing for an unknown id" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    var reg = Registry.init();

    const entry = reg.get_by_id(999);

    try testing.expect(entry == null);
}

test "a registry returns an entry by slot" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc = try reg.allocate();
    reg.slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true, .value = 123 };

    const entry = reg.get(alloc.slot);

    try testing.expect(entry != null);
    try testing.expectEqual(@as(u32, 123), entry.?.value);
}

test "a registry finds the slot holding an id" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc = try reg.allocate();
    reg.slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true };

    const slot = reg.find_by_id(alloc.id);

    try testing.expect(slot != null);
    try testing.expectEqual(alloc.slot, slot.?);
}

test "clearing a registry releases every slot" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc1 = try reg.allocate();
    reg.slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    const alloc2 = try reg.allocate();
    reg.slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    reg.clear();

    try testing.expect(reg.is_empty());
    try testing.expectEqual(@as(u32, 0), reg.count());
}

test "pausing a registry updates its flag" {
    const Registry = BaseRegistryType(TestEntry, 8, .{ .has_paused = true });
    var reg = Registry.init();

    try testing.expect(!reg.is_paused());

    reg.set_paused(true);

    try testing.expect(reg.is_paused());

    reg.set_paused(false);

    try testing.expect(!reg.is_paused());
}

test "a registry without the flag is never paused" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    const reg = Registry.init();

    try testing.expect(!reg.is_paused());
}

test "a registry counts the entries it holds" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    var reg = Registry.init();

    try testing.expectEqual(@as(u32, 0), reg.count());

    const alloc1 = try reg.allocate();
    reg.slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    try testing.expectEqual(@as(u32, 1), reg.count());

    const alloc2 = try reg.allocate();
    reg.slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    try testing.expectEqual(@as(u32, 2), reg.count());
}

test "a registry reports whether it is empty" {
    const Registry = BaseRegistryType(TestEntry, 8, .{});
    var reg = Registry.init();

    try testing.expect(reg.is_empty());

    const alloc = try reg.allocate();
    reg.slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true };

    try testing.expect(!reg.is_empty());
}

test "a registry iterates over its active entries" {
    const Registry = BaseRegistryType(TestEntry, 4, .{});
    var reg = Registry.init();

    const alloc1 = try reg.allocate();
    reg.slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true, .value = 10 };

    const alloc2 = try reg.allocate();
    reg.slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true, .value = 20 };

    var iter = reg.iterator();
    var sum: u32 = 0;

    while (iter.next()) |entry| {
        sum += entry.value;
    }

    try testing.expectEqual(@as(u32, 30), sum);
}

test "a registry exposes its entries" {
    const Registry = BaseRegistryType(TestEntry, 4, .{});
    var reg = Registry.init();

    const entries = reg.entries();

    try testing.expectEqual(@as(usize, 4), entries.len);
}

test "base options start at their defaults" {
    const opts = Options{};

    try testing.expect(!opts.has_mutex);
    try testing.expect(!opts.has_paused);
}

test "base options carry the mutex they are built with" {
    const opts = Options{ .has_mutex = true };

    try testing.expect(opts.has_mutex);
    try testing.expect(!opts.has_paused);
}

test "base options carry the paused flag they are built with" {
    const opts = Options{ .has_paused = true };

    try testing.expect(!opts.has_mutex);
    try testing.expect(opts.has_paused);
}

test "base options carry a mutex and a paused flag together" {
    const opts = Options{ .has_mutex = true, .has_paused = true };

    try testing.expect(opts.has_mutex);
    try testing.expect(opts.has_paused);
}
