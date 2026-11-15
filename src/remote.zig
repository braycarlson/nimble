const std = @import("std");

const chord_registry = @import("registry.zig").chord;
const key_event = @import("event.zig").key;
const keycode = @import("keycode.zig");
const modifier = @import("modifier.zig");
const mouse_event = @import("event.zig").mouse;
const pattern_module = @import("builder.zig").pattern;
const platform = @import("platform.zig");
const position_module = @import("position.zig");
const response_module = @import("response.zig");
const sequence_registry = @import("registry.zig").sequence;

const assert = std.debug.assert;

const Key = key_event.Key;
const Keycode = keycode.Keycode;
const Modifier = modifier.Set;
const MouseEvent = mouse_event.MouseEvent;
const Position = position_module.Position;
const Response = response_module.Response;

pub const binding_count_max: u16 = 64;
pub const chord_keys_max: u8 = 8;
pub const delay_ms_max: u16 = 1000;
pub const filter_patterns_max: u8 = 16;
pub const scroll_clicks_max: u8 = 32;
pub const sequence_bytes_max: u8 = 8;
pub const text_bytes_max: u16 = 256;

pub const CapacityError = error{
    ChordTooLong,
    FilterTooLong,
    RegistrationsExhausted,
    SequenceTooLong,
    TextTooLong,
};

pub const PlatformError = error{
    ConnectFailed,
    SendFailed,
};

pub const RequestError = error{
    BindingDuplicate,
    CharacterInvalid,
    ChordInvalid,
    ClientDisconnected,
    DelayInvalid,
    HandleUnknown,
    ScrollInvalid,
    SequenceEmpty,
    TextInvalid,
};

pub const BindOptions = struct {
    consume: bool = true,
    exempt: bool = false,
};

pub const Blocked = struct {
    keyboard: bool = false,
    mouse: bool = false,
};

pub const ButtonAction = enum(u8) {
    down = 0,
    up = 1,
    click = 2,
};

pub const KeyAction = enum(u8) {
    down = 0,
    up = 1,
    press = 2,
    suppress = 3,
    dummy = 4,
};

pub const Pattern = struct {
    key: ?Keycode = null,
    modifiers: Modifier = .{},
    modifiers_match: Match = .exact,

    pub const Match = enum(u8) {
        exact = 0,
        at_least = 1,
    };
};

pub const Scroll = struct {
    vertical: i32 = 0,
    horizontal: i32 = 0,
};

const remote = @This();

comptime {
    assert(binding_count_max > 0);
    assert(chord_keys_max >= 2);
    assert(chord_keys_max <= chord_registry.sequence_max);
    assert(delay_ms_max > 0);
    assert(filter_patterns_max > 0);
    assert(scroll_clicks_max > 0);
    assert(sequence_bytes_max > 0);
    assert(sequence_bytes_max <= sequence_registry.length_max);
    assert(text_bytes_max > 0);
}

