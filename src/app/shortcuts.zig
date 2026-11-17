//! The keyboard shortcuts overlay (Ctrl+? or F1), as GNOME apps show theirs:
//! what each key does, grouped, with the keys drawn as keycaps.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("state.zig");
const theme = @import("../ui/theme.zig");
const dialog = @import("../ui/dialog.zig");
const shortcut = @import("../ui/shortcut.zig");

const Item = shortcut.Shortcut;
const Group = struct { title: []const u8, items: []const Item };

/// Every shortcut zmon has; `keys.zig` handles them and README lists them.
/// The ones a control has come from `ui/shortcut.zig`, as its tooltip shows them.
pub const groups = [_]Group{
    .{ .title = "General", .items = &.{ shortcut.search, shortcut.settings, shortcut.help, shortcut.pause, shortcut.sidebar, shortcut.quit } },
    .{ .title = "Pages", .items = &.{
        shortcut.apps,
        shortcut.processes,
        .{ .what = "CPU, Memory, Disk, Network", .keys = &.{ "Ctrl", "3 to 6" } },
        shortcut.next_page,
        shortcut.previous_page,
    } },
    .{ .title = "Lists", .items = &.{
        .{ .what = "Select the row above or below", .keys = &.{ "↑", "↓" } },
        .{ .what = "First or last row", .keys = &.{ "Home", "End" } },
        .{ .what = "Show an app's processes", .keys = &.{"→"} },
        .{ .what = "Hide them, or go back to the app", .keys = &.{"←"} },
        shortcut.details,
        shortcut.end_task,
        shortcut.force_quit,
        .{ .what = "Go back where you came from", .keys = &.{"Esc"} },
        .{ .what = "Start a search", .keys = &.{"Type"} },
    } },
    .{ .title = "Everywhere", .items = &.{
        .{ .what = "Move between controls", .keys = &.{"Tab"}, .alt = &.{ "Shift", "Tab" } },
        .{ .what = "Open a page and go into it", .keys = &.{"Return"} },
        .{ .what = "Press the focused control", .keys = &.{"Space"} },
    } },
};

pub fn overlay(c: *ui.Context, s: *app.State, k: theme.Colors) void {
    const dlg = dialog.begin(c, k, "shortcuts", &s.shortcuts_open, .{
        .title = "Keyboard shortcuts",
        .width = 680,
    }) orelse return;
    {
        const cols = ui.div(c).row().wFull().gap(28).pt(4);
        defer cols.end();
        for ([_][]const Group{ groups[0..2], groups[2..] }, 0..) |half, h| {
            ui.key(c, if (h == 0) "left" else "right");
            const col = ui.div(c).column().grow().w(0).gap(16);
            defer col.end();
            for (half) |g| group(c, k, g);
        }
    }
    _ = dlg.end();
}

fn group(c: *ui.Context, k: theme.Colors, g: Group) void {
    ui.key(c, g.title);
    const box = ui.div(c).column().wFull().gap(7);
    defer box.end();
    ui.text(c, g.title, .{ .size = 12, .weight = .semibold, .color = k.secondary });
    for (g.items) |it| {
        ui.key(c, it.what);
        const r = ui.div(c).row().wFull().itemsCenter().gap(10);
        defer r.end();
        ui.text(c, it.what, .{ .size = 13, .color = k.text });
        ui.spacer(c);
        shortcut.keycaps(c, k, it, false);
    }
}
