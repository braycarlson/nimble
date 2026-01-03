const std = @import("std");
const input = @import("input");

const base_mod = input.registry.base;

const BaseRegistry = base_mod.BaseRegistry;
const BaseError = base_mod.BaseError;
const Options = base_mod.Options;

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

test "BaseRegistry.init no options" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    const reg = Registry.init();

    try testing.expect(reg.is_valid());
    try testing.expectEqual(@as(u32, 0), reg.count());
    try testing.expect(reg.is_empty());
}

test "BaseRegistry.init with mutex" {
    const Registry = BaseRegistry(TestEntry, 8, .{ .has_mutex = true });
    const reg = Registry.init();

    try testing.expect(reg.is_valid());
}

test "BaseRegistry.init with paused" {
    const Registry = BaseRegistry(TestEntry, 8, .{ .has_paused = true });
    const reg = Registry.init();

    try testing.expect(reg.is_valid());
    try testing.expect(!reg.is_paused());
}

test "BaseRegistry.allocate" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc = try reg.allocate();

    try testing.expect(alloc.id >= 1);
    try testing.expect(alloc.slot < 8);
}

test "BaseRegistry.allocate multiple" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc1 = try reg.allocate();
    reg.slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    const alloc2 = try reg.allocate();
    reg.slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    try testing.expect(alloc1.id != alloc2.id);
    try testing.expect(alloc1.slot != alloc2.slot);
}

test "BaseRegistry.allocate full" {
    const Registry = BaseRegistry(TestEntry, 2, .{});
    var reg = Registry.init();

    const alloc1 = try reg.allocate();
    reg.slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    const alloc2 = try reg.allocate();
    reg.slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    const result = reg.allocate();

    try testing.expectError(BaseError.RegistryFull, result);
}

test "BaseRegistry.free_by_id" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc = try reg.allocate();
    reg.slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true };

    const freed = try reg.free_by_id(alloc.id);

    try testing.expectEqual(alloc.slot, freed);
}

test "BaseRegistry.free_by_id not found" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    var reg = Registry.init();

    const result = reg.free_by_id(999);

    try testing.expectError(BaseError.NotFound, result);
}

test "BaseRegistry.get_by_id" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc = try reg.allocate();
    reg.slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true, .value = 42 };

    const entry = reg.get_by_id(alloc.id);

    try testing.expect(entry != null);
    try testing.expectEqual(@as(u32, 42), entry.?.value);
}

test "BaseRegistry.get_by_id not found" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    var reg = Registry.init();

    const entry = reg.get_by_id(999);

    try testing.expect(entry == null);
}

test "BaseRegistry.get" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc = try reg.allocate();
    reg.slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true, .value = 123 };

    const entry = reg.get(alloc.slot);

    try testing.expect(entry != null);
    try testing.expectEqual(@as(u32, 123), entry.?.value);
}

test "BaseRegistry.find_by_id" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc = try reg.allocate();
    reg.slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true };

    const slot = reg.find_by_id(alloc.id);

    try testing.expect(slot != null);
    try testing.expectEqual(alloc.slot, slot.?);
}

test "BaseRegistry.clear" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    var reg = Registry.init();

    const alloc1 = try reg.allocate();
    reg.slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    const alloc2 = try reg.allocate();
    reg.slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    reg.clear();

    try testing.expect(reg.is_empty());
    try testing.expectEqual(@as(u32, 0), reg.count());
}

test "BaseRegistry.set_paused" {
    const Registry = BaseRegistry(TestEntry, 8, .{ .has_paused = true });
    var reg = Registry.init();

    try testing.expect(!reg.is_paused());

    reg.set_paused(true);

    try testing.expect(reg.is_paused());

    reg.set_paused(false);

    try testing.expect(!reg.is_paused());
}

test "BaseRegistry.is_paused no flag" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    const reg = Registry.init();

    try testing.expect(!reg.is_paused());
}

test "BaseRegistry.count" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    var reg = Registry.init();

    try testing.expectEqual(@as(u32, 0), reg.count());

    const alloc1 = try reg.allocate();
    reg.slot.entries[alloc1.slot] = TestEntry{ .id = alloc1.id, .active = true };

    try testing.expectEqual(@as(u32, 1), reg.count());

    const alloc2 = try reg.allocate();
    reg.slot.entries[alloc2.slot] = TestEntry{ .id = alloc2.id, .active = true };

    try testing.expectEqual(@as(u32, 2), reg.count());
}

test "BaseRegistry.is_empty" {
    const Registry = BaseRegistry(TestEntry, 8, .{});
    var reg = Registry.init();

    try testing.expect(reg.is_empty());

    const alloc = try reg.allocate();
    reg.slot.entries[alloc.slot] = TestEntry{ .id = alloc.id, .active = true };

    try testing.expect(!reg.is_empty());
}

test "BaseRegistry.iterator" {
    const Registry = BaseRegistry(TestEntry, 4, .{});
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

test "BaseRegistry.entries" {
    const Registry = BaseRegistry(TestEntry, 4, .{});
    var reg = Registry.init();

    const entries = reg.entries();

    try testing.expectEqual(@as(usize, 4), entries.len);
}

test "Options default" {
    const opts = Options{};

    try testing.expect(!opts.has_mutex);
    try testing.expect(!opts.has_paused);
}

test "Options with mutex" {
    const opts = Options{ .has_mutex = true };

    try testing.expect(opts.has_mutex);
    try testing.expect(!opts.has_paused);
}

test "Options with paused" {
    const opts = Options{ .has_paused = true };

    try testing.expect(!opts.has_mutex);
    try testing.expect(opts.has_paused);
}

test "Options with both" {
    const opts = Options{ .has_mutex = true, .has_paused = true };

    try testing.expect(opts.has_mutex);
    try testing.expect(opts.has_paused);
}
