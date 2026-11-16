//! The keyboard shortcuts overlay (Ctrl+? or F1), as GNOME apps show theirs:
//! what each key does, grouped, with the keys drawn as keycaps.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("state.zig");
const theme = @import("../ui/theme.zig");
const dialog = @import("../ui/dialog.zig");

const Item = struct { keys: []const []const u8, what: []const u8 };
const Group = struct { title: []const u8, items: []const Item };

/// Every shortcut zmon has; `keys.zig` handles them and README lists them.
pub const groups = [_]Group{
    .{ .title = "General", .items = &.{
        .{ .keys = &.{ "Ctrl", "F" }, .what = "Search apps and processes" },
        .{ .keys = &.{ "Ctrl", "," }, .what = "Settings" },
        .{ .keys = &.{ "Ctrl", "?" }, .what = "Keyboard shortcuts" },
        .{ .keys = &.{ "Ctrl", "Q" }, .what = "Quit" },
    } },
    .{ .title = "Pages", .items = &.{
        .{ .keys = &.{ "Ctrl", "1" }, .what = "Apps" },
        .{ .keys = &.{ "Ctrl", "2" }, .what = "Processes" },
        .{ .keys = &.{ "Ctrl", "3 to 6" }, .what = "CPU, Memory, Disk, Network" },
        .{ .keys = &.{ "Ctrl", "Page Down" }, .what = "Next page" },
        .{ .keys = &.{ "Ctrl", "Page Up" }, .what = "Previous page" },
    } },
    .{ .title = "Lists", .items = &.{
        .{ .keys = &.{ "↑", "↓" }, .what = "Select the row above or below" },
        .{ .keys = &.{ "Home", "End" }, .what = "First or last row" },
        .{ .keys = &.{"→"}, .what = "Show an app's processes" },
        .{ .keys = &.{"←"}, .what = "Hide them, or go back to the app" },
        .{ .keys = &.{"Delete"}, .what = "End task (Return confirms)" },
        .{ .keys = &.{ "Shift", "Delete" }, .what = "Force quit" },
        .{ .keys = &.{"Esc"}, .what = "Go back where you came from" },
        .{ .keys = &.{"Type"}, .what = "Start a search" },
    } },
    .{ .title = "Everywhere", .items = &.{
        .{ .keys = &.{ "Tab", "Shift Tab" }, .what = "Move between controls" },
        .{ .keys = &.{"Return"}, .what = "Open a page and go into it" },
        .{ .keys = &.{"Space"}, .what = "Press the focused control" },
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
        for (it.keys) |cap| keycap(c, k, cap);
    }
}

fn keycap(c: *ui.Context, k: theme.Colors, label: []const u8) void {
    ui.key(c, label);
    const d = ui.div(c).row().h(22).px(7).itemsCenter().rounded(5).bg(k.stripe).border(k.border);
    defer d.end();
    ui.text(c, label, .{ .size = 11.5, .weight = .medium, .color = k.text });
}
