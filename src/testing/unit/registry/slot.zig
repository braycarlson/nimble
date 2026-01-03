const std = @import("std");
const input = @import("input");

const slot_mod = input.registry.slot;

const testing = std.testing;

const TestEntry = struct {
    id: u32 = 0,
    active: bool = false,
    value: u32 = 0,

    pub fn is_active(self: *const TestEntry) bool {
        return self.active;
    }

    pub fn is_valid(self: *const TestEntry) bool {
        if (!self.active) return true;
        return self.id >= 1;
    }

    pub fn get_id(self: *const TestEntry) u32 {
        return self.id;
    }
};

test "SlotManager.init" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
    const slot = Slot.init();

    try testing.expect(slot.is_valid());
    try testing.expectEqual(@as(u32, 0), slot.count);
    try testing.expectEqual(@as(u32, 1), slot.id_next);
}

test "SlotManager.allocate" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
    var slot = Slot.init();

    const alloc = slot.allocate();

    try testing.expect(alloc != null);
    try testing.expectEqual(@as(u32, 0), alloc.?.slot);
    try testing.expectEqual(@as(u32, 1), alloc.?.id);
    try testing.expectEqual(@as(u32, 1), slot.count);
    try testing.expectEqual(@as(u32, 2), slot.id_next);
}

test "SlotManager.allocate multiple" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
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

test "SlotManager.allocate full" {
    const Slot = slot_mod.SlotManager(TestEntry, 2);
    var slot = Slot.init();

    const alloc1 = slot.allocate().?;
    slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    const alloc2 = slot.allocate().?;
    slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    const alloc3 = slot.allocate();

    try testing.expect(alloc3 == null);
    try testing.expectEqual(@as(u32, 2), slot.count);
}

test "SlotManager.free_by_id" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
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

test "SlotManager.free_by_id not found" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
    var slot = Slot.init();

    const freed = slot.free_by_id(999);

    try testing.expect(freed == null);
}

test "SlotManager.free_by_id reuse slot" {
    const Slot = slot_mod.SlotManager(TestEntry, 2);
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

test "SlotManager.get_by_id" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
    var slot = Slot.init();

    const alloc = slot.allocate().?;
    slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true, .value = 42 };

    const entry = slot.get_by_id(alloc.id);

    try testing.expect(entry != null);
    try testing.expectEqual(@as(u32, 42), entry.?.value);
}

test "SlotManager.get_by_id not found" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
    var slot = Slot.init();

    const entry = slot.get_by_id(999);

    try testing.expect(entry == null);
}

test "SlotManager.get" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
    var slot = Slot.init();

    const alloc = slot.allocate().?;
    slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true, .value = 123 };

    const entry = slot.get(0);

    try testing.expect(entry != null);
    try testing.expectEqual(@as(u32, 123), entry.?.value);
}

test "SlotManager.get inactive" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
    var slot = Slot.init();

    const entry = slot.get(0);

    try testing.expect(entry == null);
}

test "SlotManager.get out of bounds" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
    var slot = Slot.init();

    const entry = slot.get(100);

    try testing.expect(entry == null);
}

test "SlotManager.find_by_id" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
    var slot = Slot.init();

    const alloc = slot.allocate().?;
    slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true };

    const found = slot.find_by_id(alloc.id);

    try testing.expect(found != null);
    try testing.expectEqual(@as(u32, 0), found.?);
}

test "SlotManager.find_by_id not found" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
    const slot = Slot.init();

    const found = slot.find_by_id(999);

    try testing.expect(found == null);
}

test "SlotManager.clear" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
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

test "SlotManager.iterator" {
    const Slot = slot_mod.SlotManager(TestEntry, 4);
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

test "SlotManager.iterator empty" {
    const Slot = slot_mod.SlotManager(TestEntry, 4);
    var slot = Slot.init();

    var iter = slot.iterator();
    var count: u32 = 0;

    while (iter.next()) |_| {
        count += 1;
    }

    try testing.expectEqual(@as(u32, 0), count);
}

test "SlotManager.is_valid" {
    const Slot = slot_mod.SlotManager(TestEntry, 8);
    var slot = Slot.init();

    try testing.expect(slot.is_valid());

    const alloc = slot.allocate().?;
    slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true };

    try testing.expect(slot.is_valid());
}

test "SlotManager id wraps" {
    const Slot = slot_mod.SlotManager(TestEntry, 2);
    var slot = Slot.init();

    slot.id_next = slot_mod.id_max;

    const alloc = slot.allocate().?;

    try testing.expectEqual(slot_mod.id_max, alloc.id);
    try testing.expectEqual(slot_mod.id_min, slot.id_next);
}
