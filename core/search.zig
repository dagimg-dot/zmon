//! Finding processes by what a person types: part of a name or a pid.
const std = @import("std");
const Proc = @import("types.zig").Proc;

/// Whether `text` holds `part`, ignoring ASCII case.
pub fn containsIgnoreCase(text: []const u8, part: []const u8) bool {
    if (part.len > text.len) return false;
    for (0..text.len - part.len + 1) |i| {
        if (std.ascii.eqlIgnoreCase(text[i..][0..part.len], part)) return true;
    }
    return false;
}

/// Whether a process matches a search: part of its name, any case, or the
/// start of its pid. Spaces around the search don't count; an empty search
/// matches everything.
pub fn matches(p: Proc, search: []const u8) bool {
    const query = std.mem.trim(u8, search, " ");
    if (query.len == 0) return true;
    if (containsIgnoreCase(p.name, query)) return true;
    var b: [16]u8 = undefined;
    const pid = std.fmt.bufPrint(&b, "{d}", .{p.pid}) catch return false;
    return std.mem.startsWith(u8, pid, query);
}

test "a search matches part of a name in any case, or the start of a pid" {
    const p: Proc = .{ .pid = 4213, .ppid = 1, .name = "Telegram" };
    try std.testing.expect(matches(p, ""));
    try std.testing.expect(matches(p, "  "));
    try std.testing.expect(matches(p, "gram"));
    try std.testing.expect(matches(p, " TELE "));
    try std.testing.expect(matches(p, "42"));
    try std.testing.expect(!matches(p, "213")); // the middle of a pid is not a pid
    try std.testing.expect(!matches(p, "telegrams"));
}
