//! The sidebar: the pages first, then a live tile for each device, as GNOME's
//! Resources and Mission Center lay it out. A tile opens that device's page.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const fmt = core.fmt;
const state = @import("state.zig");
const theme = @import("../ui/theme.zig");
const tile = @import("../ui/tile.zig");
const stats = @import("../pages/devices/stats.zig");
const controls = @import("../ui/controls.zig");
const app_icon = @import("../ui/icon.zig");

const shortcut = @import("../ui/shortcut.zig");

const State = state.State;

/// The shortcut that opens a page, shown when its entry is hovered.
fn pageShortcut(page: Page) ?shortcut.Shortcut {
    return switch (page) {
        .apps => shortcut.apps,
        .processes => shortcut.processes,
        .cpu => shortcut.cpu,
        .memory => shortcut.memory,
        .disk => shortcut.disk,
        .network => shortcut.network,
        .settings => shortcut.settings,
        .battery => null,
    };
}
const Page = state.Page;

/// Below this window width the sidebar keeps only its icons and values.
pub const compact_below = 1000;

/// Only icons and values: collapsed by the user, or a window too narrow for more.
pub fn compact(c: *const ui.Context, s: *const State) bool {
    return s.settings.sidebar_collapsed or c.size.w < compact_below;
}

pub fn width(c: *const ui.Context, s: *const State) f32 {
    return if (compact(c, s)) 76 else 236;
}

