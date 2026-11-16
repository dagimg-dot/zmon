//! The Performance page: a tile for each resource with its recent history,
//! and the one you pick drawn large with its figures beside it.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("app.zig");
const charts = @import("charts.zig");
const core = @import("zmon-core");
const fmt = core.fmt;
const theme = @import("theme.zig");

const State = app.State;

pub fn page(c: *ui.Context, s: *State, k: theme.Colors) void {
    const root = ui.div(c).row().wFull().grow().h(0);
    defer root.end();
    rail(c, s, k);
    _ = c.leaf(.{ .width = .{ .px = 1 }, .height = .fill, .background = k.separator }, .none, null);
    detail(c, s, k);
}

fn rail(c: *ui.Context, s: *State, k: theme.Colors) void {
    const col = ui.div(c).column().w(250).hFull().p(12).gap(8).scrollY();
    defer col.end();
    const h = &s.sampler.history;
    var b: [3][48]u8 = undefined;
    const mem = &s.sampler.memory;

    tile(c, s, k, .cpu, "CPU", fmt.own(c.alloc(), fmt.percent(&b[0], s.sampler.cpu_pct)), &h.cpu, 100);
    tile(c, s, k, .memory, "Memory", c.print("{s} / {s}", .{ fmt.bytes(&b[0], mem.used()), fmt.bytes(&b[1], mem.total) }), &h.memory, 100);
    tile(c, s, k, .disk, "Disk", c.print("R {s}  W {s}", .{ fmt.rate(&b[0], s.sampler.disk_read_bps), fmt.rate(&b[1], s.sampler.disk_write_bps) }), &h.disk_read, null);
    tile(c, s, k, .network, "Network", c.print("↓ {s}  ↑ {s}", .{ fmt.rate(&b[0], s.sampler.net_in_bps), fmt.rate(&b[1], s.sampler.net_out_bps) }), &h.net_in, null);
}

fn tile(c: *ui.Context, s: *State, k: theme.Colors, res: app.Resource, title: []const u8, value: []const u8, ring: *const core.Ring(f32), max: ?f32) void {
    ui.key(c, title);
    const on = s.resource == res;
    const box = ui.div(c).column().wFull().p(12).gap(6).rounded(10).control();
    defer box.end();
    if (on) _ = box.bg(k.panel).border(k.separator) else _ = box.hover(k.hover);
    if (box.clicked()) s.resource = res;
    ui.text(c, title, .{ .size = 13, .weight = .semibold, .color = k.text });
    ui.text(c, value, .{ .size = 11.5, .color = k.secondary });
    charts.spark(c, ring, 34, max, if (on) k.text else k.secondary);
}

fn detail(c: *ui.Context, s: *State, k: theme.Colors) void {
    const col = ui.div(c).column().grow().w(0).hFull().p(24).gap(18).scrollY();
    defer col.end();
    const h = &s.sampler.history;
    switch (s.resource) {
        .cpu => {
            heading(c, k, "CPU", c.print("{d} cores", .{s.sampler.cores.len}));
            charts.area(c, &h.cpu, .{ .height = 220, .max = 100, .color = k.text, .grid = k.separator });
            cpuStats(c, s, k);
        },
        .memory => {
            heading(c, k, "Memory", "");
            charts.area(c, &h.memory, .{ .height = 220, .max = 100, .color = k.text, .grid = k.separator });
            memoryStats(c, s, k);
        },
        .disk => {
            heading(c, k, "Disk", "reads solid, writes lighter");
            charts.area(c, &h.disk_read, .{ .height = 220, .floor = 256 * 1024, .color = k.text, .grid = k.separator, .second = &h.disk_write });
            var b: [2][24]u8 = undefined;
            const r = ui.div(c).row().wFull().gap(28);
            defer r.end();
            stat(c, k, "Read", fmt.own(c.alloc(), fmt.rate(&b[0], s.sampler.disk_read_bps)));
            stat(c, k, "Write", fmt.own(c.alloc(), fmt.rate(&b[1], s.sampler.disk_write_bps)));
        },
        .network => {
            heading(c, k, "Network", "download solid, upload lighter");
            charts.area(c, &h.net_in, .{ .height = 220, .floor = 64 * 1024, .color = k.text, .grid = k.separator, .second = &h.net_out });
            var b: [2][24]u8 = undefined;
            const r = ui.div(c).row().wFull().gap(28);
            defer r.end();
            stat(c, k, "Download", fmt.own(c.alloc(), fmt.rate(&b[0], s.sampler.net_in_bps)));
            stat(c, k, "Upload", fmt.own(c.alloc(), fmt.rate(&b[1], s.sampler.net_out_bps)));
        },
    }
}

