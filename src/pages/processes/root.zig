//! The Processes page: every process on the machine, one line each, with the
//! icon of the app it belongs to. Search by name or pid; columns sort when
//! their header is clicked.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const app = @import("../../app/state.zig");
const theme = @import("../../ui/theme.zig");
const table = @import("../../ui/table.zig");
const app_icon = @import("../../ui/app_icon.zig");
const controls = @import("../../ui/controls.zig");

const State = app.State;

const columns = [_]table.Column{
    .{ .title = "Name", .right = false },
    .{ .title = "PID", .width = 72 },
    .{ .title = "CPU", .width = 76 },
    .{ .title = "Memory", .width = 96 },
    .{ .title = "Disk", .width = 100 },
    .{ .title = "Threads", .width = 68, .sorts = false },
};
const keys = [_]app.Sort{ .name, .pid, .cpu, .memory, .disk, .name };

pub fn page(c: *ui.Context, s: *State, k: theme.Colors) void {
    toolbar(c, s, k);
    const sorted = std.mem.indexOfScalar(app.Sort, keys[0..5], s.proc_order.key) orelse 0;
    if (table.header(c, k, &columns, sorted, s.proc_order.ascending)) |i| s.sortBy(keys[i]);
    const list = table.box(c, "processes-list");
    defer list.div.end();
    s.list_id = list.id;
    if (s.proc_rows.len == 0) {
        const query = s.search.text();
        return table.empty(c, k, if (query.len > 0) c.print("No process matches \"{s}\".", .{query}) else "No processes.");
    }
    var rows = table.list(c, s.proc_rows.len, s.reveal);
    s.reveal = null;
    while (rows.next()) |i| procRow(c, s, k, s.proc_rows[i], i);
    rows.end();
}

fn toolbar(c: *ui.Context, s: *State, k: theme.Colors) void {
    const bar = ui.div(c).row().wFull().h(56).px(table.pad + 4).itemsCenter().gap(12);
    defer bar.end();
    ui.text(c, "Processes", .{ .size = 18, .weight = .bold, .color = k.text });
    ui.text(c, c.print("{d} running, {d} threads", .{ s.sampler.process_count, s.sampler.threads }), .{ .size = 12.5, .color = k.secondary });
    ui.spacer(c);
    ui.key(c, "search");
    if (ui.textField(c, &s.search, .{ .placeholder = "Search", .width = .{ .px = 220 }, .size = 13 }).changed) s.rebuild();
    if (controls.button(c, k, "End task", .{ .disabled = s.target() == null, .hint = "Delete" })) s.askEndTask(false);
}

fn procRow(c: *ui.Context, s: *State, k: theme.Colors, index: u32, i: usize) void {
    const p: core.Proc = s.sampler.procs[index];
    ui.key(c, c.print("p{d}", .{p.pid}));
    const sel = s.selected_proc == p.pid;
    const r = table.row(c, k, i, sel);
    defer r.end();
    if (r.interaction().clicked) {
        s.selected_proc = p.pid;
        c.focus = s.list_id;
        c.changed = true;
    }
    const ink = table.ink(k, sel);
    const m: table.Metrics = .{ .cpu = p.cpu, .memory = p.memory, .disk = p.disk_bps, .disk_known = p.io_known, .threads = p.threads };
    table.describeRow(c, r, c.print("{s}, process {d}", .{ p.name, p.pid }), m, sel);
    {
        const name = table.cell(c, columns[0], table.row_h).gap(8);
        defer name.end();
        if (s.ownerOf(index)) |g| app_icon.draw(c, &s.icons, k, g.*) else _ = c.leaf(.{ .width = .{ .px = 20 }, .height = .{ .px = 20 } }, .none, null);
        ui.text(c, p.name, .{ .size = 13, .weight = if (s.ownerOf(index)) |g| (if (g.kind == .app and g.root == p.pid) .semibold else .regular) else .regular, .color = ink.text });
    }
    table.value(c, columns[1], c.print("{d}", .{p.pid}), ink.faint, false);
    table.metrics(c, columns[2..], ink, m);
}
