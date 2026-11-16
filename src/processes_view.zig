//! The Processes page: apps first, then background processes and the
//! kernel's threads. A group shows its totals; open it to see what it
//! started. Columns sort when their header is clicked.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const app = @import("app.zig");
const apps = @import("zmon-system").apps;
const core = @import("zmon-core");
const fmt = core.fmt;
const theme = @import("theme.zig");

const State = app.State;
const row_h = 30;
const section_h = 34;
const header_h = 30;
const pad = 14;
const icon_size = 20;

const Column = struct { title: []const u8, sort: app.Sort, width: ?f32 = null, right: bool = true };
const columns = [_]Column{
    .{ .title = "Name", .sort = .name, .right = false },
    .{ .title = "CPU", .sort = .cpu, .width = 76 },
    .{ .title = "Memory", .sort = .memory, .width = 96 },
    .{ .title = "Disk", .sort = .disk, .width = 100 },
};
const threads_w = 68;

pub fn page(c: *ui.Context, s: *State, k: theme.Colors) void {
    toolbar(c, s, k);
    header(c, s, k);
    _ = c.leaf(.{ .width = .fill, .height = .{ .px = 1 }, .background = k.separator }, .none, null);
    var rows = ui.list(c, .{ .count = s.rows.len, .row_height = row_h });
    while (rows.next()) |i| {
        switch (s.rows[i]) {
            .section => |sec| sectionRow(c, k, sec.title, sec.count),
            .group => |g| groupRow(c, s, k, s.groups[g], i),
            .proc => |p| procRow(c, s, k, s.sampler.procs[p], i),
        }
    }
    rows.end();
}

fn toolbar(c: *ui.Context, s: *State, k: theme.Colors) void {
    const bar = ui.div(c).row().wFull().h(56).px(pad + 4).itemsCenter().gap(12);
    defer bar.end();
    ui.text(c, "Processes", .{ .size = 18, .weight = .bold, .color = k.text });
    ui.text(c, c.print("{d} running, {d} threads", .{ s.sampler.procs.len, s.sampler.threads }), .{ .size = 12.5, .color = k.secondary });
    ui.spacer(c);
    const t = s.target();
    if (kit.button(c, "End task", .{ .variant = .outline, .size = .sm, .disabled = t == null }).clicked) s.confirm = true;
}

fn header(c: *ui.Context, s: *State, k: theme.Colors) void {
    const h = ui.div(c).row().wFull().h(header_h).itemsCenter().px(pad);
    defer h.end();
    for (columns) |col| {
        ui.key(c, col.title);
        var d = cell(c, col, header_h).gap(4).control();
        d = d.hover(k.hover);
        defer d.end();
        if (d.clicked()) s.sortBy(col.sort);
        const on = s.sort == col.sort;
        ui.text(c, col.title, .{ .size = 11.5, .weight = if (on) .semibold else .regular, .color = if (on) k.text else k.secondary });
        if (on) ui.icon(c, if (s.ascending) "chevron.up" else "chevron.down", .{ .size = 8, .frame = 12, .weight = .bold, .color = k.secondary });
    }
    ui.key(c, "Threads");
    const t = ui.div(c).row().w(threads_w).h(header_h).itemsCenter().justifyEnd();
    defer t.end();
    ui.text(c, "Threads", .{ .size = 11.5, .color = k.secondary });
}

fn cell(c: *ui.Context, col: Column, h: f32) ui.Div {
    var d = ui.div(c).row().h(h).itemsCenter().px(6).clip();
    d = if (col.width) |w| d.w(w) else d.grow().w(0);
    if (col.right) d = d.justifyEnd();
    return d;
}

fn sectionRow(c: *ui.Context, k: theme.Colors, title: []const u8, count: usize) void {
    ui.key(c, title);
    const r = ui.div(c).row().wFull().h(row_h).itemsEnd().pb(6).px(pad + 6).gap(6);
    defer r.end();
    ui.text(c, title, .{ .size = 12, .weight = .semibold, .color = k.secondary });
    ui.text(c, c.print("{d}", .{count}), .{ .size = 12, .color = k.tertiary });
}

