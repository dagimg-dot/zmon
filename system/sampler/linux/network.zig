//! Bytes received and sent by the machine's network interfaces, from /proc/net/dev.
const std = @import("std");
const files = @import("../../platform/root.zig").files;

/// Bytes received and sent since boot by the machine's real network interfaces.
pub fn read(io: std.Io) [2]u64 {
    var buf: [65536]u8 = undefined;
    const text = files.readWhole(io, .cwd(), "/proc/net/dev", &buf) catch return .{ 0, 0 };
    return parseNetDev(text, Sysfs{});
}

/// An interface the kernel made up (loopback, bridges, veth pairs, tunnels) has
/// its node under /sys/devices/virtual/net. Its traffic is also counted on the
/// real interface it passes through, so counting both would count it twice.
const Sysfs = struct {
    pub fn isVirtual(_: Sysfs, name: []const u8) bool {
        var path: [128]u8 = undefined;
        const p = std.fmt.bufPrintSentinel(&path, "/sys/devices/virtual/net/{s}", .{name}, 0) catch return false;
        return std.c.access(p.ptr, std.posix.F_OK) == 0;
    }
};

/// Bytes received and sent since boot by every interface `interfaces` doesn't
/// call virtual (`interfaces.isVirtual(name)`).
pub fn parseNetDev(text: []const u8, interfaces: anytype) [2]u64 {
    var total: [2]u64 = .{ 0, 0 };
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const dev = std.mem.trim(u8, line[0..colon], " ");
        if (interfaces.isVirtual(dev)) continue;
        var f = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
        var v: [16]u64 = @splat(0);
        for (&v) |*x| x.* = std.fmt.parseInt(u64, f.next() orelse break, 10) catch 0;
        total[0] += v[0]; // bytes received
        total[1] += v[8]; // bytes sent
    }
    return total;
}

const FakeSysfs = struct {
    pub fn isVirtual(_: FakeSysfs, name: []const u8) bool {
        return std.mem.eql(u8, name, "lo") or std.mem.startsWith(u8, name, "veth") or std.mem.startsWith(u8, name, "docker");
    }
};

test "network: virtual interfaces are left out" {
    const text =
        \\Inter-|   Receive                                                |  Transmit
        \\ face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
        \\    lo: 999 9 0 0 0 0 0 0 999 9 0 0 0 0 0 0
        \\  wlan0: 1000 10 0 0 0 0 0 0 500 5 0 0 0 0 0 0
        \\docker0: 700 7 0 0 0 0 0 0 700 7 0 0 0 0 0 0
        \\veth01: 700 7 0 0 0 0 0 0 700 7 0 0 0 0 0 0
    ;
    const n = parseNetDev(text, FakeSysfs{});
    try std.testing.expectEqual(@as(u64, 1000), n[0]);
    try std.testing.expectEqual(@as(u64, 500), n[1]);
}

test "on this machine, loopback is virtual" {
    try std.testing.expect(Sysfs.isVirtual(.{}, "lo"));
    try std.testing.expect(!Sysfs.isVirtual(.{}, "no-such-interface"));
}
