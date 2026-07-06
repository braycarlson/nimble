const std = @import("std");
const input = @import("input");

const text = input.simulate.text;

const testing = std.testing;

test "text.send empty returns zero" {
    const sent = try text.send("");

    try testing.expectEqual(@as(u32, 0), sent);
}

test "text.send rejects oversize text" {
    var buffer: [text.text_max + 1]u8 = undefined;

    @memset(&buffer, 'a');

    try testing.expectError(text.Error.TextTooLong, text.send(&buffer));
}

test "text.send rejects invalid utf8" {
    const bad = [_]u8{ 0xC0, 0x20 };

    try testing.expectError(text.Error.InvalidText, text.send(&bad));
}

test "text.send_with_delay rejects oversize delay" {
    const delay_ms = text.delay_ms_max + 1;

    try testing.expectError(text.Error.InvalidDelay, text.send_with_delay("a", delay_ms));
}

test "text.Typer validation" {
    const typer = text.Typer.init();
    const delay_ms = text.delay_ms_max + 1;

    try testing.expectError(text.Error.InvalidDelay, typer.send_with_delay("a", delay_ms));

    const sent = try typer.send("");

    try testing.expectEqual(@as(u32, 0), sent);
}

test "text limits" {
    try testing.expect(text.text_max >= 1);
    try testing.expect(text.delay_ms_max >= 1);
}

test {
    testing.refAllDecls(text);
    testing.refAllDecls(text.Typer);
}
