//! Hyprland's "j/clients": an array of windows, each with its pid and class.
const std = @import("std");
const core = @import("zmon-core");

pub fn parse(a: std.mem.Allocator, reply: []const u8, out: []core.Window) usize {
    const v = std.json.parseFromSliceLeaky(std.json.Value, a, reply, .{}) catch return 0;
    if (v != .array) return 0;
    var n: usize = 0;
    for (v.array.items) |w| {
        if (n == out.len) break;
        if (w != .object) continue;
        const pid = w.object.get("pid") orelse continue;
        const class = w.object.get("class") orelse continue;
        if (pid != .integer or class != .string or pid.integer <= 0) continue;
        out[n] = .{ .pid = @intCast(pid.integer), .app_id = .init(class.string) };
        n += 1;
    }
    return n;
}

test "Hyprland's clients give each window's owner and class" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var out: [4]core.Window = undefined;
    const n = parse(arena.allocator(), "[{\"pid\":42,\"class\":\"obsidian\",\"title\":\"Notes\"},{\"pid\":-1,\"class\":\"x\"}]", &out);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqualStrings("obsidian", out[0].app_id.slice());
}
