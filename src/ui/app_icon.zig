//! A group's launcher icon, or a plain tile when it has none or can't be drawn.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const apps = @import("zmon-system").apps;
const theme = @import("theme.zig");

const icon_size = 20;

/// The side, in pixels, that nanoui's picture atlas starts at. nanoui starts
/// it at 2048, and on Linux it keeps a copy in memory, zeroed before the first
/// picture: 16 MB. zmon's pictures are launcher icons 40 pixels wide, so 512
/// (1 MB) holds over a hundred; nanoui doubles it if they ever don't fit.
pub const atlas_side = 512;

/// Starts the picture atlas at `atlas_side`. Call it before anything draws
/// a picture; once one has, it changes nothing.
pub fn startSmall(c: *ui.Context) void {
    if (!@hasField(@TypeOf(c.text.*), "images")) return;
    const im = &c.text.images;
    if (im.pixels.len == 0 and im.sink == null and im.entries.count() == 0 and im.side > atlas_side) im.side = atlas_side;
}

/// The group's launcher icon, or a plain tile when it has none or can't be drawn.
pub fn draw(c: *ui.Context, icons: *apps.Icons, k: theme.Colors, g: apps.Group) void {
    if (icons.get(g.icon)) |icon| {
        const drawn = switch (icon.kind) {
            .svg => ui.svg(c, .{ .key = icon.path, .bytes = icon.bytes, .size = icon_size }),
            .png, .jpeg => ui.image(c, .{ .key = icon.path, .bytes = icon.bytes, .box = .{ .w = icon_size, .h = icon_size }, .radius = 4 }),
        };
        if (drawn) return;
    }
    const tile = ui.div(c).row().size(icon_size, icon_size).itemsCenter().justifyCenter().rounded(5).bg(k.separator);
    defer tile.end();
    switch (g.kind) {
        .app => {
            const len = if (g.name.len > 0) std.unicode.utf8ByteSequenceLength(g.name[0]) catch 1 else 0;
            const first = c.print("{s}", .{g.name[0..@min(len, g.name.len)]});
            ui.text(c, first, .{ .size = 11, .weight = .bold, .color = k.secondary });
        },
        .background => ui.icon(c, "gearshape", .{ .size = 11, .frame = icon_size, .color = k.secondary }),
        .kernel => ui.icon(c, "cpu", .{ .size = 11, .frame = icon_size, .color = k.secondary }),
    }
}
