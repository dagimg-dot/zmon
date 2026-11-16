//! Finds the picture for a launcher entry's Icon= value.
//!
//! An Icon= is a theme name ("org.gnome.Calculator") or an absolute path. A
//! name is looked up the way the icon theme spec lays things out, trying the
//! user's theme first, then hicolor, then every other installed theme, and
//! within a theme the size nanoui draws best. nanoui draws PNG, JPEG and SVG
//! but not XPM, so those are the only kinds considered; a PNG near 64 pixels
//! beats an SVG, which beats a larger or smaller PNG.
//!
//! Bytes are read once and kept, because nanoui draws from the caller's
//! memory. Misses are remembered too, so a name is searched for once.
const std = @import("std");
const procfs = @import("procfs.zig");
const xdg = @import("xdg.zig");

pub const Kind = enum { png, jpeg, svg };

pub const Icon = struct {
    /// Where it came from; unique, so it names the picture to nanoui.
    path: []const u8,
    bytes: []const u8,
    kind: Kind,
};

/// Larger files are skipped: a handful of apps ship multi-megabyte vector art.
pub const max_bytes = 384 * 1024;

const Probe = struct { dir: []const u8, ext: []const u8, score: u16 };

const probes = [_]Probe{
    .{ .dir = "64x64", .ext = "png", .score = 100 },
    .{ .dir = "96x96", .ext = "png", .score = 95 },
    .{ .dir = "48x48", .ext = "png", .score = 90 },
    .{ .dir = "128x128", .ext = "png", .score = 85 },
    .{ .dir = "scalable", .ext = "svg", .score = 70 },
    .{ .dir = "256x256", .ext = "png", .score = 60 },
    .{ .dir = "32x32", .ext = "png", .score = 50 },
    .{ .dir = "512x512", .ext = "png", .score = 40 },
    .{ .dir = "24x24", .ext = "png", .score = 20 },
    .{ .dir = "22x22", .ext = "png", .score = 18 },
    .{ .dir = "16x16", .ext = "png", .score = 10 },
};

pub const Cache = struct {
    io: std.Io,
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    /// Icon theme directories in the order they are tried.
    themes: []const []const u8 = &.{},
    /// Directories of loose icons (pixmaps).
    loose: []const []const u8 = &.{},
    found: std.StringHashMapUnmanaged(?Icon) = .empty,

    pub fn init(gpa: std.mem.Allocator, io: std.Io) Cache {
        var c: Cache = .{ .io = io, .gpa = gpa, .arena = .init(gpa) };
        const a = c.arena.allocator();
        const dirs = xdg.iconDirs(a) catch &.{};
        c.setDirs(dirs, userTheme(io, a));
        return c;
    }

    /// Searches these icon directories, preferring the theme called `preferred`.
    pub fn setDirs(c: *Cache, dirs: []const []const u8, preferred: []const u8) void {
        const a = c.arena.allocator();
        var first: std.ArrayList([]const u8) = .empty;
        var hicolor: std.ArrayList([]const u8) = .empty;
        var rest: std.ArrayList([]const u8) = .empty;
        var loose: std.ArrayList([]const u8) = .empty;
        for (dirs) |base| {
            if (std.mem.endsWith(u8, base, "pixmaps")) {
                loose.append(a, base) catch {};
                continue;
            }
            var dir = std.Io.Dir.cwd().openDir(c.io, base, .{ .iterate = true }) catch continue;
            defer dir.close(c.io);
            var it = dir.iterate();
            while (it.next(c.io) catch null) |e| {
                if (e.kind != .directory and e.kind != .sym_link) continue;
                if (e.name.len == 0 or e.name[0] == '.') continue;
                const path = std.fs.path.join(a, &.{ base, e.name }) catch continue;
                const is_preferred = preferred.len > 0 and std.mem.eql(u8, e.name, preferred);
                const list = if (is_preferred) &first else if (std.mem.eql(u8, e.name, "hicolor")) &hicolor else &rest;
                list.append(a, path) catch {};
            }
        }
        first.appendSlice(a, hicolor.items) catch {};
        first.appendSlice(a, rest.items) catch {};
        c.themes = first.items;
        c.loose = loose.items;
    }

    pub fn deinit(c: *Cache) void {
        c.arena.deinit();
    }

    /// The picture for an Icon= value, or null if none can be drawn.
    pub fn get(c: *Cache, name: []const u8) ?Icon {
        if (name.len == 0) return null;
        if (c.found.get(name)) |hit| return hit;
        const result = c.lookup(name);
        const a = c.arena.allocator();
        if (a.dupe(u8, name)) |key| c.found.put(a, key, result) catch {} else |_| {}
        return result;
    }

    fn lookup(c: *Cache, raw: []const u8) ?Icon {
        if (raw[0] == '/') return c.load(raw);
        const name = stripExt(raw);
        if (c.inThemes(name)) |icon| return icon;
        var lower: [128]u8 = undefined;
        if (name.len <= lower.len) {
            const l = std.ascii.lowerString(&lower, name);
            if (!std.mem.eql(u8, l, name)) if (c.inThemes(l)) |icon| return icon;
        }
        return c.inLoose(name);
    }

    fn inThemes(c: *Cache, name: []const u8) ?Icon {
        var buf: [1024]u8 = undefined;
        for (c.themes) |theme| {
            var best: u16 = 0;
            var best_path: ?[]const u8 = null;
            for (probes) |p| {
                if (p.score <= best) continue;
                // The two layouts themes use: <size>/apps and apps/<size>.
                inline for (.{ "{s}/{s}/apps/{s}.{s}", "{s}/apps/{s}/{s}.{s}" }) |layout| {
                    if (p.score > best) {
                        if (std.fmt.bufPrintSentinel(&buf, layout, .{ theme, p.dir, name, p.ext }, 0)) |path| {
                            if (std.c.access(path.ptr, 4) == 0) {
                                best = p.score;
                                // `path` lives in `buf`, which the next probe overwrites.
                                best_path = c.arena.allocator().dupe(u8, path) catch null;
                            }
                        } else |_| {}
                    }
                }
            }
            if (best_path) |path| if (c.load(path)) |icon| return icon;
        }
        return null;
    }

    fn inLoose(c: *Cache, name: []const u8) ?Icon {
        var buf: [1024]u8 = undefined;
        for (c.loose) |dir| for ([_][]const u8{ "png", "svg" }) |ext| {
            const path = std.fmt.bufPrintSentinel(&buf, "{s}/{s}.{s}", .{ dir, name, ext }, 0) catch continue;
            if (std.c.access(path.ptr, 4) == 0) if (c.load(path)) |icon| return icon;
        };
        return null;
    }

    /// Reads and checks one file; null when it isn't a picture nanoui can draw.
    fn load(c: *Cache, path: []const u8) ?Icon {
        const kind = kindOf(path) orelse return null;
        const buf = c.gpa.alloc(u8, max_bytes + 1) catch return null;
        defer c.gpa.free(buf);
        const bytes = procfs.read(c.io, .cwd(), path, buf) catch return null;
        if (bytes.len == 0 or bytes.len > max_bytes) return null;
        if (!looksLike(kind, bytes)) return null;
        const a = c.arena.allocator();
        return .{ .path = a.dupe(u8, path) catch return null, .bytes = a.dupe(u8, bytes) catch return null, .kind = kind };
    }
};

