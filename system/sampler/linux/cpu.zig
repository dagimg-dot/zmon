//! The processor's busy and total ticks, as a whole and per core, from /proc/stat.
const std = @import("std");
const files = @import("../../platform/root.zig").files;

pub const Times = struct { busy: u64 = 0, total: u64 = 0 };

/// Reads the total (first) and every core into `out`, and returns how many.
pub fn read(io: std.Io, out: []Times) usize {
    var buf: [16384]u8 = undefined;
    const text = files.read(io, .cwd(), "/proc/stat", &buf) catch return 0;
    return parse(text, out);
}

/// Fills `out` from the "cpu" and "cpuN" lines of /proc/stat (the total
/// first) and returns how many.
pub fn parse(text: []const u8, out: []Times) usize {
    var n: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "cpu")) break;
        if (n == out.len) break;
        var f = std.mem.tokenizeScalar(u8, line, ' ');
        _ = f.next();
        var v: [8]u64 = @splat(0);
        for (&v) |*x| x.* = std.fmt.parseInt(u64, f.next() orelse break, 10) catch 0;
        // user nice system idle iowait irq softirq steal
        const idle = v[3] + v[4];
        const total = v[0] + v[1] + v[2] + v[3] + v[4] + v[5] + v[6] + v[7];
        out[n] = .{ .busy = total - idle, .total = total };
        n += 1;
    }
    return n;
}

test "cpu lines: busy is everything but idle and iowait" {
    const text = "cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 60 0 30 400 10 0 0 0 0 0\ncpu1 40 0 20 400 40 0 0 0 0 0\nintr 1\n";
    var out: [8]Times = undefined;
    try std.testing.expectEqual(@as(usize, 3), parse(text, &out));
    try std.testing.expectEqual(@as(u64, 150), out[0].busy);
    try std.testing.expectEqual(@as(u64, 1000), out[0].total);
}
