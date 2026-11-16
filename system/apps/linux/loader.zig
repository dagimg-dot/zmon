//! Reads launcher entries from the standard application directories.
const std = @import("std");
const files = @import("../../platform/root.zig").files;
const paths = @import("paths.zig");
const Index = @import("index.zig").Index;

/// Reads every .desktop file in the standard application directories. A
/// name an earlier (more specific) directory already claimed is kept.
pub fn loadEntries(ix: *Index, io: std.Io) void {
    const dirs = paths.applicationDirs(ix.arena.allocator()) catch return;
    for (dirs) |d| loadDir(ix, io, d);
}

fn loadDir(ix: *Index, io: std.Io, path: []const u8) void {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return;
    defer dir.close(io);
    var it = dir.iterate();
    var buf: [32768]u8 = undefined;
    while (it.next(io) catch null) |e| {
        if (!std.mem.endsWith(u8, e.name, ".desktop")) continue;
        const text = files.read(io, dir, e.name, &buf) catch continue;
        ix.add(e.name[0 .. e.name.len - ".desktop".len], text);
    }
}