fn kindOf(path: []const u8) ?Kind {
    if (std.ascii.endsWithIgnoreCase(path, ".png")) return .png;
    if (std.ascii.endsWithIgnoreCase(path, ".svg")) return .svg;
    if (std.ascii.endsWithIgnoreCase(path, ".jpg") or std.ascii.endsWithIgnoreCase(path, ".jpeg")) return .jpeg;
    return null;
}

/// The file's first bytes say what it is; an extension alone can lie.
fn looksLike(kind: Kind, bytes: []const u8) bool {
    return switch (kind) {
        .png => std.mem.startsWith(u8, bytes, "\x89PNG"),
        .jpeg => std.mem.startsWith(u8, bytes, "\xff\xd8"),
        .svg => std.mem.indexOf(u8, bytes[0..@min(bytes.len, 512)], "<") != null,
    };
}

fn stripExt(name: []const u8) []const u8 {
    for ([_][]const u8{ ".png", ".svg", ".xpm", ".jpg" }) |ext| {
        if (std.ascii.endsWithIgnoreCase(name, ext)) return name[0 .. name.len - ext.len];
    }
    return name;
}

/// The icon theme the user chose, from GTK's settings; "" when none is set.
fn userTheme(io: std.Io, a: std.mem.Allocator) []const u8 {
    var buf: [8192]u8 = undefined;
    for ([_][]const u8{ "gtk-3.0", "gtk-4.0" }) |dir| {
        const path = std.fs.path.join(a, &.{ xdg.home(), ".config", dir, "settings.ini" }) catch continue;
        const text = procfs.read(io, .cwd(), path, &buf) catch continue;
        if (themeFromSettings(text)) |t| return a.dupe(u8, t) catch "";
    }
    return "";
}

pub fn themeFromSettings(text: []const u8) ?[]const u8 {
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |line| {
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        if (!std.mem.eql(u8, std.mem.trim(u8, line[0..eq], " \t"), "gtk-icon-theme-name")) continue;
        const v = std.mem.trim(u8, line[eq + 1 ..], " \t\"'");
        return if (v.len > 0) v else null;
    }
    return null;
}

const png_header = "\x89PNG\r\n\x1a\n";

fn write(dir: std.Io.Dir, io: std.Io, path: []const u8, data: []const u8) !void {
    if (std.fs.path.dirname(path)) |d| try dir.createDirPath(io, d);
    try dir.writeFile(io, .{ .sub_path = path, .data = data });
}

