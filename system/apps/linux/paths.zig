//! Where the freedesktop specs put things: launcher entries and icons live
//! under the user's data directory, then each of XDG_DATA_DIRS, then the
//! flatpak and snap exports. Earlier directories win.
const std = @import("std");
const platform_env = @import("../../platform/root.zig").env;

const env = platform_env.get;
pub const home = platform_env.home;

const Dirs = struct {
    list: std.ArrayList([]const u8) = .empty,
    a: std.mem.Allocator,

    fn add(d: *Dirs, parts: []const []const u8) !void {
        const path = try std.fs.path.join(d.a, parts);
        for (d.list.items) |have| if (std.mem.eql(u8, have, path)) return;
        try d.list.append(d.a, path);
    }

    /// Each of XDG_DATA_DIRS (or the usual two) with `sub` below it.
    fn addData(d: *Dirs, sub: []const u8) !void {
        if (env("XDG_DATA_DIRS")) |dirs| {
            var it = std.mem.splitScalar(u8, dirs, ':');
            while (it.next()) |dir| if (dir.len > 0) try d.add(&.{ dir, sub });
        } else {
            for ([_][]const u8{ "/usr/local/share", "/usr/share" }) |dir| try d.add(&.{ dir, sub });
        }
    }
};

fn userData(d: *Dirs, sub: []const u8) !void {
    if (env("XDG_DATA_HOME")) |x| try d.add(&.{ x, sub }) else try d.add(&.{ home(), ".local", "share", sub });
}

/// Directories holding .desktop launcher entries, most specific first.
pub fn applicationDirs(a: std.mem.Allocator) ![]const []const u8 {
    var d: Dirs = .{ .a = a };
    try userData(&d, "applications");
    try d.add(&.{ home(), ".local", "share", "flatpak", "exports", "share", "applications" });
    try d.add(&.{"/var/lib/flatpak/exports/share/applications"});
    try d.add(&.{"/var/lib/snapd/desktop/applications"});
    try d.addData("applications");
    return d.list.items;
}

/// Directories holding icon themes (and loose pixmaps), most specific first.
pub fn iconDirs(a: std.mem.Allocator) ![]const []const u8 {
    var d: Dirs = .{ .a = a };
    try userData(&d, "icons");
    try d.add(&.{ home(), ".icons" });
    try d.add(&.{ home(), ".local", "share", "flatpak", "exports", "share", "icons" });
    try d.add(&.{"/var/lib/flatpak/exports/share/icons"});
    try d.add(&.{"/var/lib/snapd/desktop/icons"});
    try d.addData("icons");
    try d.add(&.{"/usr/share/pixmaps"});
    return d.list.items;
}

test "search directories start with the user's and never repeat" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const apps = try applicationDirs(arena.allocator());
    const icons = try iconDirs(arena.allocator());
    try std.testing.expect(apps.len >= 2 and icons.len >= 2);
    try std.testing.expect(std.mem.endsWith(u8, apps[0], "applications"));
    try std.testing.expect(std.mem.endsWith(u8, icons[icons.len - 1], "pixmaps"));
    for (apps, 0..) |x, i| for (apps[i + 1 ..]) |y| try std.testing.expect(!std.mem.eql(u8, x, y));
}
