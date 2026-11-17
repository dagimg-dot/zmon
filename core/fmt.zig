//! Numbers as people read them.
const std = @import("std");

/// A copy of `text` in `a` (the frame's memory, for text the view draws after
/// the function that formatted it has returned).
pub fn own(a: std.mem.Allocator, text: []const u8) []const u8 {
    return a.dupe(u8, text) catch "";
}

/// "812 B", "1.4 MB", "12 GB": binary multiples, one decimal under 10.
pub fn bytes(buf: []u8, n: u64) []const u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var v: f64 = @floatFromInt(n);
    var i: usize = 0;
    // Decide on the value as it will print: 1023.7 KB prints as 1024, so it is 1.0 MB.
    while (@round(v) >= 1024 and i + 1 < units.len) : (i += 1) v /= 1024;
    if (i == 0) return std.fmt.bufPrint(buf, "{d} B", .{n}) catch "";
    if (v < 9.95) return std.fmt.bufPrint(buf, "{d:.1} {s}", .{ v, units[i] }) catch "";
    return std.fmt.bufPrint(buf, "{d:.0} {s}", .{ v, units[i] }) catch "";
}

/// "0 B/s", "1.4 MB/s".
pub fn rate(buf: []u8, bps: f32) []const u8 {
    var tmp: [24]u8 = undefined;
    const b = bytes(&tmp, @intFromFloat(@max(0, bps)));
    return std.fmt.bufPrint(buf, "{s}/s", .{b}) catch "";
}

/// "3.2%", "0%": whole numbers from 10 up.
pub fn percent(buf: []u8, v: f32) []const u8 {
    if (v < 0.05) return "0%";
    // 9.97 prints as 10 with one decimal: from 9.95 on it is a whole number.
    if (v < 9.95) return std.fmt.bufPrint(buf, "{d:.1}%", .{v}) catch "";
    return std.fmt.bufPrint(buf, "{d:.0}%", .{v}) catch "";
}

/// "3d 4h", "2h 15m", "7m 12s".
pub fn duration(buf: []u8, seconds: f64) []const u8 {
    const s: u64 = @intFromFloat(@max(0, seconds));
    const d = s / 86400;
    const h = (s / 3600) % 24;
    const m = (s / 60) % 60;
    if (d > 0) return std.fmt.bufPrint(buf, "{d}d {d}h", .{ d, h }) catch "";
    if (h > 0) return std.fmt.bufPrint(buf, "{d}h {d}m", .{ h, m }) catch "";
    return std.fmt.bufPrint(buf, "{d}m {d}s", .{ m, s % 60 }) catch "";
}

test "bytes, rates, percents and durations" {
    var b: [32]u8 = undefined;
    try std.testing.expectEqualStrings("812 B", bytes(&b, 812));
    try std.testing.expectEqualStrings("1.5 KB", bytes(&b, 1536));
    try std.testing.expectEqualStrings("12 MB", bytes(&b, 12 * 1024 * 1024 + 5));
    try std.testing.expectEqualStrings("0 B/s", rate(&b, 0));
    try std.testing.expectEqualStrings("2.0 MB/s", rate(&b, 2 * 1024 * 1024));
    try std.testing.expectEqualStrings("0%", percent(&b, 0));
    try std.testing.expectEqualStrings("3.2%", percent(&b, 3.24));
    try std.testing.expectEqualStrings("47%", percent(&b, 47.2));
    try std.testing.expectEqualStrings("10%", percent(&b, 9.97));
    try std.testing.expectEqualStrings("9.9%", percent(&b, 9.94));
    try std.testing.expectEqualStrings("1.0 MB", bytes(&b, 1023 * 1024 + 900));
    try std.testing.expectEqualStrings("10 KB", bytes(&b, 10 * 1024 - 20));
    try std.testing.expectEqualStrings("3d 4h", duration(&b, 3 * 86400 + 4 * 3600 + 5));
    try std.testing.expectEqualStrings("7m 12s", duration(&b, 432));
}
