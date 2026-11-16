//! The Performance page: a tile for each resource with its recent history, and
//! the one you pick drawn large with its figures beside it.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const fmt = core.fmt;
const system = @import("zmon-system");
const app = @import("../../app/state.zig");
const charts = @import("../../ui/charts.zig");
const theme = @import("../../ui/theme.zig");
const detail = @import("detail.zig");

const State = app.State;

pub fn page(c: *ui.Context, s: *State, k: theme.Colors) void {
    const root = ui.div(c).row().wFull().grow().h(0);
    defer root.end();
    rail(c, s, k);
    _ = c.leaf(.{ .width = .{ .px = 1 }, .height = .fill, .background = k.separator }, .none, null);
    detail.view(c, s, k);
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
