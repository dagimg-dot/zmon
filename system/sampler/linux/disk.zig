//! Bytes read and written by the machine's disks, from /proc/diskstats.
const std = @import("std");
const files = @import("../../platform/root.zig").files;

/// Bytes read and written since boot, by every whole disk.
pub fn read(io: std.Io) [2]u64 {
    var buf: [32768]u8 = undefined;
    const text = files.read(io, .cwd(), "/proc/diskstats", &buf) catch return .{ 0, 0 };
    return parseDiskstats(text);
}

/// A whole disk, not a partition or a virtual device: sda, vda, nvme0n1,
/// mmcblk0, but not sda1, nvme0n1p1, loop0, dm-0, zram0.
fn wholeDisk(name: []const u8) bool {
    if (name.len < 3) return false;
    if (std.mem.startsWith(u8, name, "nvme") or std.mem.startsWith(u8, name, "mmcblk"))
        return std.mem.indexOfScalar(u8, name, 'p') == null;
    for ([_][]const u8{ "sd", "vd", "hd", "xvd" }) |pre| {
        if (!std.mem.startsWith(u8, name, pre)) continue;
        for (name[pre.len..]) |ch| if (!std.ascii.isAlphabetic(ch)) return false;
        return true;
    }
    return false;
}

/// Bytes read and written by every whole disk since boot.
pub fn parseDiskstats(text: []const u8) [2]u64 {
    var total: [2]u64 = .{ 0, 0 };
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var f = std.mem.tokenizeAny(u8, line, " \t");
        _ = f.next();
        _ = f.next();
        const dev = f.next() orelse continue;
        if (!wholeDisk(dev)) continue;
        var v: [8]u64 = @splat(0);
        for (&v) |*x| x.* = std.fmt.parseInt(u64, f.next() orelse break, 10) catch 0;
        // reads, merged, sectors read, ms, writes, merged, sectors written
        total[0] += v[2] * 512;
        total[1] += v[6] * 512;
    }
    return total;
}

test "disks: whole devices only" {
    try std.testing.expect(wholeDisk("nvme0n1"));
    try std.testing.expect(wholeDisk("sda"));
    try std.testing.expect(wholeDisk("mmcblk0"));
    try std.testing.expect(!wholeDisk("nvme0n1p2"));
    try std.testing.expect(!wholeDisk("sda1"));
    try std.testing.expect(!wholeDisk("loop3"));
    try std.testing.expect(!wholeDisk("dm-0"));
    const text = "   8  0 sda 10 0 2000 5 20 0 4000 9 0 0 0\n   8  1 sda1 5 0 1000 2 10 0 2000 4 0 0 0\n";
    const d = parseDiskstats(text);
    try std.testing.expectEqual(@as(u64, 2000 * 512), d[0]);
    try std.testing.expectEqual(@as(u64, 4000 * 512), d[1]);
}
