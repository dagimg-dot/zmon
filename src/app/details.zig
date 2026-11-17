//! The details pane beside Apps and Processes (Ctrl+I): everything about the
//! selected process that doesn't fit a row, its command line included. The
//! worker reads it for the selection only (system/sampler/linux/details.zig),
//! and nothing here is logged or saved.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const fmt = core.fmt;
const app = @import("state.zig");
const theme = @import("../ui/theme.zig");
const controls = @import("../ui/controls.zig");
const app_icon = @import("../ui/app_icon.zig");
const shortcut = @import("../ui/shortcut.zig");

const State = app.State;
/// The pane's width when it hasn't been dragged, and the least and the
/// room it must leave the list.
pub const default_width = 320;
pub const min_width = 260;
pub const list_keeps = 420;

/// The widest the pane may be in a window `window_w` wide beside a sidebar
/// `sidebar_w` wide.
pub fn maxWidth(window_w: f32, sidebar_w: f32) f32 {
    return @max(min_width, window_w - sidebar_w - list_keeps);
}

/// The edge between the list and the pane: drag it to resize the pane,
/// double-click it for the default width. A screen reader steps it.
pub fn edge(c: *ui.Context, s: *State, k: theme.Colors, sidebar_w: f32) void {
    ui.key(c, "details-edge");
    const d = ui.div(c).row().w(7).hFull().justifyCenter();
    defer d.end();
    c.adjustable(d.index, .{ .role = .splitter, .label = "Details width", .value = c.print("{d} points", .{s.settings.details_width}) });
    const it = c.interact(d.index, .{});
    const dragging = s.edge_drag != null;
    if (it.hovered or dragging) c.cursor = .resize_left_right;
    const most = maxWidth(c.size.w, sidebar_w);
    if (it.double_clicked) {
        s.settings.details_width = default_width;
        s.edge_drag = null;
        s.save();
    } else if (it.pressed and !dragging) {
        s.edge_drag = .{ .x = c.input.mouse.x, .width = @floatFromInt(s.settings.details_width) };
    } else if (s.edge_drag) |drag| {
        if (!c.input.down) {
            s.edge_drag = null;
            s.save(); // once, when let go
        } else {
            // The pane is on the right: moving left widens it.
            const w = std.math.clamp(drag.width - (c.input.mouse.x - drag.x), min_width, most);
            s.settings.details_width = @intFromFloat(w);
            c.changed = true;
        }
    }
    if (it.a11y_step != 0) {
        const w = std.math.clamp(@as(f32, @floatFromInt(s.settings.details_width)) - @as(f32, @floatFromInt(it.a11y_step)) * 20, min_width, most);
        s.settings.details_width = @intFromFloat(w);
        s.save();
    }
    _ = c.leaf(.{ .width = .{ .px = 1 }, .height = .fill, .background = if (it.hovered or dragging) k.accent else k.separator }, .none, null);
}

