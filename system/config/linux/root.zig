//! Settings in $XDG_CONFIG_HOME/zmon/settings.toml and themes in
//! $XDG_DATA_HOME/zmon/themes, as the XDG base directory spec places them.
const std = @import("std");
const core = @import("zmon-core");
const platform = @import("../../platform/root.zig");
const config = @import("../root.zig");

const files = platform.files;
const env = platform.env;
const settings_file = "settings.toml";

pub fn location(a: std.mem.Allocator) ?config.Location {
    const dir = if (env.get("XDG_CONFIG_HOME")) |x|
        std.fs.path.join(a, &.{ x, "zmon" }) catch return null
    else
        std.fs.path.join(a, &.{ env.home(), ".config", "zmon" }) catch return null;
    const themes = if (env.get("XDG_DATA_HOME")) |x|
        std.fs.path.join(a, &.{ x, "zmon", "themes" }) catch return null
    else
        std.fs.path.join(a, &.{ env.home(), ".local", "share", "zmon", "themes" }) catch return null;
    return .{ .dir = dir, .themes = themes };
}

pub fn loadSettings(io: std.Io, scratch: std.mem.Allocator, at: config.Location) core.settings.Settings {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ at.dir, settings_file }) catch return .{};
    var buf: [16384]u8 = undefined;
    const text = files.readWhole(io, .cwd(), path, &buf) catch return .{};
    return core.settings.Settings.parse(scratch, text);
}

pub fn saveSettings(io: std.Io, at: config.Location, s: *const core.settings.Settings) !void {
    var buf: [4096]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try s.write(&w);
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(io, at.dir);
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    var link_buf: [std.fs.max_path_bytes]u8 = undefined;
    var target_buf: [std.fs.max_path_bytes]u8 = undefined;
    var tmp_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ at.dir, settings_file });
    // A settings file linked from elsewhere (a dotfiles folder) is written
    // where it lives, so the link stays a link.
    const final = if (cwd.readLink(io, path, &link_buf)) |n| blk: {
        const link = link_buf[0..n];
        break :blk if (std.fs.path.isAbsolute(link)) link else try std.fmt.bufPrint(&target_buf, "{s}/{s}", .{ at.dir, link });
    } else |_| path;
    const tmp = try std.fmt.bufPrint(&tmp_buf, "{s}.new", .{final});
    try cwd.writeFile(io, .{ .sub_path = tmp, .data = w.buffered() });
    try std.Io.Dir.rename(cwd, tmp, cwd, final, io);
}

pub fn makeThemesFolder(io: std.Io, at: config.Location) bool {
    std.Io.Dir.cwd().createDirPath(io, at.themes) catch return false;
    return true;
}

pub fn userThemes(io: std.Io, a: std.mem.Allocator, at: config.Location) []config.UserTheme {
    var list: std.ArrayList(config.UserTheme) = .empty;
    var dir = std.Io.Dir.cwd().openDir(io, at.themes, .{ .iterate = true }) catch return &.{};
    defer dir.close(io);
    var it = dir.iterate();
    var buf: [65536]u8 = undefined;
    while (it.next(io) catch null) |e| {
        const id = std.mem.cutSuffix(u8, e.name, ".toml") orelse continue;
        if (!core.settings.validId(id)) continue;
        const text = files.readWhole(io, dir, e.name, &buf) catch continue;
        const theme: config.UserTheme = .{
            .id = a.dupe(u8, id) catch break,
            .text = a.dupe(u8, text) catch break,
        };
        list.append(a, theme) catch break;
    }
    return list.items;
}

fn tmpLocation(a: std.mem.Allocator, tmp: *std.testing.TmpDir) !config.Location {
    const root = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    return .{
        .dir = try std.fs.path.join(a, &.{ root, "config", "zmon" }),
        .themes = try std.fs.path.join(a, &.{ root, "themes" }),
    };
}

test "settings saved are the settings loaded, and nothing saved means the defaults" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const at = try tmpLocation(a, &tmp);
    const before = loadSettings(io, a, at);
    try std.testing.expectEqualStrings("graphite-dark", before.dark_theme.slice());
    var s: core.settings.Settings = .{ .appearance = .light, .light_theme = .init("nord-light") };
    try saveSettings(io, at, &s);
    s.appearance = .dark;
    try saveSettings(io, at, &s); // a second save replaces the first
    const after = loadSettings(io, a, at);
    try std.testing.expectEqual(core.settings.Appearance.dark, after.appearance);
    try std.testing.expectEqualStrings("nord-light", after.light_theme.slice());
}

test "a linked settings file is saved through the link, which stays a link" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const at = try tmpLocation(a, &tmp);
    try tmp.dir.createDirPath(io, "dotfiles");
    try tmp.dir.writeFile(io, .{ .sub_path = "dotfiles/zmon.toml", .data = "" });
    try tmp.dir.createDirPath(io, "config/zmon");
    try tmp.dir.symLink(io, "../../dotfiles/zmon.toml", "config/zmon/" ++ settings_file, .{});
    var s: core.settings.Settings = .{ .appearance = .dark };
    try saveSettings(io, at, &s);
    var buf: [256]u8 = undefined;
    _ = try tmp.dir.readLink(io, "config/zmon/" ++ settings_file, &buf);
    const saved = try tmp.dir.readFileAlloc(io, "dotfiles/zmon.toml", a, .limited(4096));
    try std.testing.expect(std.mem.indexOf(u8, saved, "mode = \"dark\"") != null);
    try std.testing.expectEqual(core.settings.Appearance.dark, loadSettings(io, a, at).appearance);
}

test "user themes are the folder's .toml files with sound names" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const at = try tmpLocation(a, &tmp);
    try std.testing.expectEqual(@as(usize, 0), userThemes(io, a, at).len); // no folder yet
    try tmp.dir.createDirPath(io, "themes");
    try tmp.dir.writeFile(io, .{ .sub_path = "themes/my-theme.toml", .data = "[meta]\nname = \"Mine\"\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "themes/notes.txt", .data = "not a theme" });
    try tmp.dir.writeFile(io, .{ .sub_path = "themes/bad name!.toml", .data = "[meta]\n" });
    const found = userThemes(io, a, at);
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqualStrings("my-theme", found[0].id);
    try std.testing.expect(std.mem.startsWith(u8, found[0].text, "[meta]"));
}
