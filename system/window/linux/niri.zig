//! niri's answer to "Windows": {"Ok":{"Windows":[{"app_id":..,"pid":..},..]}}.
const std = @import("std");
const core = @import("zmon-core");

pub fn parse(a: std.mem.Allocator, reply: []const u8, out: []core.Window) usize {
    const v = std.json.parseFromSliceLeaky(std.json.Value, a, reply, .{}) catch return 0;
    const ok = field(v, "Ok") orelse return 0;
    const windows = field(ok, "Windows") orelse return 0;
    if (windows != .array) return 0;
    var n: usize = 0;
    for (windows.array.items) |w| {
        if (n == out.len) break;
        const pid = field(w, "pid") orelse continue;
        const app_id = field(w, "app_id") orelse continue;
        if (pid != .integer or app_id != .string) continue;
        out[n] = .{ .pid = @intCast(pid.integer), .app_id = .init(app_id.string) };
        n += 1;
    }
    return n;
}

fn field(v: std.json.Value, name: []const u8) ?std.json.Value {
    if (v != .object) return null;
    return v.object.get(name);
}

test "niri's window list gives each window's owner and app id" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var out: [4]core.Window = undefined;
    const n = parse(arena.allocator(),
        \\{"Ok":{"Windows":[{"id":193,"title":"Discord","app_id":"equibop","pid":852806,"workspace_id":26},
        \\{"id":7,"title":"no owner","app_id":"x","pid":null},{"id":8,"app_id":null,"pid":5}]}}
    , &out);
    try std.testing.expectEqual(@as(usize, 1), n);
    try std.testing.expectEqual(@as(i32, 852806), out[0].pid);
    try std.testing.expectEqualStrings("equibop", out[0].app_id.slice());
    try std.testing.expectEqual(@as(usize, 0), parse(arena.allocator(), "{\"Err\":\"no\"}", &out));
    try std.testing.expectEqual(@as(usize, 0), parse(arena.allocator(), "not json", &out));
}
