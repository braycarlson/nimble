pub const input = struct {
    const simulator = @import("input/simulator.zig");
    const state = @import("input/state.zig");
    const recorder = @import("input/recorder.zig");
    const replay = @import("input/replay.zig");

    pub const VOPR = simulator.VOPR;
    pub const VOPRConfig = simulator.VOPRConfig;
    pub const VOPRStats = simulator.VOPRStats;
    pub const VOPRResult = simulator.VOPRResult;
    pub const ReplayEntry = simulator.ReplayEntry;
    pub const Operation = simulator.Operation;
    pub const OperationKind = simulator.OperationKind;
    pub const FaultKind = simulator.FaultKind;
    pub const FaultInjector = simulator.FaultInjector;
    pub const Workload = simulator.Workload;
    pub const PendingInput = simulator.PendingInput;
    pub const TestProfile = simulator.TestProfile;
    pub const RealisticConfig = simulator.RealisticConfig;

    pub const StateChecker = state.StateChecker;
    pub const Event = state.Event;
    pub const EventKind = state.EventKind;
    pub const Snapshot = state.Snapshot;
    pub const KeyboardSnapshot = state.KeyboardSnapshot;
    pub const RegistrySnapshot = state.RegistrySnapshot;
    pub const InvariantKind = state.InvariantKind;

    pub const Recorder = recorder.Recorder;
    pub const Recording = recorder.Recording;
    pub const Format = recorder.Format;

    pub const Replayer = replay.Replayer;
    pub const ReplayState = replay.ReplayState;
    pub const ReplayCallback = replay.ReplayCallback;
};

pub const hook = @import("hook/root.zig");
pub const stress = @import("stress/root.zig");

pub const VOPR = input.VOPR;
pub const VOPRConfig = input.VOPRConfig;
pub const VOPRStats = input.VOPRStats;
pub const VOPRResult = input.VOPRResult;

pub const HookSimulator = hook.Simulator;
pub const HookConfig = hook.Config;
pub const HookStats = hook.Stats;

pub const StressVOPR = stress.StressVOPR;
pub const StressVOPRConfig = stress.StressVOPRConfig;

test {
    _ = input.simulator;
    _ = input.state;
    _ = input.recorder;
    _ = input.replay;
    _ = hook.simulator;
    _ = hook.recorder;
    _ = hook.replay;
    _ = stress.simulator;
    _ = stress.recorder;
    _ = stress.replay;
}
