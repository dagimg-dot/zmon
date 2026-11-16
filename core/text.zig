//! Small parsers for the "key: value" listings the kernel writes.
const std = @import("std");

/// The unsigned number after `key` in a "key: value" listing, or 0.
pub fn field(text: []const u8, key: []const u8) u64 {
    const at = std.mem.indexOf(u8, text, key) orelse return 0;
    var it = std.mem.tokenizeAny(u8, text[at + key.len ..], " \t\n");
    return std.fmt.parseInt(u64, it.next() orelse return 0, 10) catch 0;
}

test "field finds the number after a key" {
    const text = "Name:\tbash\nUid:\t1000\t1000\nVmRSS:\t  2048 kB\n";
    try std.testing.expectEqual(@as(u64, 1000), field(text, "Uid:"));
    try std.testing.expectEqual(@as(u64, 2048), field(text, "VmRSS:"));
    try std.testing.expectEqual(@as(u64, 0), field(text, "Nope:"));
}
