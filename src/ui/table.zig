//! A sortable table: a header of columns over striped rows of the same
//! widths. The pages keep what is sorted; this draws it and reports clicks.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const fmt = @import("zmon-core").fmt;
const theme = @import("theme.zig");
const controls = @import("controls.zig");

pub const row_h = 30;
pub const header_h = 30;
pub const pad = 14;

pub const Column = struct {
    title: []const u8,
    /// A fixed width; null grows to fill (the name).
    width: ?f32 = null,
    right: bool = true,
    /// Whether clicking the header sorts by it.
    sorts: bool = true,
    /// When the table is narrow, columns go in this order, highest first;
    /// 0 never goes.
    drop: u8 = 0,
    /// Left out this frame (`fit`).
    hidden: bool = false,
};

/// The least room the name keeps before other columns give way.
pub const min_name = 200;

/// Hides columns, the highest `drop` first, until the name has `min_name`
/// in a table `width` wide (0: not laid out yet, so all stay).
pub fn fit(columns: []Column, width: f32) void {
    for (columns) |*col| col.hidden = false;
    if (width <= 0) return;
    while (true) {
        var fixed: f32 = 2 * pad;
        for (columns) |col| if (!col.hidden) {
            fixed += col.width orelse 0;
        };
        if (width - fixed >= min_name) return;
        var worst: ?*Column = null;
        for (columns) |*col| if (!col.hidden and col.drop > 0) {
            if (worst == null or col.drop > worst.?.drop) worst = col;
        };
        (worst orelse return).hidden = true;
    }
}

/// The width the table had in the last frame, by its list box (0 at first).
pub fn lastWidth(c: *ui.Context, list_id: u64) f32 {
    return if (c.rects.get(list_id)) |r| r.w else 0;
}

/// The header row and the line under it; returns the column clicked, if one was.
pub fn header(c: *ui.Context, k: theme.Colors, columns: []const Column, sorted: usize, ascending: bool) ?usize {
    var clicked: ?usize = null;
    {
        const h = ui.div(c).row().wFull().h(header_h).itemsCenter().px(pad);
        defer h.end();
        for (columns, 0..) |col, i| {
            if (col.hidden) continue;
            ui.key(c, col.title);
            var d = cell(c, col, header_h).gap(4);
            if (col.sorts) d = d.control().hover(k.hover);
            defer d.end();
            const on = col.sorts and sorted == i;
            if (col.sorts and controls.press(c, d, .{
                .label = c.print("Sort by {s}", .{col.title}),
                .value = if (!on) "" else if (ascending) "Sorted ascending" else "Sorted descending",
                .selected = on,
            })) clicked = i;
            ui.text(c, col.title, .{ .size = 11.5, .weight = if (on) .semibold else .regular, .color = if (on) k.text else k.secondary });
            if (on) ui.icon(c, if (ascending) "chevron.up" else "chevron.down", .{ .size = 8, .frame = 12, .weight = .bold, .color = k.secondary });
        }
    }
    _ = c.leaf(.{ .width = .fill, .height = .{ .px = 1 }, .background = k.separator }, .none, null);
    return clicked;
}

/// A cell of `col`'s width; end it after drawing its content.
pub fn cell(c: *ui.Context, col: Column, h: f32) ui.Div {
    var d = ui.div(c).row().h(h).itemsCenter().px(6).clip();
    d = if (col.width) |w| d.w(w) else d.grow().w(0);
    if (col.right) d = d.justifyEnd();
    return d;
}

/// A cell holding one value.
pub fn value(c: *ui.Context, col: Column, text: []const u8, color: ui.Color, strong: bool) void {
    if (col.hidden) return;
    const d = cell(c, col, row_h);
    defer d.end();
    ui.text(c, text, .{ .size = 13, .weight = if (strong) .semibold else .regular, .color = color });
}

/// What a row measures, in the last four columns: CPU, memory, disk and threads.
pub const Metrics = struct {
    cpu: f32,
    memory: u64,
    disk: f32,
    /// Linux shows disk use only for the user's own processes.
    disk_known: bool,
    threads: u32,
};

/// The cells for CPU, memory, disk and threads; `columns` are those four.
pub fn metrics(c: *ui.Context, columns: []const Column, i: Ink, m: Metrics) void {
    var b: [32]u8 = undefined;
    value(c, columns[0], fmt.own(c.alloc(), fmt.percent(&b, m.cpu)), if (m.cpu >= 1) i.text else i.faint, m.cpu >= 25);
    value(c, columns[1], fmt.own(c.alloc(), fmt.bytes(&b, m.memory)), i.text, false);
    value(c, columns[2], if (m.disk_known) fmt.own(c.alloc(), fmt.rate(&b, m.disk)) else "–", if (m.disk >= 1024) i.text else i.faint, false);
    value(c, columns[3], c.print("{d}", .{m.threads}), i.faint, false);
}

