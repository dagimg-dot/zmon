//! The Processes page: every process on the machine, one line each, with the
//! icon of the app it belongs to. Search by name or pid; columns sort when
//! their header is clicked.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const fmt = core.fmt;
const app = @import("../../app/state.zig");
const theme = @import("../../ui/theme.zig");
const table = @import("../../ui/table.zig");
const app_icon = @import("../../ui/app_icon.zig");
const controls = @import("../../ui/controls.zig");

const State = app.State;

const all_columns = [_]table.Column{
    .{ .title = "Name", .right = false },
    .{ .title = "User", .width = 96, .right = false, .drop = 1 },
    .{ .title = "PID", .width = 72, .drop = 2 },
    .{ .title = "CPU", .width = 76 },
    .{ .title = "Memory", .width = 96 },
    .{ .title = "Disk", .width = 100, .drop = 3 },
    .{ .title = "Threads", .width = 68, .sorts = false, .drop = 4 },
};
const Columns = @TypeOf(all_columns);
const keys = [_]app.Sort{ .name, .user, .pid, .cpu, .memory, .disk, .name };

pub fn page(c: *ui.Context, s: *State, k: theme.Colors) void {
    toolbar(c, s, k);
    var columns = all_columns;
    table.fit(&columns, table.lastWidth(c, s.list_id));
    const sorted = std.mem.indexOfScalar(app.Sort, keys[0..6], s.proc_order.key) orelse 0;
    if (table.header(c, k, &columns, sorted, s.proc_order.ascending)) |i| s.sortBy(keys[i]);
    const list = table.box(c, "processes-list");
    defer list.div.end();
    s.list_id = list.id;
    s.list_hovered = list.hovered;
    if (s.proc_rows.len == 0) {
        const query = s.search.text();
        return table.empty(c, k, if (query.len > 0)
            c.print("No process matches \"{s}\".", .{query})
        else if (s.sample.samples > 0)
            "zmon can't see the processes here: /proc may be hidden from other users (hidepid) or this may be a sandbox."
        else
            "Reading the processes…");
    }
    var rows = table.list(c, s.proc_rows.len, s.reveal);
    s.reveal = null;
    while (rows.next()) |i| procRow(c, s, k, &columns, s.proc_rows[i], i);
    rows.end();
}

fn toolbar(c: *ui.Context, s: *State, k: theme.Colors) void {
    const bar = ui.div(c).row().wFull().h(56).px(table.pad + 4).itemsCenter().gap(12);
    defer bar.end();
    ui.text(c, "Processes", .{ .size = 18, .weight = .bold, .color = k.text });
    {
        // The count gives way first when the toolbar is short of room.
        const count = ui.div(c).row().grow().w(0).clip();
        defer count.end();
        ui.text(c, c.print("{d} processes, {d} threads", .{ s.sample.process_count, s.sample.threads }), .{ .size = 12.5, .color = k.secondary });
    }
    ui.key(c, "search");
    if (ui.textField(c, &s.search, .{ .placeholder = "Search", .width = .{ .px = 220 }, .size = 13 }).changed) s.rebuild();
    if (controls.button(c, k, "Details", .{ .icon = "info.circle", .hint = "Ctrl+I" })) s.details_open = !s.details_open;
    if (controls.button(c, k, "End task", .{ .disabled = s.target() == null, .hint = "Delete" })) s.askEndTask(false);
}

fn procRow(c: *ui.Context, s: *State, k: theme.Colors, columns: *const Columns, index: u32, i: usize) void {
    const p: core.Proc = s.sample.procs[index];
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
    const m: table.Metrics = .{ .cpu = s.cpuShown(p.cpu), .memory = p.memory, .disk = p.disk_bps, .disk_known = p.io_known, .threads = p.threads };
    table.describeRow(c, r, c.print("{s}, process {d}", .{ p.name, p.pid }), m, sel);
    {
        const name = table.cell(c, columns[0], table.row_h).gap(8);
        defer name.end();
        if (s.ownerOf(index)) |g| app_icon.draw(c, &s.icons, k, g.*) else _ = c.leaf(.{ .width = .{ .px = 20 }, .height = .{ .px = 20 } }, .none, null);
        const root = if (s.ownerOf(index)) |g| g.kind == .app and g.root == p.pid else false;
        table.processName(c, ink, p.name, p.program, root);
    }
    var b: [16]u8 = undefined;
    table.value(c, columns[1], fmt.own(c.alloc(), s.userName(&b, p.uid)), ink.faint, false);
    table.value(c, columns[2], c.print("{d}", .{p.pid}), ink.faint, false);
    table.metrics(c, columns[3..], ink, m);
}