fn groupRow(c: *ui.Context, s: *State, k: theme.Colors, g: apps.Group, i: usize) void {
    ui.key(c, c.print("g{d}-{s}", .{ g.root, g.name }));
    const open = s.expanded.contains(g.root);
    const sel = s.selected == g.root and g.kind != .kernel;
    const r = ui.div(c).row().wFull().h(row_h).px(pad).itemsCenter();
    defer r.end();
    if (sel) _ = r.bg(k.selected) else if (i % 2 == 1) _ = r.bg(k.stripe) else _ = r.hover(k.hover);
    const it = r.interaction();
    if (it.clicked) {
        if (g.kind != .kernel) s.selected = g.root;
        c.changed = true;
    }
    if (it.double_clicked and g.members.len > 1) s.toggle(g.root);
    const ink = if (sel) k.selected_text else k.text;
    const faint = if (sel) k.selected_text.alpha(0.7) else k.secondary;
    {
        const name = ui.div(c).row().grow().w(0).h(row_h).itemsCenter().gap(6).px(6).clip();
        defer name.end();
        if (g.members.len > 1) {
            ui.key(c, "chev");
            const chev = ui.div(c).row().size(18, 18).itemsCenter().justifyCenter().rounded(4).control();
            defer chev.end();
            if (chev.clicked()) s.toggle(g.root);
            ui.icon(c, if (open) "chevron.down" else "chevron.right", .{ .size = 9, .frame = 14, .weight = .bold, .color = faint });
        } else {
            _ = c.leaf(.{ .width = .{ .px = 18 }, .height = .{ .px = 18 } }, .none, null);
        }
        appIcon(c, s, k, g);
        ui.text(c, g.name, .{ .size = 13.5, .weight = if (g.kind == .app) .semibold else .regular, .color = ink });
        if (g.members.len > 1) ui.text(c, c.print("({d})", .{g.members.len}), .{ .size = 12, .color = faint });
    }
    values(c, ink, faint, g.cpu, g.memory, g.disk_bps, g.kind != .kernel, g.threads);
}

/// The group's launcher icon, or a plain tile when it has none or can't be drawn.
fn appIcon(c: *ui.Context, s: *State, k: theme.Colors, g: apps.Group) void {
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

fn procRow(c: *ui.Context, s: *State, k: theme.Colors, p: core.Proc, i: usize) void {
    ui.key(c, c.print("p{d}", .{p.pid}));
    const sel = s.selected == p.pid;
    const r = ui.div(c).row().wFull().h(row_h).px(pad).itemsCenter();
    defer r.end();
    if (sel) _ = r.bg(k.selected) else if (i % 2 == 1) _ = r.bg(k.stripe) else _ = r.hover(k.hover);
    const it = r.interaction();
    if (it.clicked) {
        s.selected = p.pid;
        c.changed = true;
    }
    const ink = if (sel) k.selected_text else k.text;
    const faint = if (sel) k.selected_text.alpha(0.7) else k.secondary;
    {
        const name = ui.div(c).row().grow().w(0).h(row_h).itemsCenter().gap(6).pl(34).clip();
        defer name.end();
        ui.text(c, p.name, .{ .size = 13, .color = ink });
        ui.text(c, c.print("{d}", .{p.pid}), .{ .size = 11.5, .color = faint });
    }
    values(c, ink, faint, p.cpu, p.memory, p.disk_bps, p.io_known, p.threads);
}

fn values(c: *ui.Context, ink: ui.Color, faint: ui.Color, cpu: f32, memory: u64, disk: f32, disk_known: bool, threads: u32) void {
    var b: [32]u8 = undefined;
    num(c, columns[1], fmt.own(c.alloc(), fmt.percent(&b, cpu)), if (cpu >= 1) ink else faint, cpu >= 25);
    num(c, columns[2], fmt.own(c.alloc(), fmt.bytes(&b, memory)), ink, false);
    num(c, columns[3], if (disk_known) fmt.own(c.alloc(), fmt.rate(&b, disk)) else "–", if (disk >= 1024) ink else faint, false);
    const t = ui.div(c).row().w(threads_w).h(row_h).itemsCenter().justifyEnd().px(6);
    defer t.end();
    ui.text(c, c.print("{d}", .{threads}), .{ .size = 12.5, .color = faint });
}

fn num(c: *ui.Context, col: Column, text: []const u8, color: ui.Color, strong: bool) void {
    const d = cell(c, col, row_h);
    defer d.end();
    ui.text(c, text, .{ .size = 13, .weight = if (strong) .semibold else .regular, .color = color });
}

pub fn confirmDialog(c: *ui.Context, s: *State, k: theme.Colors) void {
    _ = k;
    const t = s.target();
    const name = if (t) |x| x.name else "";
    const count = if (t) |x| x.count else 0;
    const dlg = kit.dialog(c, "end-task", &s.confirm, .{
        .title = c.print("End {s}?", .{name}),
        .description = if (count > 1)
            c.print("This asks {d} processes to quit. Unsaved work in them may be lost.", .{count})
        else
            "This asks the process to quit. Unsaved work in it may be lost.",
        .ok = "End task",
        .ok_variant = .danger,
        .cancel = "Cancel",
    }) orelse return;
    if (dlg.end() == .ok) s.endTask(false);
}