test "the GTK setting names the user's icon theme" {
    try std.testing.expectEqualStrings("Papirus-Dark", themeFromSettings("[Settings]\ngtk-theme-name=Adwaita\ngtk-icon-theme-name = Papirus-Dark\n").?);
    try std.testing.expect(themeFromSettings("[Settings]\ngtk-theme-name=Adwaita\n") == null);
}

test "names find the best picture: the user's theme first, a PNG near 64 over the rest" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, io, "icons/hicolor/48x48/apps/tool.png", png_header ++ "hicolor");
    try write(tmp.dir, io, "icons/hicolor/scalable/apps/tool.svg", "<svg/>");
    try write(tmp.dir, io, "icons/Mine/16x16/apps/tool.png", png_header ++ "mine16");
    try write(tmp.dir, io, "icons/Mine/64x64/apps/tool.png", png_header ++ "mine64");
    try write(tmp.dir, io, "icons/Other/64x64/apps/only-other.png", png_header ++ "other");
    try write(tmp.dir, io, "icons/Other/apps/48x48/laid-out-differently.png", png_header ++ "alt");
    try write(tmp.dir, io, "icons/hicolor/scalable/apps/vector-only.svg", "<svg/>");
    try write(tmp.dir, io, "pixmaps/loose.png", png_header ++ "loose");

    var root_buf: [256]u8 = undefined;
    const root = try std.fmt.bufPrint(&root_buf, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var c: Cache = .{ .io = io, .gpa = std.testing.allocator, .arena = .init(std.testing.allocator) };
    defer c.deinit();
    c.setDirs(&.{ try std.fs.path.join(a, &.{ root, "icons" }), try std.fs.path.join(a, &.{ root, "pixmaps" }) }, "Mine");

    const tool = c.get("tool").?;
    try std.testing.expect(std.mem.endsWith(u8, tool.path, "Mine/64x64/apps/tool.png"));
    try std.testing.expect(std.mem.endsWith(u8, tool.bytes, "mine64"));
    try std.testing.expectEqual(Kind.png, tool.kind);
    try std.testing.expect(std.mem.endsWith(u8, c.get("only-other").?.path, "Other/64x64/apps/only-other.png"));
    try std.testing.expect(std.mem.endsWith(u8, c.get("laid-out-differently").?.path, "Other/apps/48x48/laid-out-differently.png"));
    try std.testing.expectEqual(Kind.svg, c.get("vector-only").?.kind);
    try std.testing.expectEqual(Kind.png, c.get("loose").?.kind);
    try std.testing.expectEqual(Kind.png, c.get("TOOL.png").?.kind); // an extension and a different case still find it
    try std.testing.expect(c.get("nothing-by-this-name") == null);
    try std.testing.expect(c.get("") == null);
    try std.testing.expect(c.get("nothing-by-this-name") == null); // remembered
    try std.testing.expectEqual(@as(u32, 7), c.found.count());
}

test "absolute paths and odd files" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try write(tmp.dir, io, "good.png", png_header ++ "x");
    try write(tmp.dir, io, "fake.png", "not a picture");
    try write(tmp.dir, io, "note.txt", "hello");
    var buf: [3][256]u8 = undefined;
    var c: Cache = .{ .io = io, .gpa = std.testing.allocator, .arena = .init(std.testing.allocator) };
    defer c.deinit();
    const good = try std.fmt.bufPrint(&buf[0], ".zig-cache/tmp/{s}/good.png", .{tmp.sub_path});
    try std.testing.expect(c.get(good) == null); // relative to nothing: only "/" paths are paths
    var abs: [1024]u8 = undefined;
    const cwd = std.mem.sliceTo(std.c.getcwd(&abs, abs.len) orelse return error.SkipZigTest, 0);
    const full = try std.fmt.bufPrint(&buf[1], "{s}/{s}", .{ cwd, good });
    try std.testing.expect(c.get(full) != null);
    const fake = try std.fmt.bufPrint(&buf[2], "{s}/.zig-cache/tmp/{s}/fake.png", .{ cwd, tmp.sub_path });
    try std.testing.expect(c.get(fake) == null); // its bytes aren't a PNG
    try std.testing.expect(c.get("/etc/hostname") == null); // not a picture kind
}

test "on this machine, installed apps have icons that resolve" {
    const apps = @import("apps.zig");
    var ix = apps.Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.load(std.testing.io);
    var c = Cache.init(std.testing.allocator, std.testing.io);
    defer c.deinit();
    var named: usize = 0;
    var resolved: usize = 0;
    for (ix.entries.items) |e| {
        if (e.icon.len == 0) continue;
        named += 1;
        if (c.get(e.icon) != null) resolved += 1;
    }
    if (named == 0) return error.SkipZigTest;
    try std.testing.expect(resolved > 0);
}
