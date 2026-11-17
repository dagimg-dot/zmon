//! zmon's keyboard shortcuts, written once: the keys `app/keys.zig` handles,
//! as the controls' tooltips and the Ctrl+? overlay show them. Hovering a
//! control that has one shows what it does and its keys as keycaps, so
//! every shortcut can be found where it is used.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const theme = @import("theme.zig");

/// The keys of one combination, pressed together ("Ctrl", "Shift", "P").
pub const Keys = []const []const u8;

pub const Shortcut = struct {
    /// What it does, as the tooltip and the overlay say it.
    what: []const u8,
    keys: Keys,
    /// Another combination that does the same ("F1" for Ctrl+?).
    alt: ?Keys = null,
};

pub const search: Shortcut = .{ .what = "Search apps and processes", .keys = &.{ "Ctrl", "F" } };
pub const settings: Shortcut = .{ .what = "Settings", .keys = &.{ "Ctrl", "," } };
pub const help: Shortcut = .{ .what = "Keyboard shortcuts", .keys = &.{ "Ctrl", "?" }, .alt = &.{"F1"} };
pub const pause: Shortcut = .{ .what = "Pause or resume updates", .keys = &.{ "Ctrl", "Shift", "P" } };
pub const sidebar: Shortcut = .{ .what = "Collapse or expand the sidebar", .keys = &.{ "Ctrl", "B" } };
pub const quit: Shortcut = .{ .what = "Quit", .keys = &.{ "Ctrl", "Q" } };
pub const apps: Shortcut = .{ .what = "Apps", .keys = &.{ "Ctrl", "1" } };
pub const processes: Shortcut = .{ .what = "Processes", .keys = &.{ "Ctrl", "2" } };
pub const cpu: Shortcut = .{ .what = "CPU", .keys = &.{ "Ctrl", "3" } };
pub const memory: Shortcut = .{ .what = "Memory", .keys = &.{ "Ctrl", "4" } };
pub const disk: Shortcut = .{ .what = "Disk", .keys = &.{ "Ctrl", "5" } };
pub const network: Shortcut = .{ .what = "Network", .keys = &.{ "Ctrl", "6" } };
pub const next_page: Shortcut = .{ .what = "Next page", .keys = &.{ "Ctrl", "Page Down" } };
pub const previous_page: Shortcut = .{ .what = "Previous page", .keys = &.{ "Ctrl", "Page Up" } };
pub const details: Shortcut = .{ .what = "Show or hide the details", .keys = &.{ "Ctrl", "I" } };
pub const end_task: Shortcut = .{ .what = "End task (Return confirms)", .keys = &.{"Delete"} };
pub const force_quit: Shortcut = .{ .what = "Force quit", .keys = &.{ "Shift", "Delete" } };

/// The arrow keys, drawn rather than written: Lexend has no arrows, and a
/// character the font lacks makes the text system read a fallback font,
/// often a CJK one of tens of megabytes, and keep it for the whole run.
const arrow_keys = [_]struct { label: []const u8, name: []const u8, icon: []const u8, turn: f32 = 0 }{
    .{ .label = "↑", .name = "Up", .icon = "arrow.up" },
    .{ .label = "↓", .name = "Down", .icon = "arrow.up", .turn = std.math.pi },
    .{ .label = "←", .name = "Left", .icon = "arrow.left" },
    .{ .label = "→", .name = "Right", .icon = "arrow.right" },
};

/// One key as a keycap: a raised key with a firmer lower edge.
pub fn keycap(c: *ui.Context, k: theme.Colors, label: []const u8, small: bool) void {
    ui.key(c, label);
    const h: f32 = if (small) 20 else 22;
    const d = ui.div(c).row().h(h).minW(h).px(if (small) 6 else 7).itemsCenter().justifyCenter().rounded(5)
        .bg(k.stripe).border(k.border).shadow(.{ .color = k.border, .blur = 0, .y = 1 });
    defer d.end();
    for (arrow_keys) |a| if (std.mem.eql(u8, a.label, label)) {
        ui.access.describe(c, d.index, .{ .role = .static_text, .label = a.name });
        ui.icon(c, a.icon, .{ .size = if (small) 10 else 11, .weight = .semibold, .color = k.text, .rotation = a.turn });
        return;
    };
    ui.text(c, label, .{ .size = if (small) 11 else 11.5, .weight = .semibold, .color = k.text });
}

/// A shortcut's keys as keycaps, with "or" before an alternative.
pub fn keycaps(c: *ui.Context, k: theme.Colors, s: Shortcut, small: bool) void {
    ui.key(c, s.what);
    const r = ui.div(c).row().gap(4).itemsCenter();
    defer r.end();
    for (s.keys) |cap| keycap(c, k, cap, small);
    if (s.alt) |alt| {
        ui.key(c, "or");
        ui.text(c, "or", .{ .size = 11, .color = k.secondary });
        for (alt) |cap| keycap(c, k, cap, small);
    }
}

/// What a tooltip draws, kept in the frame's memory until it is drawn.
const Tip = struct { label: []const u8, s: Shortcut, k: theme.Colors };

/// Hovering `d` shows `label` (what the control does; the shortcut's own
/// words when empty) and the shortcut's keys.
pub fn tooltip(c: *ui.Context, d: ui.Div, k: theme.Colors, label: []const u8, s: Shortcut) ui.Div {
    const tip = c.alloc().create(Tip) catch return d;
    tip.* = .{ .label = if (label.len > 0) label else s.what, .s = s, .k = k };
    return d.tooltipWith(@as(*const Tip, tip), drawTip, .{
        .delay = 0.4,
        .background = k.panel.mix(k.text, 0.04),
        .border = k.border,
        .padding = .xy(10, 7),
        .radius = 8,
        .max_width = 360,
        .themed = false,
    });
}

fn drawTip(tip: *const Tip, c: *ui.Context) void {
    const r = ui.div(c).row().gap(12).itemsCenter();
    defer r.end();
    ui.text(c, tip.label, .{ .size = 12.5, .weight = .medium, .color = tip.k.text });
    keycaps(c, tip.k, tip.s, true);
}

test "every shortcut has words and keys" {
    const all = [_]Shortcut{ search, settings, help, pause, sidebar, quit, apps, processes, cpu, memory, disk, network, next_page, previous_page, details, end_task, force_quit };
    for (all) |s| {
        try std.testing.expect(s.what.len > 0);
        try std.testing.expect(s.keys.len > 0);
    }
}
