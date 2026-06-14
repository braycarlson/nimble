const w32 = @import("win32").everything;

pub const Mutex = struct {
    srwlock: w32.RTL_SRWLOCK = .{ .Ptr = null },

    pub fn lock(self: *Mutex) void {
        w32.AcquireSRWLockExclusive(&self.srwlock);
    }

    pub fn unlock(self: *Mutex) void {
        w32.ReleaseSRWLockExclusive(&self.srwlock);
    }
};
