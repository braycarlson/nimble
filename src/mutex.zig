const win32 = @import("win32").everything;

pub const Mutex = struct {
    srwlock: win32.RTL_SRWLOCK = .{ .Ptr = null },

    pub fn lock(self: *Mutex) void {
        win32.AcquireSRWLockExclusive(&self.srwlock);
    }

    pub fn unlock(self: *Mutex) void {
        win32.ReleaseSRWLockExclusive(&self.srwlock);
    }
};
