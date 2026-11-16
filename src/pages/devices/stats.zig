//! The figures under a chart: labelled values, the cores, the memory split.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const fmt = core.fmt;
const app = @import("../../app/state.zig");
const theme = @import("../../ui/theme.zig");

const State = app.State;

pub fn stat(c: *ui.Context, k: theme.Colors, label: []const u8, value: []const u8) void {
    ui.key(c, label);
    const col = ui.div(c).column().gap(2);
    defer col.end();
    ui.text(c, label, .{ .size = 11.5, .color = k.secondary });
    ui.text(c, value, .{ .size = 20, .weight = .semibold, .color = k.text });
}

pub fn cpu(c: *ui.Context, s: *State, k: theme.Colors) void {
    var b: [4][32]u8 = undefined;
    {
        const r = ui.div(c).row().wFull().gap(28);
        defer r.end();
        stat(c, k, "Utilization", fmt.own(c.alloc(), fmt.percent(&b[0], s.sample.cpu_pct)));
        stat(c, k, "Processes", c.print("{d}", .{s.sample.process_count}));
        stat(c, k, "Threads", c.print("{d}", .{s.sample.threads}));
        stat(c, k, "Up time", fmt.own(c.alloc(), fmt.duration(&b[1], s.sample.uptime)));
        stat(c, k, "Load", c.print("{d:.2}  {d:.2}  {d:.2}", .{ s.sample.load[0], s.sample.load[1], s.sample.load[2] }));
    }
    ui.text(c, "Cores", .{ .size = 12.5, .weight = .semibold, .color = k.secondary });
    const grid = ui.div(c).row().wFull().gap(6).itemsEnd();
    defer grid.end();
    for (s.sample.cores, 0..) |v, i| {
        ui.key(c, c.print("core{d}", .{i}));
        const col = ui.div(c).column().grow().w(0).gap(4).itemsCenter();
        defer col.end();
        const track = ui.div(c).column().wFull().h(64).justifyEnd().rounded(4).bg(k.panel);
        {
            defer track.end();
            const fill = ui.div(c).wFull().h(@max(2, 64 * v / 100)).rounded(4).bg(k.cpu);
            fill.end();
        }
        ui.text(c, c.print("{d}", .{i}), .{ .size = 10.5, .color = k.tertiary });
    }
}

pub fn memory(c: *ui.Context, s: *State, k: theme.Colors) void {
    const m = s.sample.memory;
    var b: [5][32]u8 = undefined;
    const r = ui.div(c).row().wFull().gap(28);
    defer r.end();
    stat(c, k, "In use", fmt.own(c.alloc(), fmt.bytes(&b[0], m.used())));
    stat(c, k, "Available", fmt.own(c.alloc(), fmt.bytes(&b[1], m.available)));
    stat(c, k, "Cached", fmt.own(c.alloc(), fmt.bytes(&b[2], m.cached)));
    stat(c, k, "Shared", fmt.own(c.alloc(), fmt.bytes(&b[3], m.shmem)));
    stat(c, k, "Swap", c.print("{s} / {s}", .{ fmt.bytes(&b[4], m.swapUsed()), fmt.bytes(&b[0], m.swap_total) }));
}
