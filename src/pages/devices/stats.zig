//! The figures under a device's chart: labelled values, cards of rows,
//! the cores, the memory split, the disks, filesystems and interfaces.
//! Rows are walked by pointer into the sample, which lasts the whole frame:
//! a copy's names would be gone before the text is drawn.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const fmt = core.fmt;
const app = @import("../../app/state.zig");
const theme = @import("../../ui/theme.zig");
const charts = @import("../../ui/charts.zig");

const State = app.State;

pub fn stat(c: *ui.Context, k: theme.Colors, label: []const u8, value: []const u8) void {
    ui.key(c, label);
    const col = ui.div(c).column().gap(2);
    defer col.end();
    ui.text(c, label, .{ .size = 11.5, .color = k.secondary });
    ui.text(c, value, .{ .size = 20, .weight = .semibold, .color = k.text });
}

/// A row of stats.
pub fn stats(c: *ui.Context) ui.Div {
    return ui.div(c).row().wFull().gap(28);
}

/// A titled card of rows; end it after the last.
pub fn card(c: *ui.Context, k: theme.Colors, title: []const u8) ui.Div {
    ui.key(c, title);
    ui.text(c, title, .{ .size = 12.5, .weight = .semibold, .color = k.secondary });
    return ui.div(c).column().wFull().rounded(12).bg(k.panel).border(k.separator).clip();
}

/// A line in a card: a name on the left, values on the right.
pub fn line(c: *ui.Context, k: theme.Colors, key: []const u8, first: bool) ui.Div {
    ui.key(c, key);
    if (!first) _ = c.leaf(.{ .width = .fill, .height = .{ .px = 1 }, .background = k.separator }, .none, null);
    return ui.div(c).row().wFull().px(16).py(10).itemsCenter().gap(16);
}

/// A thin bar `fraction` full.
pub fn bar(c: *ui.Context, k: theme.Colors, fraction: f32, color: ui.Color, width: f32) void {
    const track = ui.div(c).row().w(width).h(6).rounded(3).bg(k.stripe).clip();
    defer track.end();
    _ = c.leaf(.{ .width = .{ .px = @max(0, @min(1, fraction)) * width }, .height = .fill, .background = color, .radius = 3 }, .none, null);
}

/// How often tasks had to wait for this resource lately, as a person reads it.
pub fn waiting(c: *ui.Context, k: theme.Colors, s: *const State, some: f32) void {
    if (!s.sample.devices.pressure.known) return;
    stat(c, k, "Waiting", c.print("{d:.1}%", .{some}));
}

pub fn cpu(c: *ui.Context, s: *State, k: theme.Colors) void {
    const d = &s.sample.devices;
    var b: [4][32]u8 = undefined;
    {
        const r = stats(c);
        defer r.end();
        stat(c, k, "Utilization", fmt.own(c.alloc(), fmt.percent(&b[0], s.sample.cpu_pct)));
        stat(c, k, "Processes", c.print("{d}", .{s.sample.process_count}));
        stat(c, k, "Threads", c.print("{d}", .{s.sample.threads}));
        stat(c, k, "Up time", fmt.own(c.alloc(), fmt.duration(&b[1], s.sample.uptime)));
        stat(c, k, "Load", c.print("{d:.2}  {d:.2}  {d:.2}", .{ s.sample.load[0], s.sample.load[1], s.sample.load[2] }));
        waiting(c, k, s, d.pressure.cpu);
    }
    ui.text(c, "Cores", .{ .size = 12.5, .weight = .semibold, .color = k.secondary });
    {
        // Rows of up to 16, so many cores stay readable.
        const per_row = 16;
        const cores = s.sample.cores;
        var start: usize = 0;
        while (start < cores.len) : (start += per_row) {
            ui.key(c, c.print("cores{d}", .{start}));
            const grid = ui.div(c).row().wFull().gap(6).itemsEnd();
            defer grid.end();
            for (start..@min(cores.len, start + per_row)) |i| coreBar(c, k, i, cores[i], if (i < d.coreMhz().len) d.coreMhz()[i] else 0);
            for (@min(cores.len, start + per_row)..start + per_row) |i| {
                if (cores.len <= per_row) break;
                ui.key(c, c.print("gap{d}", .{i}));
                const gap = ui.div(c).grow().w(0);
                gap.end();
            }
        }
    }
    if (d.sensor_count > 0) {
        const g = card(c, k, "Temperatures");
        defer g.end();
        for (d.sensorList(), 0..) |*t, i| {
            const r = line(c, k, t.label.slice(), i == 0);
            defer r.end();
            ui.text(c, t.label.slice(), .{ .size = 13, .color = k.text });
            ui.spacer(c);
            ui.text(c, c.print("{d:.0} °C", .{t.celsius}), .{ .size = 13, .weight = .medium, .color = if (t.celsius >= 85) k.danger else k.text, .tabular = true });
        }
    }
}

