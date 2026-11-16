//! A group's launcher icon, or a plain tile when it has none or can't be drawn.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const apps = @import("zmon-system").apps;
const app = @import("../../app/state.zig");
const theme = @import("../../ui/theme.zig");

const State = app.State;
const icon_size = 20;

/// The group's launcher icon, or a plain tile when it has none or can't be drawn.
pub fn draw(c: *ui.Context, s: *State, k: theme.Colors, g: apps.Group) void {
    if (s.icons.get(g.icon)) |icon| {
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
