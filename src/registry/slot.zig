const std = @import("std");

const assert = std.debug.assert;

pub const id_min: u32 = 1;
pub const id_max: u32 = 0xFFFFFFFF;

pub fn SlotManagerType(comptime Entry: type, comptime capacity: u32) type {
    if (capacity == 0) {
        @compileError("SlotManagerType capacity must be at least 1");
    }

    return struct {
        const Instance = @This();

        entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
        count: u32 = 0,
        id_next: u32 = id_min,

        pub fn init() Instance {
            const result = Instance{};

            assert(result.count == 0);
            assert(result.id_next == id_min);
            assert(result.entries.len == capacity);

            return result;
        }

        pub fn is_valid(instance: *const Instance) bool {
            assert(instance.entries.len == capacity);

            const valid_count = instance.count <= capacity;
            const valid_id = instance.id_next >= id_min;
            const valid_entries = instance.validate_entries();

            return valid_count and valid_id and valid_entries;
        }

        fn validate_entries(instance: *const Instance) bool {
            var active_count: u32 = 0;
            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                if (instance.entries[i].is_active()) {
                    active_count += 1;

                    if (!instance.entries[i].is_valid()) {
                        return false;
                    }
                }
            }

            return active_count == instance.count;
        }

        pub fn allocate(instance: *Instance) ?struct { slot: u32, id: u32 } {
            assert(instance.is_valid());

            if (instance.count >= capacity) {
                return null;
            }

            const slot = instance.find_empty() orelse return null;

            assert(slot < capacity);
            assert(!instance.entries[slot].is_active());

            const id = instance.id_next;

            if (instance.id_next < id_max) {
                instance.id_next += 1;
            } else {
                instance.id_next = id_min;

                assert(instance.find_by_id(instance.id_next) == null);
            }

            instance.count += 1;

            assert(instance.count <= capacity);
            assert(instance.count >= 1);
            assert(id >= id_min);

            return .{
                .slot = slot,
                .id = id,
            };
        }

        pub fn free_by_id(instance: *Instance, id: u32) ?u32 {
            assert(instance.is_valid());
            assert(id >= id_min);

            const slot = instance.find_by_id(id) orelse return null;

            assert(slot < capacity);
            assert(instance.entries[slot].is_active());

            instance.entries[slot] = .{};
            instance.count -= 1;

            assert(!instance.entries[slot].is_active());
            assert(instance.find_by_id(id) == null);

            return slot;
        }

        pub fn get_by_id(instance: *Instance, id: u32) ?*Entry {
            assert(id >= id_min);

            const slot = instance.find_by_id(id) orelse return null;

            assert(slot < capacity);

            return &instance.entries[slot];
        }

        pub fn get(instance: *Instance, slot: u32) ?*Entry {
            if (slot >= capacity) {
                return null;
            }

            assert(slot < capacity);

            if (!instance.entries[slot].is_active()) {
                return null;
            }

            return &instance.entries[slot];
        }

        pub fn find_by_id(instance: *const Instance, id: u32) ?u32 {
            assert(id >= id_min);

            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                if (instance.entries[i].is_active() and instance.entries[i].get_id() == id) {
                    return i;
                }
            }

            return null;
        }

        fn find_empty(instance: *const Instance) ?u32 {
            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                if (!instance.entries[i].is_active()) {
                    return i;
                }
            }

            return null;
        }

        pub fn clear(instance: *Instance) void {
            var i: u32 = 0;

            while (i < capacity) : (i += 1) {
                instance.entries[i] = .{};
            }

            instance.count = 0;

            assert(instance.count == 0);
        }

        pub const Iterator = struct {
            slot: *Instance,
            index: u32 = 0,

            pub fn next(cursor: *Iterator) ?*Entry {
                while (cursor.index < capacity) {
                    const i = cursor.index;
                    cursor.index += 1;

                    if (cursor.slot.entries[i].is_active()) {
                        return &cursor.slot.entries[i];
                    }
                }

                return null;
            }

            pub fn reset(cursor: *Iterator) void {
                cursor.index = 0;
            }
        };

        pub fn iterator(instance: *Instance) Iterator {
            return Iterator{ .slot = instance };
        }
    };
}

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

test "a fresh slot manager holds no slots" {
    const Slot = SlotManagerType(TestEntry, 8);
    const slot = Slot.init();

    try testing.expect(slot.is_valid());
    try testing.expectEqual(@as(u32, 0), slot.count);
    try testing.expectEqual(@as(u32, 1), slot.id_next);
}

test "allocating gives a slot" {
    const Slot = SlotManagerType(TestEntry, 8);
    var slot = Slot.init();

    const alloc = slot.allocate();

    try testing.expect(alloc != null);
    try testing.expectEqual(@as(u32, 0), alloc.?.slot);
    try testing.expectEqual(@as(u32, 1), alloc.?.id);
    try testing.expectEqual(@as(u32, 1), slot.count);
    try testing.expectEqual(@as(u32, 2), slot.id_next);
}

test "allocating repeatedly gives distinct slots" {
    const Slot = SlotManagerType(TestEntry, 8);
    var slot = Slot.init();

    const alloc1 = slot.allocate().?;
    slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    const alloc2 = slot.allocate().?;
    slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    const alloc3 = slot.allocate().?;
    slot.entries[alloc3.slot] = TestEntry{ .id = alloc3.id, .active = true };

    try testing.expectEqual(@as(u32, 1), alloc1.id);
    try testing.expectEqual(@as(u32, 2), alloc2.id);
    try testing.expectEqual(@as(u32, 3), alloc3.id);
    try testing.expectEqual(@as(u32, 3), slot.count);
}