pub fn ClientType(comptime Platform: type) type {
    comptime assert(Platform.capabilities.remote);
    comptime assert(scroll_clicks_max <= Platform.scroll_clicks_max);
    comptime assert(text_bytes_max <= Platform.text_bytes_max);

    return struct {
        raw: Platform.RemoteClient = .{},

        const Client = @This();

        pub const BindOptions = remote.BindOptions;
        pub const Binding = enum(u32) { _ };
        pub const Blocked = remote.Blocked;
        pub const ButtonAction = remote.ButtonAction;
        pub const KeyAction = remote.KeyAction;
        pub const Pattern = remote.Pattern;
        pub const Scroll = remote.Scroll;

        pub fn bind(
            client: *Client,
            comptime pattern: []const u8,
            options: remote.BindOptions,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner, ?*const Key) void,
        ) (CapacityError || PlatformError || RequestError)!Binding {
            comptime assert(pattern.len > 0);

            const parsed = comptime pattern_module.parse(pattern);
            return client.bind_key(parsed.key, parsed.modifiers, options, Owner, owner, callback);
        }

        pub fn bind_chord(
            client: *Client,
            keys: []const Keycode,
            options: remote.BindOptions,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner, ?*const Key) void,
        ) (CapacityError || PlatformError || RequestError)!Binding {
            if (keys.len > chord_keys_max) return error.ChordTooLong;
            if (keys.len < 2) return error.ChordInvalid;

            for (keys) |value| {
                if (value == .silent) return error.ChordInvalid;
            }

            const notify = NotifyType(Owner, callback);
            const id = try client.raw.bind_chord(keys, options, notify.invoke, owner);

            assert(id >= 1);

            return @fromBackingInt(id);
        }

        pub fn bind_key(
            client: *Client,
            key: Keycode,
            modifiers: Modifier,
            options: remote.BindOptions,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner, ?*const Key) void,
        ) (CapacityError || PlatformError || RequestError)!Binding {
            assert(modifiers.flags <= modifier.flag_all);

            const notify = NotifyType(Owner, callback);
            const id = try client.raw.bind_key(key, modifiers, options, notify.invoke, owner);

            assert(id >= 1);

            return @fromBackingInt(id);
        }

        pub fn bind_sequence(
            client: *Client,
            text: []const u8,
            options: remote.BindOptions,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner, ?*const Key) void,
        ) (CapacityError || PlatformError || RequestError)!Binding {
            if (text.len > sequence_bytes_max) return error.SequenceTooLong;
            if (text.len == 0) return error.SequenceEmpty;

            for (text) |character| {
                if (!std.ascii.isAlphabetic(character)) return error.CharacterInvalid;
            }

            const notify = NotifyType(Owner, callback);
            const id = try client.raw.bind_sequence(text, options, notify.invoke, owner);

            assert(id >= 1);

            return @fromBackingInt(id);
        }

        pub fn connect(client: *Client) PlatformError!void {
            assert(!client.is_connected());

            try client.raw.connect();

            assert(client.is_connected());
        }

        pub fn disconnect(client: *Client) void {
            client.raw.disconnect();

            assert(!client.is_connected());
        }

        pub fn is_connected(client: *const Client) bool {
            return client.raw.is_connected();
        }

        pub fn set_blocked(
            client: *Client,
            blocked: remote.Blocked,
        ) (PlatformError || RequestError)!void {
            return client.raw.set_blocked(blocked);
        }

        pub fn set_filter(
            client: *Client,
            patterns: []const remote.Pattern,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner, *const Key) Response,
        ) (CapacityError || PlatformError || RequestError)!void {
            if (patterns.len > filter_patterns_max) return error.FilterTooLong;

            const wrapper = struct {
                fn invoke(pointer: *anyopaque, key: *const Key) Response {
                    const typed: *Owner = @ptrCast(@alignCast(pointer));
                    return callback(typed, key);
                }
            };

            return client.raw.set_filter(patterns, wrapper.invoke, owner);
        }

        pub fn set_release_callback(
            client: *Client,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner) void,
        ) void {
            const wrapper = struct {
                fn invoke(pointer: *anyopaque) void {
                    const typed: *Owner = @ptrCast(@alignCast(pointer));

                    callback(typed);
                }
            };

            client.raw.set_release_callback(wrapper.invoke, owner);
        }

        pub fn simulate_button(
            client: *Client,
            button: MouseEvent.Button,
            action: remote.ButtonAction,
        ) (PlatformError || RequestError)!void {
            assert(button.is_valid());

            return client.raw.simulate_button(button, action);
        }

        pub fn simulate_combination(
            client: *Client,
            modifiers: Modifier,
            key: Keycode,
        ) (PlatformError || RequestError)!void {
            assert(modifiers.flags <= modifier.flag_all);

            return client.raw.simulate_combination(modifiers, key);
        }

        pub fn simulate_key(
            client: *Client,
            key: Keycode,
            action: remote.KeyAction,
        ) (PlatformError || RequestError)!void {
            return client.raw.simulate_key(key, action);
        }

        pub fn simulate_move(
            client: *Client,
            offset: Position,
        ) (PlatformError || RequestError)!void {
            return client.raw.simulate_move(offset);
        }

        pub fn simulate_scroll(
            client: *Client,
            scroll: remote.Scroll,
        ) (PlatformError || RequestError)!void {
            if (!scroll_valid(scroll)) return error.ScrollInvalid;
            return client.raw.simulate_scroll(scroll);
        }

        pub fn simulate_text(
            client: *Client,
            text: []const u8,
            delay_ms: u16,
        ) (CapacityError || PlatformError || RequestError)!void {
            if (text.len > text_bytes_max) return error.TextTooLong;
            if (delay_ms > delay_ms_max) return error.DelayInvalid;
            if (!std.unicode.utf8ValidateSlice(text)) return error.TextInvalid;
            return client.raw.simulate_text(text, delay_ms);
        }

        pub fn unbind(client: *Client, handle: Binding) (PlatformError || RequestError)!void {
            assert(@backingInt(handle) >= 1);

            return client.raw.unbind(@backingInt(handle));
        }

        pub fn poll(client: *Client, timeout_ms: u32) void {
            assert(timeout_ms <= std.math.maxInt(i32));

            client.raw.poll(timeout_ms);
        }
    };
}

