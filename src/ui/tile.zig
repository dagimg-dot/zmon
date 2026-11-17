//! A device in the sidebar: its icon, name and live value, a detail line, and
//! its recent history as a small chart.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const charts = @import("charts.zig");
const theme = @import("theme.zig");
const controls = @import("controls.zig");
const shortcut_mod = @import("shortcut.zig");

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
    /// The shortcut that opens its page, shown when it is hovered.
    shortcut: ?shortcut_mod.Shortcut = null,
    /// A battery's charge (0 to 100) and whether it is charging: drawn as a
    /// battery in place of `icon`, which nanoui doesn't have.
    battery: ?struct { percent: f32, charging: bool } = null,
    /// The graph's colour, and how many samples it spans.
    color: nanoui.ui.Color,
    window: usize = 60,
};

/// A battery `frame` points wide, filled to `percent`: in the accent while
/// charging, in the danger colour when nearly empty.
pub fn batteryIcon(c: *ui.Context, k: theme.Colors, percent: f32, charging: bool, ink: ui.Color, frame: f32) void {
    const body_w = frame * 0.8;
    const body_h = frame * 0.5;
    const r = ui.div(c).row().w(frame).h(frame).itemsCenter().justifyCenter().gap(1);
    defer r.end();
    ui.access.hide(c, r.index);
    const body = ui.div(c).row().w(body_w).h(body_h).p(1.5).rounded(2.5).border(ink).borderW(1.2);
    {
        defer body.end();
        const fill = @max(0, @min(1, percent / 100));
        const color = if (charging) k.accent else if (percent <= 15) k.danger else ink;
        _ = c.leaf(.{ .width = .{ .px = (body_w - 5.4) * fill }, .height = .fill, .background = color, .radius = 1 }, .none, null);
    }
    _ = c.leaf(.{ .width = .{ .px = 1.5 }, .height = .{ .px = body_h * 0.45 }, .background = ink, .radius = 0.75 }, .none, null);
}

/// Draws the tile; says whether it was pressed, and its box's id (for focus).
pub fn draw(c: *ui.Context, k: theme.Colors, t: Tile, on: bool) struct { pressed: bool, id: u64 } {
    ui.key(c, t.key);
    var box = ui.div(c).column().wFull().px(10).py(8).gap(3).rounded(10).control();
    if (t.shortcut) |s| box = shortcut_mod.tooltip(c, box, k, t.title, s);
    defer box.end();
    if (on) _ = box.bg(k.page).border(k.separator) else _ = box.hover(k.hover);
    const clicked = controls.press(c, box, .{ .role = .tab, .label = c.print("{s}, {s}, {s}", .{ t.title, t.value, t.detail }), .selected = on });
    {
        const head = ui.div(c).row().wFull().itemsCenter().gap(8);
        defer head.end();
        if (t.battery) |b| batteryIcon(c, k, b.percent, b.charging, k.text, 16) else ui.icon(c, t.icon, .{ .size = 13, .frame = 16, .color = k.text });
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
    return .{ .pressed = clicked, .id = c.interact(box.index, .{}).id };
}
