//! The Apps page: the apps a person opened from their launcher, each with the
//! processes it started folded in. Open an app to see them; columns sort when
//! their header is clicked.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const apps = @import("zmon-system").apps;
const app = @import("../../app/state.zig");
const theme = @import("../../ui/theme.zig");
const table = @import("../../ui/table.zig");
const app_icon = @import("../../ui/app_icon.zig");
const controls = @import("../../ui/controls.zig");

const State = app.State;

const columns = [_]table.Column{
    .{ .title = "Name", .right = false },
    .{ .title = "CPU", .width = 76 },
    .{ .title = "Memory", .width = 96 },
    .{ .title = "Disk", .width = 100 },
    .{ .title = "Threads", .width = 68, .sorts = false },
};
const keys = [_]app.Sort{ .name, .cpu, .memory, .disk, .name };

pub fn page(c: *ui.Context, s: *State, k: theme.Colors) void {
    toolbar(c, s, k);
    const sorted = std.mem.indexOfScalar(app.Sort, keys[0..4], s.app_order.key) orelse 0;
    if (table.header(c, k, &columns, sorted, s.app_order.ascending)) |i| s.sortBy(keys[i]);
    const list = table.box(c, "apps-list");
    defer list.div.end();
    s.list_id = list.id;
    if (s.app_rows.len == 0) {
        const query = s.search.text();
        return table.empty(c, k, if (query.len > 0) c.print("No app matches \"{s}\".", .{query}) else "No apps are open.");
    }
    var rows = table.list(c, s.app_rows.len, s.reveal);
    s.reveal = null;
    while (rows.next()) |i| switch (s.app_rows[i]) {
        .group => |g| groupRow(c, s, k, s.groups[g], i),
        .proc => |p| procRow(c, s, k, s.sample.procs[p], i),
    };
    rows.end();
    if (s.pending_toggle) |root| {
        s.pending_toggle = null;
        s.toggle(root);
        c.changed = true;
    }
}

fn toolbar(c: *ui.Context, s: *State, k: theme.Colors) void {
    const bar = ui.div(c).row().wFull().h(56).px(table.pad + 4).itemsCenter().gap(12);
    defer bar.end();
    ui.text(c, "Apps", .{ .size = 18, .weight = .bold, .color = k.text });
    const n = s.appCount();
    ui.text(c, c.print("{d} open", .{n}), .{ .size = 12.5, .color = k.secondary });
    ui.spacer(c);
    search(c, s);
    if (controls.button(c, k, "End task", .{ .disabled = s.target() == null, .hint = "Delete" })) s.askEndTask(false);
}

fn groupRow(c: *ui.Context, s: *State, k: theme.Colors, g: apps.Group, i: usize) void {
    ui.key(c, c.print("g{d}-{s}", .{ g.root, g.name }));
    const open = s.expanded.contains(g.root);
    const sel = s.selected_app == g.root;
    const r = table.row(c, k, i, sel);
    defer r.end();
    const it = r.interaction();
    if (it.clicked) {
        s.selected_app = g.root;
        c.focus = s.list_id; // the keyboard carries on in the list
        c.changed = true;
    }
    if (it.double_clicked and g.members.len > 1) s.pending_toggle = g.root;
    const ink = table.ink(k, sel);
    const m: table.Metrics = .{ .cpu = g.cpu, .memory = g.memory, .disk = g.disk_bps, .disk_known = true, .threads = g.threads };
    table.describeRow(c, r, if (g.members.len > 1) c.print("{s}, {d} processes, {s}", .{ g.name, g.members.len, if (open) "open" else "closed" }) else g.name, m, sel);
    {
        const name = table.cell(c, columns[0], table.row_h).gap(6);
        defer name.end();
        if (g.members.len > 1) {
            ui.key(c, "chev");
            const chev = ui.div(c).row().size(24, 24).itemsCenter().justifyCenter().rounded(5).control().hover(k.hover);
            defer chev.end();
            ui.access.describe(c, chev.index, .{ .label = if (open) "Hide its processes" else "Show its processes" });
            if (chev.clicked()) s.pending_toggle = g.root;
            ui.icon(c, if (open) "chevron.down" else "chevron.right", .{ .size = 9, .frame = 14, .weight = .bold, .color = ink.faint });
        } else {
            _ = c.leaf(.{ .width = .{ .px = 24 }, .height = .{ .px = 24 } }, .none, null);
        }
        app_icon.draw(c, &s.icons, k, g);
        ui.text(c, g.name, .{ .size = 13.5, .weight = .semibold, .color = ink.text });
        if (g.members.len > 1) ui.text(c, c.print("({d})", .{g.members.len}), .{ .size = 12, .color = ink.faint });
    }
    table.metrics(c, columns[1..], ink, m);
}

fn procRow(c: *ui.Context, s: *State, k: theme.Colors, p: core.Proc, i: usize) void {
    ui.key(c, c.print("p{d}", .{p.pid}));
    const sel = s.selected_app == p.pid;
    const r = table.row(c, k, i, sel);
    defer r.end();
    if (r.interaction().clicked) {
        s.selected_app = p.pid;
        c.focus = s.list_id;
        c.changed = true;
    }
    const ink = table.ink(k, sel);
    const m: table.Metrics = .{ .cpu = p.cpu, .memory = p.memory, .disk = p.disk_bps, .disk_known = p.io_known, .threads = p.threads };
    table.describeRow(c, r, c.print("{s}, process {d}", .{ p.name, p.pid }), m, sel);
    {
        const name = table.cell(c, columns[0], table.row_h).gap(6).pl(46);
        defer name.end();
        ui.text(c, p.name, .{ .size = 13, .color = ink.text });
        ui.text(c, c.print("{d}", .{p.pid}), .{ .size = 11.5, .color = ink.faint });
    }
    table.metrics(c, columns[1..], ink, m);
}

/// The search both lists share: what is typed here filters Processes too.
fn search(c: *ui.Context, s: *State) void {
    ui.key(c, "search");
    if (ui.textField(c, &s.search, .{ .placeholder = "Search", .width = .{ .px = 220 }, .size = 13 }).changed) s.rebuild();
}
