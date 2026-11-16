//! Small parsers for the "key: value" listings the kernel writes.
const std = @import("std");

/// The unsigned number after `key` in a "key: value" listing, or 0. The key
/// must start a line, so a process named "Uid: 0" can't pose as its owner, and
/// "Cached:" never matches "SwapCached:".
pub fn field(text: []const u8, key: []const u8) u64 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, key)) continue;
        var it = std.mem.tokenizeAny(u8, line[key.len..], " \t");
        return std.fmt.parseInt(u64, it.next() orelse return 0, 10) catch 0;
    }
    return 0;
}

test "field finds the number after a key" {
    const text = "Name:\tbash\nUid:\t1000\t1000\nVmRSS:\t  2048 kB\n";
    try std.testing.expectEqual(@as(u64, 1000), field(text, "Uid:"));
    try std.testing.expectEqual(@as(u64, 2048), field(text, "VmRSS:"));
    try std.testing.expectEqual(@as(u64, 0), field(text, "Nope:"));
}

test "a key only counts at the start of a line" {
    try std.testing.expectEqual(@as(u64, 1000), field("Name:\tUid: 0\nUid:\t1000\t1000\n", "Uid:"));
    try std.testing.expectEqual(@as(u64, 300), field("SwapCached:  7 kB\nCached:  300 kB\n", "Cached:"));
}