pub fn pane(c: *ui.Context, s: *State, k: theme.Colors) void {
    ui.key(c, "details-pane");
    // A window made narrower since the last drag still leaves the list room.
    const sidebar_w: f32 = if (c.size.w < @import("sidebar.zig").compact_below) 76 else 236;
    const w = @min(@as(f32, @floatFromInt(s.settings.details_width)), maxWidth(c.size.w, sidebar_w));
    const box = ui.div(c).column().w(w).hFull().bg(k.panel).scrollY();
    defer box.end();
    const col = ui.div(c).column().wFull().px(18).py(16).gap(14);
    defer col.end();
    const target = s.detailTarget() orelse return empty(c, s, k, "Select an app or a process to see its details.");
    const p = s.sample.find(target.pid) orelse return empty(c, s, k, "It has ended.");
    const group = s.selectedGroup();
    header(c, s, k, p.*, group);
    // A pointer into the sample, not a copy: the socket lines are kept
    // inline, and text drawn after this returns must still be there.
    const d: ?*const core.Details = if (s.sample.detail) |*x| (if (x.pid == p.pid and x.start == p.start) x else null) else null;
    if (d) |x| if (x.cmdline.len > 0) commandLine(c, k, x.cmdline);
    var b: [6][32]u8 = undefined;
    why(c, s, k, p.*, d);
    section(c, k, "Process");
    {
        const rows = ui.div(c).column().wFull().gap(7);
        defer rows.end();
        line(c, k, "User", s.userName(&b[0], p.uid));
        line(c, k, "State", stateWord(p.state));
        line(c, k, "Priority", c.print("{d}{s}", .{ p.nice, niceWord(p.nice) }));
        if (s.sample.hz > 0 and s.sample.uptime > 0) {
            const age = s.sample.uptime - @as(f64, @floatFromInt(p.start)) / @as(f64, @floatFromInt(s.sample.hz));
            line(c, k, "Started", c.print("{s} ago", .{fmt.duration(&b[1], @max(0, age))}));
            line(c, k, "CPU time", fmt.own(c.alloc(), fmt.duration(&b[2], @as(f64, @floatFromInt(p.cpu_ticks)) / @as(f64, @floatFromInt(s.sample.hz)))));
        }
        if (s.sample.find(p.ppid)) |parent| {
            line(c, k, "Parent", c.print("{s} ({d})", .{ parent.name, parent.pid }));
        } else if (p.ppid > 0) line(c, k, "Parent", c.print("{d}", .{p.ppid}));
        line(c, k, "Threads", c.print("{d}", .{p.threads}));
        line(c, k, "Memory", fmt.own(c.alloc(), fmt.bytes(&b[3], p.memory)));
        if (d) |x| if (x.io_known) {
            line(c, k, "Read", fmt.own(c.alloc(), fmt.bytes(&b[4], x.read_total)));
            line(c, k, "Written", fmt.own(c.alloc(), fmt.bytes(&b[5], x.write_total)));
        };
        if (group) |g| line(c, k, "Processes", c.print("{d}", .{g.members.len}));
    }
    section(c, k, "Where");
    {
        const rows = ui.div(c).column().wFull().gap(10);
        defer rows.end();
        if (p.exe.len > 0) path(c, k, "Program", p.exe) else if (p.program.len > 0) path(c, k, "Program", p.program);
        if (d) |x| {
            if (x.cwd.len > 0) path(c, k, "Working folder", x.cwd);
            if (x.cgroup.len > 0) path(c, k, "Control group", x.cgroup);
        }
    }
}

/// Why it is running, as witr asks it: the parents that started it, what
/// keeps it running, what it works on and holds open, and anything amiss.
fn why(c: *ui.Context, s: *State, k: theme.Colors, p: core.Proc, d: ?*const core.Details) void {
    section(c, k, "Why it's running");
    const rows = ui.div(c).column().wFull().gap(10);
    defer rows.end();
    // The chain from the first process down to this one.
    var chain: [12]*const core.Proc = undefined;
    var n: usize = 0;
    var at: ?*const core.Proc = s.sample.find(p.pid);
    while (at) |q| {
        if (n == chain.len) break;
        chain[n] = q;
        n += 1;
        if (q.ppid <= 0) break;
        at = s.sample.find(q.ppid);
    }
    {
        var w: std.Io.Writer.Allocating = .init(c.alloc());
        var i = n;
        while (i > 0) {
            i -= 1;
            w.writer.print("{s}{s} ({d})", .{ if (i + 1 < n) " → " else "", chain[i].name, chain[i].pid }) catch {};
        }
        path(c, k, "Started by", w.written());
    }
    if (source(c, p, chain[0..n], d)) |text| path(c, k, "Kept running by", text);
    if (d) |x| {
        if (x.unit_file.len > 0) path(c, k, "Unit file", x.unit_file);
        if (x.repo.len > 0) path(c, k, "Working on", if (x.branch.len > 0) c.print("{s}, branch {s}", .{ x.repo, x.branch }) else x.repo);
        if (x.sockets_known) {
            if (x.socket_count > 0) {
                const col = ui.div(c).column().wFull().gap(3);
                defer col.end();
                ui.text(c, "Network", .{ .size = 12.5, .color = k.secondary });
                for (x.sockets[0..x.socket_count], 0..) |*sock, i| {
                    ui.key(c, c.print("sock{d}", .{i}));
                    ui.text(c, c.print("{s} {s} {s}", .{ if (sock.listening) "Listening on" else "Connected", sock.text.slice(), sock.proto.slice() }), .{ .size = 12.5, .color = k.text, .wrap = true });
                }
            }
        } else if (!p.kthread) path(c, k, "Network", "Only your own processes' connections can be read.");
    }
    // What is worth knowing at a glance.
    if (p.uid == 0 and !p.kthread) warning(c, k, "Runs as root: it can change anything on this machine.");
    if (p.exe_replaced) warning(c, k, "Its program was updated after it started: it runs the old one until restarted.");
    if (p.state == 'Z') warning(c, k, "It has ended, but the process that started it hasn't collected it yet.");
}