test "a full slot manager refuses another slot" {
    const Slot = SlotManagerType(TestEntry, 2);
    var slot = Slot.init();

    const alloc1 = slot.allocate().?;
    slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    const alloc2 = slot.allocate().?;
    slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    const alloc3 = slot.allocate();

    try testing.expect(alloc3 == null);
    try testing.expectEqual(@as(u32, 2), slot.count);
}

test "freeing by id releases the slot" {
    const Slot = SlotManagerType(TestEntry, 8);
    var slot = Slot.init();

    const alloc = slot.allocate().?;
    slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true };

    try testing.expectEqual(@as(u32, 1), slot.count);

    const freed = slot.free_by_id(alloc.id);

    try testing.expect(freed != null);
    try testing.expectEqual(@as(u32, 0), freed.?);
    try testing.expectEqual(@as(u32, 0), slot.count);
    try testing.expect(!slot.entries[0].is_active());
}

test "freeing an unknown id is reported" {
    const Slot = SlotManagerType(TestEntry, 8);
    var slot = Slot.init();

    const freed = slot.free_by_id(999);

    try testing.expect(freed == null);
}

test "a freed slot is handed out again" {
    const Slot = SlotManagerType(TestEntry, 2);
    var slot = Slot.init();

    const alloc1 = slot.allocate().?;
    slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    const alloc2 = slot.allocate().?;
    slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    _ = slot.free_by_id(alloc1.id);

    const alloc3 = slot.allocate().?;

    try testing.expectEqual(@as(u32, 0), alloc3.slot);
    try testing.expectEqual(@as(u32, 3), alloc3.id);
}

test "a slot manager returns a slot by id" {
    const Slot = SlotManagerType(TestEntry, 8);
    var slot = Slot.init();

    const alloc = slot.allocate().?;
    slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true, .value = 42 };

    const entry = slot.get_by_id(alloc.id);

    try testing.expect(entry != null);
    try testing.expectEqual(@as(u32, 42), entry.?.value);
}

test "a slot manager returns nothing for an unknown id" {
    const Slot = SlotManagerType(TestEntry, 8);
    var slot = Slot.init();

    const entry = slot.get_by_id(999);

    try testing.expect(entry == null);
}

test "a slot manager returns a slot by index" {
    const Slot = SlotManagerType(TestEntry, 8);
    var slot = Slot.init();

    const alloc = slot.allocate().?;
    slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true, .value = 123 };

    const entry = slot.get(0);

    try testing.expect(entry != null);
    try testing.expectEqual(@as(u32, 123), entry.?.value);
}

test "an inactive slot is not returned" {
    const Slot = SlotManagerType(TestEntry, 8);
    var slot = Slot.init();

    const entry = slot.get(0);

    try testing.expect(entry == null);
}

test "an index past the end returns nothing" {
    const Slot = SlotManagerType(TestEntry, 8);
    var slot = Slot.init();

    const entry = slot.get(100);

    try testing.expect(entry == null);
}

test "a slot manager finds the index holding an id" {
    const Slot = SlotManagerType(TestEntry, 8);
    var slot = Slot.init();

    const alloc = slot.allocate().?;
    slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true };

    const found = slot.find_by_id(alloc.id);

    try testing.expect(found != null);
    try testing.expectEqual(@as(u32, 0), found.?);
}

test "an unknown id is found nowhere" {
    const Slot = SlotManagerType(TestEntry, 8);
    const slot = Slot.init();

    const found = slot.find_by_id(999);

    try testing.expect(found == null);
}

test "clearing a slot manager releases every slot" {
    const Slot = SlotManagerType(TestEntry, 8);
    var slot = Slot.init();

    const alloc1 = slot.allocate().?;
    slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    const alloc2 = slot.allocate().?;
    slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    slot.clear();

    try testing.expectEqual(@as(u32, 0), slot.count);
    try testing.expect(!slot.entries[0].is_active());
    try testing.expect(!slot.entries[1].is_active());
}

test "a slot manager iterates over its active slots" {
    const Slot = SlotManagerType(TestEntry, 4);
    var slot = Slot.init();

    const alloc1 = slot.allocate().?;
    slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true, .value = 10 };

    const alloc2 = slot.allocate().?;
    slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true, .value = 20 };

    var iter = slot.iterator();
    var sum: u32 = 0;
    var count: u32 = 0;

    while (iter.next()) |entry| {
        sum += entry.value;
        count += 1;
    }

    try testing.expectEqual(@as(u32, 30), sum);
    try testing.expectEqual(@as(u32, 2), count);
}

test "an empty slot manager iterates over nothing" {
    const Slot = SlotManagerType(TestEntry, 4);
    var slot = Slot.init();

    var iter = slot.iterator();
    var count: u32 = 0;

    while (iter.next()) |_| {
        count += 1;
    }

    try testing.expectEqual(@as(u32, 0), count);
}

test "a slot manager reports whether a slot is valid" {
    const Slot = SlotManagerType(TestEntry, 8);
    var slot = Slot.init();

    try testing.expect(slot.is_valid());

    const alloc = slot.allocate().?;
    slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true };

    try testing.expect(slot.is_valid());
}

test "a slot id wraps around" {
    const Slot = SlotManagerType(TestEntry, 2);
    var slot = Slot.init();

    slot.id_next = id_max;

    const alloc = slot.allocate().?;

    try testing.expectEqual(id_max, alloc.id);
    try testing.expectEqual(id_min, slot.id_next);
}
