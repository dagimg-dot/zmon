//! The sidebar: the pages first, then a live tile for each device, as GNOME's
//! Resources and Mission Center lay it out. A tile opens that device's page.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const fmt = core.fmt;
const state = @import("state.zig");
const theme = @import("../ui/theme.zig");
const tile = @import("../ui/tile.zig");
const controls = @import("../ui/controls.zig");
const app_icon = @import("../ui/icon.zig");

const State = state.State;
const Page = state.Page;

pub fn draw(c: *ui.Context, s: *State, k: theme.Colors) void {
    const side = ui.div(c).column().w(236).hFull().bg(k.panel).px(10).py(10).gap(4).scrollY();
    defer side.end();
    {
        // The icon's corner sits as far from the top as from the left (20), in
        // line with the page icons below it.
        const head = ui.div(c).row().px(10).pt(10).pb(10).itemsCenter().gap(10);
        defer head.end();
        app_icon.draw(c, 22);
        ui.text(c, "zmon", .{ .size = 17, .weight = .bold, .color = k.text });
    }
    nav(c, s, k, .apps, "Apps", "square.grid.2x2");
    nav(c, s, k, .processes, "Processes", "waveform.path.ecg");
    section(c, k, "Devices");
    devices(c, s, k);
    ui.spacer(c);
    nav(c, s, k, .settings, "Settings", "gearshape");
    var b: [2][32]u8 = undefined;
    const r = ui.div(c).row().wFull().px(8).pt(10);
    defer r.end();
    ui.text(c, c.print("Up {s} · load {d:.1}", .{ fmt.duration(&b[0], s.sampler.uptime), s.sampler.load[0] }), .{ .size = 11, .color = k.tertiary });
}

fn nav(c: *ui.Context, s: *State, k: theme.Colors, page: Page, label: []const u8, icon: []const u8) void {
    ui.key(c, label);
    const on = s.page == page;
    const row = ui.div(c).row().wFull().h(34).px(10).itemsCenter().gap(10).rounded(8).control();
    defer row.end();
    if (on) _ = row.bg(k.selected) else _ = row.hover(k.hover);
    const id = c.interact(row.index, .{}).id;
    s.nav_ids.set(page, id);
    if (controls.press(c, row, .{ .role = .tab, .label = label, .selected = on })) s.openFromSidebar(page, id);
    const ink = if (on) k.selected_text else k.text;
    ui.icon(c, icon, .{ .size = 14, .frame = 18, .color = ink });
    ui.text(c, label, .{ .size = 13.5, .weight = if (on) .semibold else .regular, .color = ink });
}

fn section(c: *ui.Context, k: theme.Colors, title: []const u8) void {
    const r = ui.div(c).row().wFull().px(10).pt(12).pb(2);
    defer r.end();
    ui.text(c, title, .{ .size = 11.5, .weight = .semibold, .color = k.tertiary });
}

fn devices(c: *ui.Context, s: *State, k: theme.Colors) void {
    const smp = &s.sampler;
    const h = &smp.history;
    const mem = smp.memory;
    var b: [4][32]u8 = undefined;
    const tiles = [_]struct { page: Page, t: tile.Tile }{
        .{ .page = .cpu, .t = .{
            .key = "tile-cpu",
            .color = k.cpu,
            .window = s.settings.span.seconds(),
            .icon = "cpu",
            .title = "CPU",
            .value = fmt.own(c.alloc(), fmt.percent(&b[0], smp.cpu_pct)),
            .detail = c.print("{d} cores · {d} processes", .{ smp.cores.len, smp.procs.len }),
            .history = &h.cpu,
            .max = 100,
        } },
        .{ .page = .memory, .t = .{
            .key = "tile-memory",
            .color = k.memory,
            .window = s.settings.span.seconds(),
            .icon = "memorychip",
            .title = "Memory",
            .value = fmt.own(c.alloc(), fmt.percent(&b[1], h.memory.at(h.memory.len -| 1))),
            .detail = c.print("{s} of {s}", .{ fmt.bytes(&b[2], mem.used()), fmt.bytes(&b[3], mem.total) }),
            .history = &h.memory,
            .max = 100,
        } },
        .{ .page = .disk, .t = .{
            .key = "tile-disk",
            .color = k.disk,
            .window = s.settings.span.seconds(),
            .icon = "internaldrive",
            .title = "Disk",
            .value = fmt.own(c.alloc(), fmt.rate(&b[0], smp.disk_read_bps + smp.disk_write_bps)),
            .detail = c.print("read {s} · write {s}", .{ fmt.rate(&b[1], smp.disk_read_bps), fmt.rate(&b[2], smp.disk_write_bps) }),
            .history = &h.disk_read,
            .second = &h.disk_write,
            .floor = 256 * 1024,
        } },
        .{ .page = .network, .t = .{
            .key = "tile-network",
            .color = k.network,
            .window = s.settings.span.seconds(),
            .icon = "network",
            .title = "Network",
            .value = fmt.own(c.alloc(), fmt.rate(&b[3], smp.net_in_bps + smp.net_out_bps)),
            .detail = c.print("↓ {s} · ↑ {s}", .{ fmt.rate(&b[1], smp.net_in_bps), fmt.rate(&b[2], smp.net_out_bps) }),
            .history = &h.net_in,
            .second = &h.net_out,
            .floor = 64 * 1024,
        } },
    };
    for (tiles) |it| {
        const t = tile.draw(c, k, it.t, s.page == it.page);
        if (t.pressed) s.openFromSidebar(it.page, t.id);
        s.nav_ids.set(it.page, t.id);
    }
}
