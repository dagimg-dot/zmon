//! A device in the sidebar: its icon, name and live value, a detail line, and
//! its recent history as a small chart.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const charts = @import("charts.zig");
const theme = @import("theme.zig");

pub const Tile = struct {
    key: []const u8,
    icon: []const u8,
    title: []const u8,
    value: []const u8,
    detail: []const u8,
    history: *const core.Ring(f32),
    /// A second series drawn lighter over the first (writes, uploads).
    second: ?*const core.Ring(f32) = null,
    /// The top of the chart; null scales to the history, never below `floor`.
    max: ?f32 = null,
    floor: f32 = 1,
    /// The graph's colour, and how many samples it spans.
    color: nanoui.ui.Color,
    window: usize = 60,
};

/// Draws the tile; true when it was clicked.
pub fn draw(c: *ui.Context, k: theme.Colors, t: Tile, on: bool) bool {
    ui.key(c, t.key);
    const box = ui.div(c).column().wFull().px(10).py(8).gap(3).rounded(10).control();
    defer box.end();
    if (on) _ = box.bg(k.page).border(k.separator) else _ = box.hover(k.hover);
    const clicked = box.clicked();
    {
        const head = ui.div(c).row().wFull().itemsCenter().gap(8);
        defer head.end();
        ui.icon(c, t.icon, .{ .size = 13, .frame = 16, .color = k.text });
        ui.text(c, t.title, .{ .size = 13, .weight = .semibold, .color = k.text });
        ui.spacer(c);
        ui.text(c, t.value, .{ .size = 12.5, .weight = .semibold, .color = k.text, .tabular = true });
    }
    ui.text(c, t.detail, .{ .size = 11, .color = k.secondary, .truncate = .ellipsis, .tabular = true });
    charts.area(c, t.history, .{
        .height = 28,
        .max = t.max,
        .floor = t.floor,
        .second = t.second,
        .color = if (on) t.color else t.color.mix(k.panel, 0.25),
        .window = t.window,
        .grid = k.separator,
        .grid_lines = 0,
    });
    return clicked;
}
