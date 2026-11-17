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
const toolbar = @import("../toolbar.zig");

const State = app.State;

const all_columns = [_]table.Column{
    .{ .title = "Name", .right = false },
    .{ .title = "CPU", .width = 76 },
    .{ .title = "Memory", .width = 96 },
    .{ .title = "Disk", .width = 100, .drop = 1 },
    .{ .title = "Threads", .width = 68, .sorts = false, .drop = 2 },
};
const Columns = @TypeOf(all_columns);
const keys = [_]app.Sort{ .name, .cpu, .memory, .disk, .name };

pub fn page(c: *ui.Context, s: *State, k: theme.Colors) void {
    toolbar.draw(c, s, k, "Apps", c.print("{d} open", .{s.appCount()}));
    var columns = all_columns;
    table.fit(&columns, table.lastWidth(c, s.list_id));
    const sorted = std.mem.indexOfScalar(app.Sort, keys[0..4], s.app_order.key) orelse 0;
    if (table.header(c, k, &columns, sorted, s.app_order.ascending)) |i| s.sortBy(keys[i]);
    const list = table.box(c, "apps-list");
    defer list.div.end();
    s.list_id = list.id;
    s.list_hovered = list.hovered;
    if (s.app_rows.len == 0) {
        const query = s.search.text();
        return table.empty(c, k, if (query.len > 0) c.print("No app matches \"{s}\".", .{query}) else "No apps are open.");
    }
    var rows = table.list(c, s.app_rows.len, s.reveal);
    s.reveal = null;
    s.beginList();
    while (rows.next()) |i| switch (s.app_rows[i]) {
        .group => |g| groupRow(c, s, k, &columns, s.groups[g], i),
        .proc => |p| procRow(c, s, k, &columns, s.sample.procs[p], i),
        .background => |n| backgroundRow(c, s, k, n, i),
    };
    rows.end();
    s.endList();
    if (s.pending_toggle) |root| {
        s.pending_toggle = null;
        s.toggle(root);
        c.changed = true;
    }
}

fn groupRow(c: *ui.Context, s: *State, k: theme.Colors, columns: *const Columns, g: apps.Group, i: usize) void {
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
    // Double-click shows its details, as on every row; the arrow (or Right
    // and Left) opens its processes.
    if (it.double_clicked) s.details_open = true;
    const ink = table.ink(k, sel);
    const m: table.Metrics = .{ .cpu = s.cpuShown(g.cpu), .memory = g.memory, .disk = g.disk_bps, .disk_known = true, .threads = g.threads };
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
        ui.text(c, g.name, .{ .size = 13.5, .weight = if (g.kind == .app) .semibold else .regular, .color = ink.text });
        if (g.members.len > 1) ui.text(c, c.print("({d})", .{g.members.len}), .{ .size = 12, .color = ink.faint });
    }
    table.metrics(c, columns[1..], ink, m);
}

/// The heading over everything that isn't an app: services, containers,
/// what the session runs. Closed at first; opens like an app.
fn backgroundRow(c: *ui.Context, s: *State, k: theme.Colors, count: u32, i: usize) void {
    ui.key(c, "background-heading");
    const sel = s.selected_app == app.heading;
    const open = s.background_open or std.mem.trim(u8, s.search.text(), " ").len > 0;
    const r = table.row(c, k, i, sel);
    defer r.end();
    if (r.interaction().clicked) {
        s.selected_app = app.heading;
        s.showBackground(!s.background_open);
        c.focus = s.list_id;
        c.changed = true;
    }
    ui.access.describe(c, r.index, .{ .role = .row, .label = c.print("Background, {d} groups, {s}", .{ count, if (open) "open" else "closed" }), .selected = sel });
    const ink = table.ink(k, sel);
    const name = ui.div(c).row().grow().w(0).h(table.row_h).itemsCenter().gap(6).px(6);
    defer name.end();
    ui.icon(c, if (open) "chevron.down" else "chevron.right", .{ .size = 9, .frame = 24, .weight = .bold, .color = ink.faint });
    ui.text(c, "Background", .{ .size = 12.5, .weight = .semibold, .color = ink.faint });
    ui.text(c, c.print("{d}", .{count}), .{ .size = 12, .color = ink.faint });
}

fn procRow(c: *ui.Context, s: *State, k: theme.Colors, columns: *const Columns, p: core.Proc, i: usize) void {
    ui.key(c, c.print("p{d}", .{p.pid}));
    const sel = s.selected_app == p.pid;
    const r = table.row(c, k, i, sel);
    defer r.end();
    const it = r.interaction();
    if (it.double_clicked) s.details_open = true;
    if (it.clicked) {
        s.selected_app = p.pid;
        c.focus = s.list_id;
        c.changed = true;
    }
    const ink = table.ink(k, sel);
    const m: table.Metrics = .{ .cpu = s.cpuShown(p.cpu), .memory = p.memory, .disk = p.disk_bps, .disk_known = p.io_known, .threads = p.threads };
    table.describeRow(c, r, c.print("{s}, process {d}", .{ p.name, p.pid }), m, sel);
    {
        const name = table.cell(c, columns[0], table.row_h).gap(6).pl(46);
        defer name.end();
        table.processName(c, ink, p.name, p.program, false);
        ui.text(c, c.print("{d}", .{p.pid}), .{ .size = 11.5, .color = ink.faint });
    }
    table.metrics(c, columns[1..], ink, m);
}
