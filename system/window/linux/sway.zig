//! sway's GET_TREE, over i3's IPC: every node with a pid is a window; its
//! app id is the Wayland app_id, or for X11 windows their class.
const std = @import("std");
const core = @import("zmon-core");

/// "i3-ipc", an empty payload's length, and GET_TREE (4).
pub const get_tree = "i3-ipc".* ++ [_]u8{ 0, 0, 0, 0, 4, 0, 0, 0 };

pub fn parse(a: std.mem.Allocator, reply: []const u8, out: []core.Window) usize {
    if (reply.len < 14) return 0;
    const v = std.json.parseFromSliceLeaky(std.json.Value, a, reply[14..], .{}) catch return 0;
    var n: usize = 0;
    walk(v, out, &n, 0);
    return n;
}

fn walk(v: std.json.Value, out: []core.Window, n: *usize, depth: u8) void {
    if (v != .object or depth > 64 or n.* == out.len) return;
    const o = v.object;
    if (o.get("pid")) |pid| if (pid == .integer) {
        const id: ?[]const u8 = blk: {
            if (o.get("app_id")) |x| if (x == .string) break :blk x.string;
            if (o.get("window_properties")) |wp| if (wp == .object) if (wp.object.get("class")) |c| if (c == .string) break :blk c.string;
            break :blk null;
        };
        if (id) |s| {
            out[n.*] = .{ .pid = @intCast(pid.integer), .app_id = .init(s) };
            n.* += 1;
        }
    };
    for ([_][]const u8{ "nodes", "floating_nodes" }) |k| {
        if (o.get(k)) |kids| if (kids == .array) for (kids.array.items) |kid| walk(kid, out, n, depth + 1);
    }
}

test "sway's tree gives Wayland and X11 windows with their owners" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const json =
        \\{"nodes":[{"nodes":[{"pid":10,"app_id":"foot","nodes":[]},
        \\{"pid":11,"app_id":null,"window_properties":{"class":"Steam"},"nodes":[]}],
        \\"floating_nodes":[{"pid":12,"app_id":"pavucontrol","nodes":[]}]}]}
    ;
    const reply = get_tree ++ json;
    var out: [4]core.Window = undefined;
    const n = parse(arena.allocator(), reply, &out);
    try std.testing.expectEqual(@as(usize, 3), n);
    try std.testing.expectEqualStrings("foot", out[0].app_id.slice());
    try std.testing.expectEqualStrings("Steam", out[1].app_id.slice());
    try std.testing.expectEqual(@as(i32, 12), out[2].pid);
}