/// What keeps it running, in words: its systemd unit, container, session or
/// whatever its parents say.
fn source(c: *ui.Context, p: core.Proc, chain: []const *const core.Proc, d: ?*const core.Details) ?[]const u8 {
    if (p.kthread) return "The kernel itself: this is one of its own threads.";
    const grouping = @import("zmon-system").apps.grouping;
    const described = if (d) |x| x.unit_description else "";
    switch (grouping.classify(p.unit)) {
        .app => |id| return c.print("The desktop, which started it as an app ({s})", .{id}),
        .service => |name| {
            for ([_][2][]const u8{ .{ "docker-", "A Docker container" }, .{ "libpod-", "A Podman container" } }) |kind| {
                if (std.mem.startsWith(u8, name, kind[0])) return c.print("{s} ({s})", .{ kind[1], name[kind[0].len..@min(name.len, kind[0].len + 12)] });
            }
            return if (described.len > 0) c.print("The service {s}: {s}", .{ p.unit, described }) else c.print("The service {s}", .{p.unit});
        },
        .none => {},
    }
    for (chain) |q| {
        if (std.mem.eql(u8, q.comm, "sshd")) return "A remote login over SSH";
        if (std.mem.eql(u8, q.comm, "cron") or std.mem.eql(u8, q.comm, "crond")) return "A scheduled job (cron)";
    }
    if (std.mem.startsWith(u8, p.unit, "session-")) return "Your login session";
    if (std.mem.startsWith(u8, p.unit, "user@")) return "Your user's service manager";
    return null;
}

fn warning(c: *ui.Context, k: theme.Colors, text: []const u8) void {
    ui.key(c, text);
    const r = ui.div(c).row().wFull().gap(8).p(10).rounded(8).bg(k.danger.alpha(0.12));
    defer r.end();
    ui.icon(c, "exclamationmark.triangle", .{ .size = 13, .frame = 16, .color = k.danger });
    const words = ui.div(c).column().grow();
    defer words.end();
    ui.text(c, text, .{ .size = 12.5, .color = k.text, .wrap = true });
}

fn empty(c: *ui.Context, s: *State, k: theme.Colors, message: []const u8) void {
    {
        const r = ui.div(c).row().wFull().itemsCenter();
        defer r.end();
        ui.text(c, "Details", .{ .size = 15, .weight = .semibold, .color = k.text });
        ui.spacer(c);
        closeButton(c, s, k);
    }
    ui.text(c, message, .{ .size = 12.5, .color = k.secondary, .wrap = true });
}

/// The pane's ✕, for whoever doesn't use Ctrl+I: its tooltip teaches it.
fn closeButton(c: *ui.Context, s: *State, k: theme.Colors) void {
    if (controls.button(c, k, "Close details", .{ .icon = "xmark", .compact = true, .quiet = true, .shortcut = shortcut.details })) s.details_open = false;
}