fn coreBar(c: *ui.Context, k: theme.Colors, i: usize, v: f32, mhz: u32) void {
    ui.key(c, c.print("core{d}", .{i}));
    const col = ui.div(c).column().grow().w(0).gap(4).itemsCenter();
    defer col.end();
    var b: [16]u8 = undefined;
    ui.text(c, fmt.own(c.alloc(), fmt.percent(&b, v)), .{ .size = 11, .weight = .medium, .color = k.text, .tabular = true });
    const track = ui.div(c).column().wFull().h(64).justifyEnd().rounded(4).bg(k.panel);
    {
        defer track.end();
        const fill = ui.div(c).wFull().h(@max(2, 64 * v / 100)).rounded(4).bg(k.cpu);
        fill.end();
    }
    ui.text(c, if (mhz > 0) c.print("{d:.1} GHz", .{@as(f32, @floatFromInt(mhz)) / 1000}) else c.print("{d}", .{i}), .{ .size = 10.5, .color = k.secondary, .tabular = true });
}

pub fn memory(c: *ui.Context, s: *State, k: theme.Colors) void {
    const m = s.sample.memory;
    const d = &s.sample.devices;
    var b: [5][32]u8 = undefined;
    {
        const r = stats(c);
        defer r.end();
        stat(c, k, "In use", fmt.own(c.alloc(), fmt.bytes(&b[0], m.used())));
        stat(c, k, "Available", fmt.own(c.alloc(), fmt.bytes(&b[1], m.available)));
        stat(c, k, "Cached", fmt.own(c.alloc(), fmt.bytes(&b[2], m.cached)));
        stat(c, k, "Shared", fmt.own(c.alloc(), fmt.bytes(&b[3], m.shmem)));
        waiting(c, k, s, d.pressure.memory);
    }
    // In use, then what the cache holds (given back when needed), then free.
    if (m.total > 0) {
        const total: f32 = @floatFromInt(m.total);
        const used = @as(f32, @floatFromInt(m.used())) / total;
        const cached = @as(f32, @floatFromInt(@min(m.cached, m.available))) / total;
        const split = ui.div(c).row().wFull().h(14).rounded(5).bg(k.stripe).clip();
        {
            defer split.end();
            _ = c.leaf(.{ .width = .{ .px = 0 }, .grow = used, .height = .fill, .background = k.memory }, .none, null);
            _ = c.leaf(.{ .width = .{ .px = 0 }, .grow = cached, .height = .fill, .background = k.memory.alpha(0.4) }, .none, null);
            _ = c.leaf(.{ .width = .{ .px = 0 }, .grow = @max(0.0001, 1 - used - cached), .height = .fill }, .none, null);
        }
        const legend = ui.div(c).row().gap(18).itemsCenter();
        defer legend.end();
        swatch(c, k, k.memory, "In use");
        swatch(c, k, k.memory.alpha(0.4), "Cache, given back when needed");
        swatch(c, k, k.stripe, "Free");
    }
    if (m.swap_total > 0) {
        const g = card(c, k, "Swap");
        defer g.end();
        const inner = ui.div(c).column().wFull().p(16).gap(10);
        defer inner.end();
        ui.text(c, c.print("{s} of {s} in use", .{ fmt.bytes(&b[0], m.swapUsed()), fmt.bytes(&b[1], m.swap_total) }), .{ .size = 13, .color = k.text });
        charts.area(c, &s.sample.history.swap, .{ .height = 70, .max = 100, .window = s.settings.span.seconds(), .color = k.memory, .grid = k.separator, .grid_lines = 1 });
    }
}

fn swatch(c: *ui.Context, k: theme.Colors, color: ui.Color, label: []const u8) void {
    ui.key(c, label);
    const r = ui.div(c).row().gap(6).itemsCenter();
    defer r.end();
    _ = c.leaf(.{ .width = .{ .px = 10 }, .height = .{ .px = 10 }, .background = color, .radius = 3 }, .none, null);
    ui.text(c, label, .{ .size = 12, .color = k.secondary });
}

