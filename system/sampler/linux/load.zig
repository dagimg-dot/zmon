//! Load averages and uptime, from /proc/loadavg and /proc/uptime.
const std = @import("std");
const files = @import("../../platform/root.zig").files;

pub const Load = struct {
    avg: [3]f32 = .{ 0, 0, 0 },
    uptime: f64 = 0,
    /// Every thread on the machine, kernel threads included (loadavg's "1/1234").
    threads: u32 = 0,
};

pub fn read(io: std.Io) Load {
    var buf: [256]u8 = undefined;
    var l: Load = .{};
    if (files.read(io, .cwd(), "/proc/loadavg", &buf)) |text| {
        parseLoad(text, &l.avg);
        l.threads = parseThreads(text);
    } else |_| {}
    if (files.read(io, .cwd(), "/proc/uptime", &buf)) |text| l.uptime = parseUptime(text) else |_| {}
    return l;
}

fn parseLoad(text: []const u8, out: *[3]f32) void {
    var f = std.mem.tokenizeScalar(u8, text, ' ');
    for (out) |*v| v.* = std.fmt.parseFloat(f32, f.next() orelse "0") catch 0;
}

fn parseThreads(text: []const u8) u32 {
    var f = std.mem.tokenizeScalar(u8, text, ' ');
    for (0..3) |_| _ = f.next();
    const tasks = f.next() orelse return 0;
    const slash = std.mem.indexOfScalar(u8, tasks, '/') orelse return 0;
    return std.fmt.parseInt(u32, tasks[slash + 1 ..], 10) catch 0;
}

fn parseUptime(text: []const u8) f64 {
    var f = std.mem.tokenizeScalar(u8, text, ' ');
    return std.fmt.parseFloat(f64, f.next() orelse "0") catch 0;
}

test "load averages and uptime parse" {
    var avg: [3]f32 = undefined;
    parseLoad("0.52 0.58 0.59 1/123 4567\n", &avg);
    try std.testing.expectApproxEqAbs(@as(f32, 0.58), avg[1], 0.001);
    try std.testing.expectEqual(@as(u32, 123), parseThreads("0.52 0.58 0.59 1/123 4567\n"));
    try std.testing.expectEqual(@as(u32, 0), parseThreads("garbage"));
    try std.testing.expectApproxEqAbs(@as(f64, 351735.47), parseUptime("351735.47 1234.5\n"), 0.001);
}
