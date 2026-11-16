//! Bytes received and sent by the machine's network interfaces, from /proc/net/dev.
const std = @import("std");
const files = @import("../../platform/root.zig").files;

/// Bytes received and sent since boot, by every interface but loopback.
pub fn read(io: std.Io) [2]u64 {
    var buf: [8192]u8 = undefined;
    const text = files.read(io, .cwd(), "/proc/net/dev", &buf) catch return .{ 0, 0 };
    return parseNetDev(text);
}

/// Bytes received and sent by every interface but loopback since boot.
pub fn parseNetDev(text: []const u8) [2]u64 {
    var total: [2]u64 = .{ 0, 0 };
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const dev = std.mem.trim(u8, line[0..colon], " ");
        if (std.mem.eql(u8, dev, "lo")) continue;
        var f = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
        var v: [16]u64 = @splat(0);
        for (&v) |*x| x.* = std.fmt.parseInt(u64, f.next() orelse break, 10) catch 0;
        total[0] += v[0]; // bytes received
        total[1] += v[8]; // bytes sent
    }
    return total;
}

test "network: loopback is left out" {
    const text =
        \\Inter-|   Receive                                                |  Transmit
        \\ face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
        \\    lo: 999 9 0 0 0 0 0 0 999 9 0 0 0 0 0 0
        \\  wlan0: 1000 10 0 0 0 0 0 0 500 5 0 0 0 0 0 0
    ;
    const n = parseNetDev(text);
    try std.testing.expectEqual(@as(u64, 1000), n[0]);
    try std.testing.expectEqual(@as(u64, 500), n[1]);
}