pub fn disk(c: *ui.Context, s: *State, k: theme.Colors) void {
    const d = &s.sample.devices;
    var b: [4][24]u8 = undefined;
    {
        const r = stats(c);
        defer r.end();
        stat(c, k, "Read", fmt.own(c.alloc(), fmt.rate(&b[0], s.sample.disk_read_bps)));
        stat(c, k, "Write", fmt.own(c.alloc(), fmt.rate(&b[1], s.sample.disk_write_bps)));
        waiting(c, k, s, d.pressure.io);
    }
    if (d.disk_count > 0) {
        const g = card(c, k, "Disks");
        defer g.end();
        for (d.diskList(), 0..) |*x, i| {
            const r = line(c, k, x.name.slice(), i == 0);
            defer r.end();
            ui.text(c, x.name.slice(), .{ .size = 13, .weight = .medium, .color = k.text });
            ui.spacer(c);
            ui.text(c, c.print("read {s} · write {s}", .{ fmt.rate(&b[0], x.read_bps), fmt.rate(&b[1], x.write_bps) }), .{ .size = 12.5, .color = k.secondary, .tabular = true });
            bar(c, k, x.busy / 100, k.disk, 80);
            ui.text(c, c.print("{d:.0}% busy", .{x.busy}), .{ .size = 12.5, .color = k.text, .tabular = true });
        }
    }
    if (d.filesystem_count > 0) {
        const g = card(c, k, "Space");
        defer g.end();
        for (d.filesystemList(), 0..) |*f, i| {
            const r = line(c, k, f.mount.slice(), i == 0);
            defer r.end();
            {
                const words = ui.div(c).column().grow().w(0).gap(2);
                defer words.end();
                ui.text(c, f.mount.slice(), .{ .size = 13, .weight = .medium, .color = k.text });
                ui.text(c, f.kind.slice(), .{ .size = 11.5, .color = k.secondary });
            }
            const frac: f32 = if (f.total > 0) @as(f32, @floatFromInt(f.used())) / @as(f32, @floatFromInt(f.total)) else 0;
            bar(c, k, frac, if (frac > 0.9) k.danger else k.disk, 140);
            ui.text(c, c.print("{s} free of {s}", .{ fmt.bytes(&b[2], f.free), fmt.bytes(&b[3], f.total) }), .{ .size = 12.5, .color = k.text, .tabular = true });
        }
    }
}

pub fn network(c: *ui.Context, s: *State, k: theme.Colors) void {
    const d = &s.sample.devices;
    var b: [2][24]u8 = undefined;
    {
        const r = stats(c);
        defer r.end();
        stat(c, k, "Download", fmt.own(c.alloc(), fmt.rate(&b[0], s.sample.net_in_bps)));
        stat(c, k, "Upload", fmt.own(c.alloc(), fmt.rate(&b[1], s.sample.net_out_bps)));
    }
    if (d.interface_count > 0) {
        const g = card(c, k, "Interfaces");
        defer g.end();
        for (d.interfaceList(), 0..) |*f, i| {
            const r = line(c, k, f.name.slice(), i == 0);
            defer r.end();
            {
                const words = ui.div(c).column().grow().w(0).gap(2);
                defer words.end();
                ui.text(c, f.name.slice(), .{ .size = 13, .weight = .medium, .color = k.text });
                const where = f.address.slice();
                ui.text(c, if (f.speed > 0)
                    c.print("{s}{s}{d} Mb/s link", .{ where, if (where.len > 0) " · " else "", f.speed })
                else if (where.len > 0) where else "No address", .{ .size = 11.5, .color = k.secondary });
            }
            ui.text(c, c.print("↓ {s}", .{fmt.rate(&b[0], f.rx_bps)}), .{ .size = 12.5, .color = k.text, .tabular = true });
            ui.text(c, c.print("↑ {s}", .{fmt.rate(&b[1], f.tx_bps)}), .{ .size = 12.5, .color = k.secondary, .tabular = true });
        }
    }
}

pub fn battery(c: *ui.Context, s: *State, k: theme.Colors) void {
    const bt = s.sample.devices.battery;
    var b: [2][32]u8 = undefined;
    const r = stats(c);
    defer r.end();
    stat(c, k, "Charge", c.print("{d:.0}%", .{bt.percent}));
    stat(c, k, "Status", statusWord(bt));
    if (bt.watts > 0) stat(c, k, if (bt.charging) "Charging at" else "Drawing", c.print("{d:.1} W", .{bt.watts}));
    if (bt.seconds_left > 0) stat(c, k, if (bt.charging) "Until full" else "Time left", fmt.own(c.alloc(), fmt.duration(&b[0], bt.seconds_left)));
}

pub fn statusWord(bt: core.devices.Battery) []const u8 {
    if (bt.full) return "Full";
    if (bt.charging) return "Charging";
    return "On battery";
}