fn heading(c: *ui.Context, k: theme.Colors, title: []const u8, note: []const u8) void {
    const r = ui.div(c).row().wFull().itemsEnd().gap(10);
    defer r.end();
    ui.text(c, title, .{ .size = 22, .weight = .bold, .color = k.text });
    ui.text(c, note, .{ .size = 13, .color = k.secondary });
}

fn stat(c: *ui.Context, k: theme.Colors, label: []const u8, value: []const u8) void {
    ui.key(c, label);
    const col = ui.div(c).column().gap(2);
    defer col.end();
    ui.text(c, label, .{ .size = 11.5, .color = k.secondary });
    ui.text(c, value, .{ .size = 20, .weight = .semibold, .color = k.text });
}

fn cpuStats(c: *ui.Context, s: *State, k: theme.Colors) void {
    var b: [4][32]u8 = undefined;
    {
        const r = ui.div(c).row().wFull().gap(28);
        defer r.end();
        stat(c, k, "Utilization", fmt.own(c.alloc(), fmt.percent(&b[0], s.sampler.cpu_pct)));
        stat(c, k, "Processes", c.print("{d}", .{s.sampler.procs.len}));
        stat(c, k, "Threads", c.print("{d}", .{s.sampler.threads}));
        stat(c, k, "Up time", fmt.own(c.alloc(), fmt.duration(&b[1], s.sampler.uptime)));
        stat(c, k, "Load", c.print("{d:.2}  {d:.2}  {d:.2}", .{ s.sampler.load[0], s.sampler.load[1], s.sampler.load[2] }));
    }
    ui.text(c, "Cores", .{ .size = 12.5, .weight = .semibold, .color = k.secondary });
    const grid = ui.div(c).row().wFull().gap(6).itemsEnd();
    defer grid.end();
    for (s.sampler.cores, 0..) |v, i| {
        ui.key(c, c.print("core{d}", .{i}));
        const col = ui.div(c).column().grow().w(0).gap(4).itemsCenter();
        defer col.end();
        const track = ui.div(c).column().wFull().h(64).justifyEnd().rounded(4).bg(k.panel);
        {
            defer track.end();
            const fill = ui.div(c).wFull().h(@max(2, 64 * v / 100)).rounded(4).bg(k.text);
            fill.end();
        }
        ui.text(c, c.print("{d}", .{i}), .{ .size = 10.5, .color = k.tertiary });
    }
}

fn memoryStats(c: *ui.Context, s: *State, k: theme.Colors) void {
    const m = s.sampler.memory;
    var b: [5][32]u8 = undefined;
    const r = ui.div(c).row().wFull().gap(28);
    defer r.end();
    stat(c, k, "In use", fmt.own(c.alloc(), fmt.bytes(&b[0], m.used())));
    stat(c, k, "Available", fmt.own(c.alloc(), fmt.bytes(&b[1], m.available)));
    stat(c, k, "Cached", fmt.own(c.alloc(), fmt.bytes(&b[2], m.cached)));
    stat(c, k, "Shared", fmt.own(c.alloc(), fmt.bytes(&b[3], m.shmem)));
    stat(c, k, "Swap", c.print("{s} / {s}", .{ fmt.bytes(&b[4], m.swapUsed()), fmt.bytes(&b[0], m.swap_total) }));
}
