const std = @import("std");

const key_event = @import("../event.zig").key;
const middleware_module = @import("../middleware.zig");
const response_module = @import("../response.zig");

const assert = std.debug.assert;

const Key = key_event.Key;
const Response = response_module.Response;
const Next = middleware_module.Next;

pub const Logging = struct {
    prefix: []const u8,
    enabled: bool = true,

    pub fn init(prefix: []const u8) Logging {
        assert(prefix.len > 0);
        assert(prefix.len <= 64);

        const result = Logging{ .prefix = prefix };

        assert(result.enabled);
        assert(result.prefix.len > 0);

        return result;
    }

    pub fn process(middleware: *Logging, key: *const Key, next: *const Next) Response {
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
            std.debug.print("{s}: response={s}\n", .{ middleware.prefix, @tagName(response) });
        }

        return response;
    }

    pub fn enable(middleware: *Logging) void {
        assert(middleware.prefix.len > 0);

        middleware.enabled = true;
    }

    pub fn disable(middleware: *Logging) void {
        assert(middleware.prefix.len > 0);

        middleware.enabled = false;
    }

    pub fn is_enabled(middleware: *const Logging) bool {
        assert(middleware.prefix.len > 0);

        return middleware.enabled;
    }
};

const testing = std.testing;

test Logging {
    var logging = Logging.init("nimble");

    try testing.expect(logging.is_enabled());

    logging.disable();

    try testing.expect(!logging.is_enabled());

    logging.enable();

    try testing.expect(logging.is_enabled());
}
