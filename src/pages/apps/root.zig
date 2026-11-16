//! The Apps page: the apps a person opened from their launcher, each with the
//! processes it started folded in. Open an app to see them; columns sort when
//! their header is clicked.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const core = @import("zmon-core");
const apps = @import("zmon-system").apps;
const app = @import("../../app/state.zig");
const theme = @import("../../ui/theme.zig");
const table = @import("../../ui/table.zig");
const app_icon = @import("../../ui/app_icon.zig");

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
    if (s.app_rows.len == 0) return table.empty(c, k, "No apps are open.");
    var rows = ui.list(c, .{ .count = s.app_rows.len, .row_height = table.row_h });
    while (rows.next()) |i| switch (s.app_rows[i]) {
        .group => |g| groupRow(c, s, k, s.groups[g], i),
        .proc => |p| procRow(c, s, k, s.sampler.procs[p], i),
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
    if (kit.button(c, "End task", .{ .variant = .outline, .size = .sm, .disabled = s.target() == null }).clicked) {
        if (s.settings.confirm_end_task) s.confirm = true else s.endTask(false);
    }
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
        c.changed = true;
    }
    if (it.double_clicked and g.members.len > 1) s.pending_toggle = g.root;
    const ink = table.ink(k, sel);
    {
        const name = table.cell(c, columns[0], table.row_h).gap(6);
        defer name.end();
        if (g.members.len > 1) {
            ui.key(c, "chev");
            const chev = ui.div(c).row().size(18, 18).itemsCenter().justifyCenter().rounded(4).control();
            defer chev.end();
            if (chev.clicked()) s.pending_toggle = g.root;
            ui.icon(c, if (open) "chevron.down" else "chevron.right", .{ .size = 9, .frame = 14, .weight = .bold, .color = ink.faint });
        } else {
            _ = c.leaf(.{ .width = .{ .px = 18 }, .height = .{ .px = 18 } }, .none, null);
        }
        app_icon.draw(c, &s.icons, k, g);
        ui.text(c, g.name, .{ .size = 13.5, .weight = .semibold, .color = ink.text });
        if (g.members.len > 1) ui.text(c, c.print("({d})", .{g.members.len}), .{ .size = 12, .color = ink.faint });
    }
    table.metrics(c, columns[1..], ink, .{ .cpu = g.cpu, .memory = g.memory, .disk = g.disk_bps, .disk_known = true, .threads = g.threads });
}

fn procRow(c: *ui.Context, s: *State, k: theme.Colors, p: core.Proc, i: usize) void {
    ui.key(c, c.print("p{d}", .{p.pid}));
    const sel = s.selected_app == p.pid;
    const r = table.row(c, k, i, sel);
    defer r.end();
    if (r.interaction().clicked) {
        s.selected_app = p.pid;
        c.changed = true;
    }
    const ink = table.ink(k, sel);
    {
        const name = table.cell(c, columns[0], table.row_h).gap(6).pl(40);
        defer name.end();
        ui.text(c, p.name, .{ .size = 13, .color = ink.text });
        ui.text(c, c.print("{d}", .{p.pid}), .{ .size = 11.5, .color = ink.faint });
    }
    table.metrics(c, columns[1..], ink, .{ .cpu = p.cpu, .memory = p.memory, .disk = p.disk_bps, .disk_known = p.io_known, .threads = p.threads });
}
