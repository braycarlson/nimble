const std = @import("std");

const key_event = @import("../event/key.zig");
const response_mod = @import("../response.zig");
const base = @import("base.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Response = response_mod.Response;
const Next = base.Next;

pub const LoggingMiddleware = struct {
    prefix: []const u8,
    enabled: bool = true,

    pub fn init(prefix: []const u8) LoggingMiddleware {
        assert(prefix.len > 0);
        assert(prefix.len <= 64);

        const result = LoggingMiddleware{ .prefix = prefix };

        assert(result.enabled);
        assert(result.prefix.len > 0);

        return result;
    }

    pub fn process(middleware: *LoggingMiddleware, key: *const Key, next: *const Next) Response {
        assert(middleware.prefix.len > 0);
        assert(key.is_valid());

        if (middleware.enabled) {
            std.debug.print("{s}: key=0x{X:0>2} down={}\n", .{
                middleware.prefix,
                key.value,
                key.down,
            });
        }

        const response = next.invoke(key);

        assert(response.is_valid());

        if (middleware.enabled) {
            std.debug.print("{s}: response={s}\n", .{
                middleware.prefix,
                @tagName(response),
            });
        }

        return response;
    }

    pub fn set_enabled(middleware: *LoggingMiddleware, value: bool) void {
        assert(middleware.prefix.len > 0);

        middleware.enabled = value;
    }

    pub fn is_enabled(middleware: *const LoggingMiddleware) bool {
        assert(middleware.prefix.len > 0);

        return middleware.enabled;
    }
};
