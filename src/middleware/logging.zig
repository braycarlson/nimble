const std = @import("std");

const key_event = @import("../event/key.zig");
const response_mod = @import("../response.zig");
const base = @import("base.zig");

const Key = key_event.Key;
const Response = response_mod.Response;
const Next = base.Next;

pub const LoggingMiddleware = struct {
    prefix: []const u8,
    enabled: bool = true,

    pub fn init(prefix: []const u8) LoggingMiddleware {
        std.debug.assert(prefix.len > 0);
        std.debug.assert(prefix.len <= 64);

        const result = LoggingMiddleware{ .prefix = prefix };

        std.debug.assert(result.enabled);
        std.debug.assert(result.prefix.len > 0);

        return result;
    }

    pub fn process(self: *LoggingMiddleware, key: *const Key, next: *const Next) Response {
        std.debug.assert(self.prefix.len > 0);
        std.debug.assert(key.is_valid());

        if (self.enabled) {
            std.debug.print("{s}: key=0x{X:0>2} down={}\n", .{
                self.prefix,
                key.value,
                key.down,
            });
        }

        const response = next.invoke(key);

        std.debug.assert(response.is_valid());

        if (self.enabled) {
            std.debug.print("{s}: response={s}\n", .{
                self.prefix,
                @tagName(response),
            });
        }

        return response;
    }

    pub fn set_enabled(self: *LoggingMiddleware, value: bool) void {
        std.debug.assert(self.prefix.len > 0);

        self.enabled = value;
    }

    pub fn is_enabled(self: *const LoggingMiddleware) bool {
        std.debug.assert(self.prefix.len > 0);

        return self.enabled;
    }
};