pub fn draw(c: *ui.Context, s: *State, k: theme.Colors) void {
    const narrow = compact(c, s);
    const side = ui.div(c).column().w(width(c, s)).hFull().bg(k.panel).px(10).py(10).gap(4).scrollY();
    defer side.end();
    if (narrow) return drawCompact(c, s, k);
    {
        // The icon's corner sits as far from the top as from the left (20), in
        // line with the page icons below it.
        const head = ui.div(c).row().wFull().pl(10).pt(8).pb(8).itemsCenter().gap(10);
        defer head.end();
        app_icon.draw(c, 22);
        ui.text(c, "zmon", .{ .size = 17, .weight = .bold, .color = k.text });
        ui.spacer(c);
        collapseButton(c, s, k);
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
    if (s.paused) {
        ui.text(c, "Paused · Ctrl+Shift+P resumes", .{ .size = 11, .weight = .semibold, .color = k.accent });
    } else ui.text(c, c.print("Up {s} · load {d:.1}", .{ fmt.duration(&b[0], s.sample.uptime), s.sample.load[0] }), .{ .size = 11, .color = k.tertiary });
}

/// The narrow sidebar: the same pages and devices, icons and live values only.
fn drawCompact(c: *ui.Context, s: *State, k: theme.Colors) void {
    expandButton(c, s, k);
    navCompact(c, s, k, .apps, "Apps", "square.grid.2x2", "", "");
    navCompact(c, s, k, .processes, "Processes", "waveform.path.ecg", "", "");
    section(c, k, "");
    const smp = s.sample;
    const a = c.alloc();
    var b: [4][16]u8 = undefined;
    const cpu = fmt.own(a, fmt.percent(&b[0], smp.cpu_pct));
    const mem = fmt.own(a, fmt.percent(&b[1], smp.history.memory.at(smp.history.memory.len -| 1)));
    const disk = smp.disk_read_bps + smp.disk_write_bps;
    const net = smp.net_in_bps + smp.net_out_bps;
    navCompact(c, s, k, .cpu, "CPU", "cpu", cpu, cpu);
    navCompact(c, s, k, .memory, "Memory", "memorychip", mem, mem);
    navCompact(c, s, k, .disk, "Disk", "internaldrive", fmt.own(a, fmt.rateShort(&b[2], disk)), fmt.own(a, fmt.rate(&b[3], disk)));
    navCompact(c, s, k, .network, "Network", "network", fmt.own(a, fmt.rateShort(&b[0], net)), fmt.own(a, fmt.rate(&b[1], net)));
    if (smp.devices.battery.present) {
        const bt = c.print("{d:.0}%", .{smp.devices.battery.percent});
        navCompact(c, s, k, .battery, "Battery", "", bt, bt);
    }
    ui.spacer(c);
    navCompact(c, s, k, .settings, "Settings", "gearshape", "", "");
}

/// The quiet sidebar icon beside the name that collapses the sidebar.
fn collapseButton(c: *ui.Context, s: *State, k: theme.Colors) void {
    ui.key(c, "collapse-sidebar");
    const b = shortcut.tooltip(c, ui.div(c).row().size(26, 26).itemsCenter().justifyCenter().rounded(7).control(), k, "Collapse sidebar", shortcut.sidebar);
    defer b.end();
    const it = c.interact(b.index, .{});
    _ = b.hover(k.hover);
    if (controls.press(c, b, .{ .label = "Collapse sidebar" })) s.toggleSidebar();
    ui.icon(c, "sidebar.left", .{ .size = 14, .frame = 16, .color = if (it.hovered) k.text else k.tertiary });
}

/// The app icon atop the collapsed sidebar, which turns into the sidebar
/// icon when hovered or focused and expands it when pressed. A window too
/// narrow to expand into keeps the plain icon.
fn expandButton(c: *ui.Context, s: *State, k: theme.Colors) void {
    ui.key(c, "expand-sidebar");
    const head = ui.div(c).row().wFull().pt(6).pb(6).justifyCenter();
    defer head.end();
    if (c.size.w < compact_below) {
        const logo = ui.div(c).size(30, 30).itemsCenter().justifyCenter();
        defer logo.end();
        return app_icon.draw(c, 22);
    }
    const b = shortcut.tooltip(c, ui.div(c).row().size(30, 30).itemsCenter().justifyCenter().rounded(8).control(), k, "Expand sidebar", shortcut.sidebar);
    defer b.end();
    const it = c.interact(b.index, .{ .focusable = true });
    _ = b.hover(k.hover);
    if (controls.press(c, b, .{ .label = "Expand sidebar" })) s.toggleSidebar();
    if (it.hovered or (s.keyboard and c.focus == it.id)) {
        ui.icon(c, "sidebar.left", .{ .size = 15, .frame = 18, .color = k.text });
    } else app_icon.draw(c, 22);
}

/// One page as an icon over its live `value`; `said` is the value in full,
/// for its tooltip and a screen reader, where `value` is shortened to fit.
fn navCompact(c: *ui.Context, s: *State, k: theme.Colors, page: Page, label: []const u8, icon: []const u8, value: []const u8, said: []const u8) void {
    ui.key(c, label);
    const on = s.page == page;
    const named = if (said.len > 0) c.print("{s}, {s}", .{ label, said }) else label;
    var row = ui.div(c).column().wFull().py(7).gap(2).itemsCenter().rounded(8).control();
    row = if (pageShortcut(page)) |sc| shortcut.tooltip(c, row, k, named, sc) else row.tooltip(named, .{});
    defer row.end();
    if (on) _ = row.bg(k.selected) else _ = row.hover(k.hover);
    const id = c.interact(row.index, .{}).id;
    s.nav_ids.set(page, id);
    if (controls.press(c, row, .{ .role = .tab, .label = named, .selected = on })) s.openFromSidebar(page, id);
    const ink = if (on) k.selected_text else k.text;
    if (page == .battery) {
        const bt = s.sample.devices.battery;
        tile.batteryIcon(c, k, bt.percent, bt.charging, ink, 20);
    } else ui.icon(c, icon, .{ .size = 15, .frame = 20, .color = ink });
    if (value.len > 0) ui.text(c, value, .{ .size = 10.5, .weight = .semibold, .color = ink, .tabular = true, .truncate = .ellipsis });
}

fn nav(c: *ui.Context, s: *State, k: theme.Colors, page: Page, label: []const u8, icon: []const u8) void {
    ui.key(c, label);
    const on = s.page == page;
    var row = ui.div(c).row().wFull().h(34).px(10).itemsCenter().gap(10).rounded(8).control();
    if (pageShortcut(page)) |sc| row = shortcut.tooltip(c, row, k, label, sc);
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
    const smp = s.sample;
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
            .detail = c.print("{d} cores · {d} processes", .{ smp.cores.len, smp.process_count }),
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
        var with_keys = it.t;
        with_keys.shortcut = pageShortcut(it.page);
        const t = tile.draw(c, k, with_keys, s.page == it.page);
        if (t.pressed) s.openFromSidebar(it.page, t.id);
        s.nav_ids.set(it.page, t.id);
    }
    // A battery only where the machine has one.
    const bt = smp.devices.battery;
    if (bt.present) {
        const t = tile.draw(c, k, .{
            .key = "tile-battery",
            .color = k.success,
            .window = s.settings.span.seconds(),
            .icon = "",
            .battery = .{ .percent = bt.percent, .charging = bt.charging },
            .title = "Battery",
            .value = c.print("{d:.0}%", .{bt.percent}),
            .detail = if (bt.seconds_left > 0) c.print("{s} · {s}", .{ stats.statusWord(bt), fmt.duration(&b[0], bt.seconds_left) }) else stats.statusWord(bt),
            .history = &h.battery,
            .max = 100,
        }, s.page == .battery);
        if (t.pressed) s.openFromSidebar(.battery, t.id);
        s.nav_ids.set(.battery, t.id);
    } else if (s.page == .battery) s.open(.cpu);
}
