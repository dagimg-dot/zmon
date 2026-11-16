//! The large chart and the figures of the device the sidebar opened.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const fmt = core.fmt;
const app = @import("../../app/state.zig");
const charts = @import("../../ui/charts.zig");
const theme = @import("../../ui/theme.zig");
const stats = @import("stats.zig");

const State = app.State;

pub fn view(c: *ui.Context, s: *State, k: theme.Colors) void {
    const col = ui.div(c).column().wFull().grow().h(0).p(24).gap(18).scrollY();
    defer col.end();
    const h = &s.sampler.history;
    const span = s.settings.span.seconds();
    switch (s.page) {
        .processes, .settings => {},
        .cpu => {
            const machine = s.sampler.machine();
            heading(c, k, "CPU", if (machine.len > 0) machine else c.print("{d} cores", .{s.sampler.cores.len}));
            charts.area(c, &h.cpu, .{ .height = 220, .max = 100, .window = span, .color = k.cpu, .grid = k.separator });
            stats.cpu(c, s, k);
        },
        .memory => {
            heading(c, k, "Memory", "");
            charts.area(c, &h.memory, .{ .height = 220, .max = 100, .window = span, .color = k.memory, .grid = k.separator });
            stats.memory(c, s, k);
        },
        .disk => {
            heading(c, k, "Disk", "reads solid, writes lighter");
            charts.area(c, &h.disk_read, .{ .height = 220, .floor = 256 * 1024, .window = span, .color = k.disk, .grid = k.separator, .second = &h.disk_write });
            var b: [2][24]u8 = undefined;
            const r = ui.div(c).row().wFull().gap(28);
            defer r.end();
            stats.stat(c, k, "Read", fmt.own(c.alloc(), fmt.rate(&b[0], s.sampler.disk_read_bps)));
            stats.stat(c, k, "Write", fmt.own(c.alloc(), fmt.rate(&b[1], s.sampler.disk_write_bps)));
        },
        .network => {
            heading(c, k, "Network", "download solid, upload lighter");
            charts.area(c, &h.net_in, .{ .height = 220, .floor = 64 * 1024, .window = span, .color = k.network, .grid = k.separator, .second = &h.net_out });
            var b: [2][24]u8 = undefined;
            const r = ui.div(c).row().wFull().gap(28);
            defer r.end();
            stats.stat(c, k, "Download", fmt.own(c.alloc(), fmt.rate(&b[0], s.sampler.net_in_bps)));
            stats.stat(c, k, "Upload", fmt.own(c.alloc(), fmt.rate(&b[1], s.sampler.net_out_bps)));
        },
    }
}

fn heading(c: *ui.Context, k: theme.Colors, title: []const u8, note: []const u8) void {
    const r = ui.div(c).row().wFull().itemsEnd().gap(10);
    defer r.end();
    ui.text(c, title, .{ .size = 22, .weight = .bold, .color = k.text });
    ui.text(c, note, .{ .size = 13, .color = k.secondary });
}
