//! A sortable table: a header of columns over striped rows of the same
//! widths. The pages keep what is sorted; this draws it and reports clicks.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const fmt = @import("zmon-core").fmt;
const theme = @import("theme.zig");

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
};

/// The header row and the line under it; returns the column clicked, if one was.
pub fn header(c: *ui.Context, k: theme.Colors, columns: []const Column, sorted: usize, ascending: bool) ?usize {
    var clicked: ?usize = null;
    {
        const h = ui.div(c).row().wFull().h(header_h).itemsCenter().px(pad);
        defer h.end();
        for (columns, 0..) |col, i| {
            ui.key(c, col.title);
            var d = cell(c, col, header_h).gap(4);
            if (col.sorts) d = d.control().hover(k.hover);
            defer d.end();
            if (col.sorts and d.clicked()) clicked = i;
            const on = col.sorts and sorted == i;
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

/// A line in the middle of an empty list.
pub fn empty(c: *ui.Context, k: theme.Colors, message: []const u8) void {
    const d = ui.div(c).column().wFull().grow().itemsCenter().pt(48);
    defer d.end();
    ui.text(c, message, .{ .size = 13, .color = k.secondary });
}
