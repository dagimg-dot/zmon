//! The large chart and the figures of the device the sidebar opened.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("../../app/state.zig");
const charts = @import("../../ui/charts.zig");
const theme = @import("../../ui/theme.zig");
const stats = @import("stats.zig");

const State = app.State;

pub fn view(c: *ui.Context, s: *State, k: theme.Colors) void {
    const col = ui.div(c).column().wFull().grow().h(0).p(24).gap(18).scrollY();
    defer col.end();
    const h = &s.sample.history;
    const span = s.settings.span.seconds();
    switch (s.page) {
        .apps, .processes, .settings => {},
        .cpu => {
            const machine = s.sample.machine();
            heading(c, k, "CPU", if (machine.len > 0) machine else c.print("{d} cores", .{s.sample.cores.len}));
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
            stats.disk(c, s, k);
        },
        .network => {
            heading(c, k, "Network", "download solid, upload lighter");
            charts.area(c, &h.net_in, .{ .height = 220, .floor = 64 * 1024, .window = span, .color = k.network, .grid = k.separator, .second = &h.net_out });
            stats.network(c, s, k);
        },
        .battery => {
            heading(c, k, "Battery", stats.statusWord(s.sample.devices.battery));
            charts.area(c, &h.battery, .{ .height = 220, .max = 100, .window = span, .color = k.success, .grid = k.separator });
            stats.battery(c, s, k);
        },
    }
}

fn heading(c: *ui.Context, k: theme.Colors, title: []const u8, note: []const u8) void {
    const r = ui.div(c).row().wFull().itemsEnd().gap(10);
    defer r.end();
    ui.text(c, title, .{ .size = 22, .weight = .bold, .color = k.text });
    ui.text(c, note, .{ .size = 13, .color = k.secondary });
}
