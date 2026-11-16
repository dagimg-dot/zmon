//! The theme gallery: a card for each theme of one kind (dark or light), each
//! a small window drawn in that theme's own colours. Only the kind shown is
//! built, from plain boxes, so the gallery stays cheap however often it redraws.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const app = @import("../../app/state.zig");
const theme = @import("../../ui/theme.zig");

const State = app.State;
const Theme = core.themes.Theme;
const per_row = 4;

pub fn view(c: *ui.Context, s: *State, k: theme.Colors, dark: bool) void {
    var shown: [128]u16 = undefined;
    var n: usize = 0;
    for (s.themes.themes.items, 0..) |t, i| {
        if (t.dark != dark or n == shown.len) continue;
        shown[n] = @intCast(i);
        n += 1;
    }
    // Graphite first, then by name, so a family's themes sit together.
    const items = s.themes.themes.items;
    std.mem.sort(u16, shown[0..n], items, struct {
        fn less(all: []const Theme, x: u16, y: u16) bool {
            const gx = std.mem.startsWith(u8, all[x].id, "graphite-");
            const gy = std.mem.startsWith(u8, all[y].id, "graphite-");
            if (gx != gy) return gx;
            return std.ascii.lessThanIgnoreCase(all[x].name, all[y].name);
        }
    }.less);
    const chosen = s.theme(dark);
    const grid = ui.div(c).column().wFull().gap(12);
    defer grid.end();
    var start: usize = 0;
    while (start < n) : (start += per_row) {
        ui.key(c, c.print("row-{d}", .{start}));
        const row = ui.div(c).row().wFull().gap(12);
        defer row.end();
        for (start..start + per_row) |j| {
            if (j < n) {
                const t = &s.themes.themes.items[shown[j]];
                card(c, s, k, t, t == chosen, dark);
            } else {
                // Keeps the last row's cards as wide as the others.
                ui.key(c, c.print("empty-{d}", .{j}));
                const gap = ui.div(c).grow().w(0);
                gap.end();
            }
        }
    }
}

fn card(c: *ui.Context, s: *State, k: theme.Colors, t: *const Theme, chosen: bool, dark: bool) void {
    ui.key(c, t.id);
    const box = ui.div(c).column().grow().w(0).p(6).gap(7).rounded(13).control();
    defer box.end();
    if (chosen) _ = box.border(k.accent).borderW(2) else _ = box.border(k.separator).hover(k.hover);
    if (box.clicked() and !chosen) {
        s.chooseTheme(dark, t.id);
        c.changed = true;
    }
    preview(c, t);
    const label = ui.div(c).row().wFull().px(4).pb(2).itemsCenter().gap(6);
    defer label.end();
    ui.text(c, t.name, .{ .size = 12.5, .weight = if (chosen) .semibold else .regular, .color = k.text, .truncate = .ellipsis });
    ui.spacer(c);
    if (chosen) ui.icon(c, "checkmark.circle.fill", .{ .size = 13, .frame = 16, .color = k.accent });
}

/// A small window in the theme's colours: a sidebar, a title, a selected row,
/// a line of text and a little bar chart in its accents.
fn preview(c: *ui.Context, t: *const Theme) void {
    const col = theme.color;
    const bg = col(t.color(.background));
    const box = ui.div(c).row().wFull().h(88).rounded(9).clip().bg(bg).border(col(t.color(.hairline)));
    defer box.end();
    {
        const side = ui.div(c).column().w(34).hFull().bg(col(t.color(.panel))).p(6).gap(5);
        defer side.end();
        bar(c, .fill, 5, col(t.color(.accent)));
        bar(c, .fill, 4, col(t.color(.muted)).alpha(0.6));
        bar(c, .fill, 4, col(t.color(.muted)).alpha(0.6));
    }
    const main = ui.div(c).column().grow().w(0).p(8).gap(6);
    defer main.end();
    bar(c, .{ .px = 48 }, 6, col(t.color(.foreground)));
    {
        const sel = ui.div(c).row().wFull().h(13).rounded(3).px(4).itemsCenter().bg(col(t.color(.selection_bg)));
        defer sel.end();
        bar(c, .{ .px = 34 }, 3, col(t.color(.selection_fg)));
    }
    bar(c, .{ .px = 56 }, 3, col(t.color(.muted)));
    const chart = ui.div(c).row().wFull().grow().itemsEnd().gap(3);
    defer chart.end();
    const heights = [_]f32{ 5, 9, 7, 13, 8, 15, 11, 17 };
    for (heights, 0..) |h, i| {
        const accent = core.themes.theme.accents[i % core.themes.theme.accents.len];
        bar(c, .{ .px = 5 }, h, col(t.color(accent)));
    }
}

fn bar(c: *ui.Context, width: ui.Length, height: f32, color: ui.Color) void {
    _ = c.leaf(.{ .width = width, .height = .{ .px = height }, .background = color, .radius = @min(2, height / 2) }, .none, null);
}

/// The chosen theme's name, description and eight accent colours.
pub fn details(c: *ui.Context, k: theme.Colors, t: *const Theme) void {
    const r = ui.div(c).row().wFull().px(4).pt(4).itemsCenter().gap(12);
    defer r.end();
    {
        const words = ui.div(c).column().grow().w(0).gap(2);
        defer words.end();
        ui.text(c, t.name, .{ .size = 13, .weight = .semibold, .color = k.text });
        if (t.description.len > 0) ui.text(c, t.description, .{ .size = 12, .color = k.secondary, .wrap = true });
    }
    const dots = ui.div(c).row().gap(5).itemsCenter();
    defer dots.end();
    for (core.themes.theme.accents) |tok| {
        _ = c.leaf(.{ .width = .{ .px = 14 }, .height = .{ .px = 14 }, .radius = 7, .background = theme.color(t.color(tok)) }, .none, null);
    }
}
