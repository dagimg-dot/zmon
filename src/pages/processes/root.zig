//! The Processes page: every process on the machine, one line each, with the
//! icon of the app it belongs to. Search by name or pid; columns sort when
//! their header is clicked.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const fmt = core.fmt;
const system = @import("zmon-system");
const app = @import("../../app/state.zig");
const theme = @import("../../ui/theme.zig");
const table = @import("../../ui/table.zig");
const app_icon = @import("../../ui/app_icon.zig");
const controls = @import("../../ui/controls.zig");
const toolbar = @import("../toolbar.zig");

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
    toolbar.draw(c, s, k, "Processes", c.print("{d} processes, {d} threads", .{ s.sample.process_count, s.sample.threads }));
    var columns = all_columns;
    table.fit(&columns, table.lastWidth(c, s.list_id));
    const sorted = std.mem.indexOfScalar(app.Sort, keys[0..6], s.proc_order.key) orelse 0;
    if (table.header(c, k, &columns, sorted, s.proc_order.ascending)) |i| s.sortBy(keys[i]);
    const list = table.box(c, "processes-list");
    defer list.div.end();
    s.list_id = list.id;
    s.list_hovered = list.hovered;
    if (s.proc_rows.len == 0) {
        if (@import("../waiting.zig").draw(c, s, k)) return;
        const query = s.search.text();
        if (core.search.port(query)) |port| return portEmpty(c, s, k, port);
        return table.empty(c, k, if (core.search.port(query)) |port|
            portMessage(c, s, port)
        else if (query.len > 0)
            c.print("No process matches \"{s}\".", .{query})
        else
            "zmon can't see the processes here: /proc may be hidden from other users (hidepid) or this may be a sandbox.");
    }
    var rows = table.list(c, s.proc_rows.len, s.reveal);
    s.reveal = null;
    s.beginList();
    while (rows.next()) |i| procRow(c, s, k, &columns, s.proc_rows[i], i);
    rows.end();
    s.endList();
}

/// A ":port" search with no row: why, and for another user's process, a
/// way to see which one by asking for root once.
fn portEmpty(c: *ui.Context, s: *State, k: theme.Colors, port: u16) void {
    const d = ui.div(c).column().wFull().grow().itemsCenter().pt(48).gap(14);
    defer d.end();
    {
        const words = ui.div(c).column().maxW(520).px(24).itemsCenter();
        defer words.end();
        ui.text(c, portMessage(c, s, port), .{ .size = 13, .color = k.secondary });
    }
    if (s.sample.port != port or s.sample.port_holders.other_uid == null) return;
    if (s.lookingUp()) {
        ui.text(c, "Waiting for your password…", .{ .size = 12.5, .color = k.tertiary });
    } else if (controls.button(c, k, "Show with administrator rights", .{ .icon = "lock", .hint = "Asks for your password once" })) {
        const waker: ?system.sampler.Waker = if (c.waker) |w| .{ .ctx = w.ctx, .wake = w.wake } else null;
        s.lookUpAsRoot(port, waker);
    }
}

/// What a ":port" search found when no row shows: nothing yet, nothing at
/// all, or a process of another user, which zmon can't name without root.
fn portMessage(c: *ui.Context, s: *State, port: u16) []const u8 {
    if (s.sample.port != port) return c.print("Looking for port {d}…", .{port});
    if (s.sample.port_holders.other_uid) |uid| {
        var b: [16]u8 = undefined;
        return c.print("Port {d} is held by a process of {s}. Which one can only be seen with root.", .{ port, s.userName(&b, uid) });
    }
    return c.print("Nothing holds port {d}.", .{port});
}

fn procRow(c: *ui.Context, s: *State, k: theme.Colors, columns: *const Columns, index: u32, i: usize) void {
    const p: core.Proc = s.sample.procs[index];
    ui.key(c, c.print("p{d}", .{p.pid}));
    const sel = s.selected_proc == p.pid;
    const r = table.row(c, k, i, sel);
    defer r.end();
    const it = r.interaction();
    if (it.double_clicked) s.details_open = true; // a row's details, as in Apps
    if (it.clicked) {
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