/// Tells a screen reader what a row is: its name and each value with its column.
pub fn describeRow(c: *ui.Context, r: ui.Div, name: []const u8, m: Metrics, selected: bool) void {
    var b: [3][32]u8 = undefined;
    ui.access.describe(c, r.index, .{
        .role = .row,
        .label = c.print("{s}, CPU {s}, memory {s}, disk {s}, {d} threads", .{
            name,
            fmt.percent(&b[0], m.cpu),
            fmt.bytes(&b[1], m.memory),
            if (m.disk_known) fmt.rate(&b[2], m.disk) else "unknown",
            m.threads,
        }),
        .selected = selected,
    });
}

/// A row: selected, striped or plain. Returns it to draw cells into; end it after.
pub fn row(c: *ui.Context, k: theme.Colors, i: usize, selected: bool) ui.Div {
    const r = ui.div(c).row().wFull().h(row_h).px(pad).itemsCenter();
    if (selected) _ = r.bg(k.selected) else if (i % 2 == 1) _ = r.bg(k.stripe) else _ = r.hover(k.hover);
    return r;
}

/// Text and quieter text on a row, inverted when the row is selected.
pub const Ink = struct { text: ui.Color, faint: ui.Color };

pub fn ink(k: theme.Colors, selected: bool) Ink {
    return if (selected)
        .{ .text = k.selected_text, .faint = k.selected_text.alpha(0.7) }
    else
        .{ .text = k.text, .faint = k.secondary };
}

/// The box a list sits in, one Tab stop for the whole list as a grid is:
/// Tab reaches it once and the keys move inside it. End `div` after the list.
pub const Box = struct { div: ui.Div, id: u64 };

pub fn box(c: *ui.Context, key: []const u8) Box {
    ui.key(c, key);
    // Inset by the ring's width and clipped, so rows never paint over the ring.
    const d = ui.div(c).column().wFull().grow().h(0).p(2).rounded(8).clip();
    const it = c.interact(d.index, .{ .focusable = true });
    return .{ .div = d, .id = it.id };
}

/// Opens a virtualized list of `count` rows, scrolled so that row `reveal`
/// (the keyboard's new selection) is in view.
pub fn list(c: *ui.Context, count: usize, reveal: ?usize) ui.ListRows {
    var to: ?f32 = null;
    if (reveal) |i| {
        const id = c.peekId(null);
        const at = (c.scroll.get(id) orelse 0);
        const view_h = if (c.rects.get(id)) |r| r.h else c.size.h;
        const top = @as(f32, @floatFromInt(i)) * row_h;
        if (top < at) to = top else if (top + row_h > at + view_h) to = top + row_h - view_h;
    }
    return ui.list(c, .{ .count = count, .row_height = row_h, .scroll_to = to });
}

/// The program a process runs, when its name doesn't already say it: a
/// "MainThread" that is node. Null when the name says enough.
pub fn programNote(name: []const u8, program: []const u8) ?[]const u8 {
    if (program.len == 0) return null;
    if (std.ascii.startsWithIgnoreCase(program, name) or std.ascii.startsWithIgnoreCase(name, program)) return null;
    return program;
}

/// A process's name, with its program after it, quieter, when that adds something.
pub fn processName(c: *ui.Context, i: Ink, name: []const u8, program: []const u8, strong: bool) void {
    ui.text(c, name, .{ .size = 13, .weight = if (strong) .semibold else .regular, .color = i.text });
    if (programNote(name, program)) |note| ui.text(c, note, .{ .size = 11.5, .color = i.faint });
}

/// A line in the middle of an empty list.
pub fn empty(c: *ui.Context, k: theme.Colors, message: []const u8) void {
    const d = ui.div(c).column().wFull().grow().itemsCenter().pt(48);
    defer d.end();
    ui.text(c, message, .{ .size = 13, .color = k.secondary });
}

test "a process's program is shown only when its name doesn't say it" {
    try std.testing.expectEqualStrings("node", programNote("MainThread", "node").?);
    try std.testing.expect(programNote("brave", "brave") == null);
    try std.testing.expect(programNote("claude-desktop", "claude") == null);
    try std.testing.expect(programNote("kworker/0:1", "") == null);
}

test "a narrow table drops its columns in order and keeps the name's room" {
    var cols = [_]Column{
        .{ .title = "Name", .right = false },
        .{ .title = "PID", .width = 72, .drop = 2 },
        .{ .title = "CPU", .width = 76 },
        .{ .title = "Threads", .width = 68, .drop = 3 },
    };
    fit(&cols, 1000);
    for (cols) |c| try std.testing.expect(!c.hidden);
    fit(&cols, 2 * pad + 76 + 72 + min_name); // room for one droppable
    try std.testing.expect(cols[3].hidden and !cols[1].hidden);
    fit(&cols, 300); // CPU never goes, whatever is left
    try std.testing.expect(cols[1].hidden and cols[3].hidden and !cols[2].hidden);
}