fn header(c: *ui.Context, s: *State, k: theme.Colors, p: core.Proc, group: ?*const @import("zmon-system").apps.Group) void {
    const r = ui.div(c).row().wFull().gap(10).itemsCenter();
    defer r.end();
    if (s.ownerOf(indexOf(s, p.pid))) |g| app_icon.draw(c, &s.icons, k, g.*);
    const words = ui.div(c).column().grow().gap(2);
    ui.text(c, if (group) |g| g.name else p.name, .{ .size = 15, .weight = .semibold, .color = k.text, .wrap = true });
    const note = if (p.program.len > 0 and !std.mem.eql(u8, p.program, p.name)) c.print("{s} · process {d}", .{ p.program, p.pid }) else c.print("Process {d}", .{p.pid});
    ui.text(c, note, .{ .size = 12, .color = k.secondary, .wrap = true });
    words.end();
    closeButton(c, s, k);
}

fn indexOf(s: *const State, pid: i32) u32 {
    for (s.sample.procs, 0..) |p, i| if (p.pid == pid) return @intCast(i);
    return std.math.maxInt(u32);
}

fn commandLine(c: *ui.Context, k: theme.Colors, cmdline: []const u8) void {
    const head = ui.div(c).row().wFull().itemsCenter();
    {
        defer head.end();
        ui.text(c, "Command line", .{ .size = 11.5, .weight = .semibold, .color = k.secondary });
        ui.spacer(c);
        if (controls.button(c, k, "Copy", .{ .hint = "Copies the command line" })) c.clipboard.write(c.clipboard.ctx, cmdline);
    }
    const box = ui.div(c).column().wFull().p(10).rounded(8).bg(k.stripe).border(k.separator);
    defer box.end();
    ui.text(c, cmdline, .{ .size = 12, .color = k.text, .wrap = true });
}

fn section(c: *ui.Context, k: theme.Colors, title: []const u8) void {
    ui.key(c, title);
    const r = ui.div(c).row().wFull().pt(4);
    defer r.end();
    ui.text(c, title, .{ .size = 11.5, .weight = .semibold, .color = k.secondary });
}

fn line(c: *ui.Context, k: theme.Colors, label: []const u8, value: []const u8) void {
    ui.key(c, label);
    const r = ui.div(c).row().wFull().gap(12);
    defer r.end();
    {
        const l = ui.div(c).w(92);
        defer l.end();
        ui.text(c, label, .{ .size = 12.5, .color = k.secondary });
    }
    const v = ui.div(c).column().grow();
    defer v.end();
    ui.text(c, value, .{ .size = 12.5, .color = k.text, .wrap = true });
}

/// A path on its own lines: label above, so long paths wrap whole.
fn path(c: *ui.Context, k: theme.Colors, label: []const u8, value: []const u8) void {
    ui.key(c, label);
    const r = ui.div(c).column().wFull().gap(3);
    defer r.end();
    ui.text(c, label, .{ .size = 12.5, .color = k.secondary });
    ui.text(c, value, .{ .size = 12.5, .color = k.text, .wrap = true });
}

/// What the kernel's one-letter state means.
pub fn stateWord(state: u8) []const u8 {
    return switch (state) {
        'R' => "Running",
        'S' => "Sleeping",
        'D' => "Waiting for the disk",
        'T' => "Stopped",
        't' => "Stopped by a debugger",
        'Z' => "Ended, not yet collected",
        'X' => "Ended",
        'I' => "Idle",
        'P' => "Parked",
        else => "Unknown",
    };
}

fn niceWord(nice: i8) []const u8 {
    if (nice < 0) return " (favoured)";
    if (nice > 0) return " (yields to others)";
    return " (normal)";
}

test "every state the kernel reports has words" {
    for ("RSDTtZXIP") |ch| try std.testing.expect(!std.mem.eql(u8, stateWord(ch), "Unknown"));
}