pub fn scroll_valid(scroll: Scroll) bool {
    if (@abs(scroll.vertical) > scroll_clicks_max) return false;
    if (@abs(scroll.horizontal) > scroll_clicks_max) return false;
    return true;
}

pub fn pattern_matches(pattern: *const Pattern, key: *const Key) bool {
    assert(key.is_valid());

    if (pattern.key) |value| {
        if (value != key.value) return false;
    }

    const required = pattern.modifiers.flags;

    return switch (pattern.modifiers_match) {
        .exact => key.modifiers.flags == required,
        .at_least => key.modifiers.flags & required == required,
    };
}

fn NotifyType(comptime Owner: type, comptime callback: fn (*Owner, ?*const Key) void) type {
    return struct {
        fn invoke(pointer: *anyopaque, key: ?*const Key) void {
            if (key) |value| assert(value.is_valid());

            const typed: *Owner = @ptrCast(@alignCast(pointer));

            callback(typed, key);
        }
    };
}

const testing = std.testing;

const Counter = struct {
    fired: u32 = 0,

    fn on_trigger(counter: *Counter, _: ?*const Key) void {
        counter.fired += 1;
    }
};

test ClientType {
    var client = ClientType(platform.Fake){};
    var counter = Counter{};

    try testing.expect(!client.is_connected());

    const on_trigger = Counter.on_trigger;
    const chord = client.bind_chord(&.{.a}, .{}, Counter, &counter, on_trigger);
    const sequence = client.bind_sequence("a1", .{}, Counter, &counter, on_trigger);
    const pattern = client.bind("Ctrl+Alt+M", .{ .exempt = true }, Counter, &counter, on_trigger);
    const scroll = client.simulate_scroll(.{ .vertical = scroll_clicks_max + 1 });

    try testing.expectError(error.ChordInvalid, chord);
    try testing.expectError(error.CharacterInvalid, sequence);
    try testing.expectError(error.ClientDisconnected, pattern);
    try testing.expectError(error.ScrollInvalid, scroll);
    try testing.expectEqual(@as(u32, 0), counter.fired);
}

test scroll_valid {
    try testing.expect(scroll_valid(.{ .vertical = -3, .horizontal = 2 }));
    try testing.expect(scroll_valid(.{ .vertical = scroll_clicks_max }));
    try testing.expect(!scroll_valid(.{ .horizontal = -@as(i32, scroll_clicks_max + 1) }));
}

test pattern_matches {
    const super = Pattern{
        .key = .super_left,
        .modifiers = .from(.{ .win = true }),
        .modifiers_match = .at_least,
    };

    const alone = Key{ .value = .super_left, .down = true, .modifiers = .from(.{ .win = true }) };

    const chorded = Key{
        .value = .super_left,
        .down = true,
        .modifiers = .from(.{ .win = true, .shift = true }),
    };

    try testing.expect(pattern_matches(&super, &alone));
    try testing.expect(pattern_matches(&super, &chorded));

    const exact = Pattern{ .key = .super_left, .modifiers = .from(.{ .win = true }) };

    try testing.expect(pattern_matches(&exact, &alone));
    try testing.expect(!pattern_matches(&exact, &chorded));
}

test "a pattern without a key matches any key carrying its modifiers" {
    const any = Pattern{
        .modifiers = .from(.{ .ctrl = true }),
        .modifiers_match = .at_least,
    };

    const held = Key{ .value = .q, .down = true, .modifiers = .from(.{ .ctrl = true }) };
    const bare = Key{ .value = .q, .down = true };

    try testing.expect(pattern_matches(&any, &held));
    try testing.expect(!pattern_matches(&any, &bare));
}
