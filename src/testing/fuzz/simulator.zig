const std = @import("std");

const input = @import("input");
const state = input.state;

const Keyboard = state.Keyboard;

const model_mod = @import("model.zig");
const property = @import("property");
const invariant = property.invariant;

const Model = model_mod.Model;
const Operation = model_mod.Operation;

pub const trace_capacity: u32 = 4096;
pub const step_max: u32 = 0xFFFFFFFF;

pub const Failure = struct {
    step: u32,
    invariant: []const u8,
    operation: Operation,
    seed: u64,

    pub fn format(self: Failure, writer: anytype) !void {
        std.debug.assert(self.step > 0 or self.step == 0);
        std.debug.assert(self.invariant.len > 0);

        try writer.print("Failure at step {d}: invariant '{s}' violated by ", .{
            self.step,
            self.invariant,
        });

        try self.operation.format(writer);

        try writer.print("\n  Reproduce with: --seed={d}\n", .{self.seed});
    }
};

pub const Trace = struct {
    operations: [trace_capacity]Operation = undefined,
    len: u32 = 0,

    pub fn push(self: *Trace, op: Operation) void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(self.len <= trace_capacity);

        if (self.len < trace_capacity) {
            self.operations[self.len] = op;
            self.len += 1;
        }

        std.debug.assert(self.len <= trace_capacity);
    }

    pub fn slice(self: *const Trace) []const Operation {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(self.len <= trace_capacity);

        const result = self.operations[0..self.len];

        std.debug.assert(result.len == self.len);

        return result;
    }

    pub fn clear(self: *Trace) void {
        std.debug.assert(@intFromPtr(self) != 0);

        self.len = 0;

        std.debug.assert(self.len == 0);
    }
};

pub const Simulator = struct {
    keyboard: Keyboard,
    model: Model,
    trace: Trace,
    prng: std.Random.DefaultPrng,
    step: u32,
    seed: u64,

    pub fn init(seed: u64) Simulator {
        const result = Simulator{
            .keyboard = Keyboard.init(),
            .model = Model.init(),
            .trace = Trace{},
            .prng = std.Random.DefaultPrng.init(seed),
            .step = 0,
            .seed = seed,
        };

        std.debug.assert(result.step == 0);
        std.debug.assert(result.trace.len == 0);

        return result;
    }

    pub fn reset(self: *Simulator) void {
        std.debug.assert(@intFromPtr(self) != 0);

        self.keyboard = Keyboard.init();
        self.model = Model.init();
        self.trace.clear();
        self.step = 0;

        std.debug.assert(self.step == 0);
        std.debug.assert(self.trace.len == 0);
    }

    pub fn reseed(self: *Simulator, seed: u64) void {
        std.debug.assert(@intFromPtr(self) != 0);

        self.reset();
        self.prng = std.Random.DefaultPrng.init(seed);
        self.seed = seed;

        std.debug.assert(self.step == 0);
        std.debug.assert(self.seed == seed);
    }

    pub fn run(self: *Simulator, steps: u32) ?Failure {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(steps > 0 or steps == 0);

        var random = self.prng.random();

        var i: u32 = 0;

        while (i < steps) : (i += 1) {
            std.debug.assert(i < steps);

            const failure = self.execute_step(&random);

            if (failure) |f| {
                return f;
            }
        }

        std.debug.assert(i == steps);

        return null;
    }

    fn execute_step(self: *Simulator, random: *std.Random) ?Failure {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(random) != 0);

        const op = model_mod.generate_operation(random, &self.model);

        self.trace.push(op);

        op.apply(&self.keyboard);
        op.apply_to_model(&self.model);

        self.step += 1;

        const failure = self.check_invariants(op);

        return failure;
    }

    fn check_invariants(self: *const Simulator, op: Operation) ?Failure {
        std.debug.assert(@intFromPtr(self) != 0);

        if (!self.model.matches(&self.keyboard)) {
            return Failure{
                .step = self.step,
                .invariant = "model_mismatch",
                .operation = op,
                .seed = self.seed,
            };
        }

        const ctx = invariant.Context{
            .keyboard = &self.keyboard,
            .last_key = extract_key(op),
            .last_down = extract_down(op),
        };

        if (invariant.check_all(&ctx)) |failed| {
            return Failure{
                .step = self.step,
                .invariant = failed,
                .operation = op,
                .seed = self.seed,
            };
        }

        return null;
    }

    pub fn replay(self: *Simulator, operations: []const Operation) ?Failure {
        std.debug.assert(@intFromPtr(self) != 0);

        self.reset();

        var i: u32 = 0;

        while (i < operations.len and i < step_max) : (i += 1) {
            std.debug.assert(i < operations.len);

            const op = operations[i];

            op.apply(&self.keyboard);
            op.apply_to_model(&self.model);

            self.step = i + 1;

            if (!self.model.matches(&self.keyboard)) {
                return Failure{
                    .step = self.step,
                    .invariant = "model_mismatch",
                    .operation = op,
                    .seed = self.seed,
                };
            }
        }

        std.debug.assert(i == operations.len or i == step_max);

        return null;
    }
};

fn extract_key(op: Operation) ?u8 {
    const result: ?u8 = switch (op) {
        .keydown => |k| k,
        .keyup => |k| k,
        .clear => null,
    };

    return result;
}

fn extract_down(op: Operation) bool {
    const result: bool = switch (op) {
        .keydown => true,
        .keyup => false,
        .clear => false,
    };

    return result;
}

const testing = std.testing;

test "Simulator basic" {
    var sim = Simulator.init(42);

    const failure = sim.run(1000);

    try testing.expect(failure == null);
}

test "Simulator deterministic" {
    var sim1 = Simulator.init(12345);
    var sim2 = Simulator.init(12345);

    _ = sim1.run(100);
    _ = sim2.run(100);

    try testing.expect(sim1.model.matches(&sim2.keyboard));
}

test "Simulator reseed" {
    var sim = Simulator.init(42);

    _ = sim.run(50);

    sim.reseed(42);

    try testing.expectEqual(@as(u32, 0), sim.step);
    try testing.expectEqual(@as(u32, 0), sim.trace.len);
}
