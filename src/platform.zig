const builtin = @import("builtin");
const build_options = @import("build_options");

const contract = @import("platform/contract.zig");

pub const Capabilities = contract.Capabilities;

pub const backend = if (build_options.backend_mock)
    @import("platform/mock.zig")
else switch (builtin.os.tag) {
    .linux => @import("platform/linux.zig"),
    .windows => @import("platform/windows.zig"),
    else => @compileError("nimble: unsupported target OS"),
};

pub const mock = if (build_options.backend_mock)
    backend
else
    @compileError("nimble: mock surface requires -Dbackend=mock");

pub const capabilities: Capabilities = backend.capabilities;

pub const sync = switch (builtin.os.tag) {
    .linux => @import("platform/linux/sync.zig"),
    .windows => @import("platform/windows/sync.zig"),
    else => @compileError("nimble: unsupported target OS"),
};

comptime {
    contract.assert_backend(backend);
}
