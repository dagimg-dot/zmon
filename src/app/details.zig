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

const State = app.State;
pub const width = 320;

pub fn pane(c: *ui.Context, s: *State, k: theme.Colors) void {
    ui.key(c, "details-pane");
    const box = ui.div(c).column().w(width).hFull().bg(k.panel).scrollY();
    defer box.end();
    const col = ui.div(c).column().wFull().px(18).py(16).gap(14);
    defer col.end();
    const target = s.detailTarget() orelse return empty(c, k, "Select an app or a process to see its details.");
    const p = s.sample.find(target.pid) orelse return empty(c, k, "It has ended.");
    const group = s.selectedGroup();
    header(c, s, k, p.*, group);
    const d = if (s.sample.detail) |x| (if (x.pid == p.pid and x.start == p.start) x else null) else null;
    if (d) |x| if (x.cmdline.len > 0) commandLine(c, k, x.cmdline);
    var b: [6][32]u8 = undefined;
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

fn empty(c: *ui.Context, k: theme.Colors, message: []const u8) void {
    ui.text(c, "Details", .{ .size = 15, .weight = .semibold, .color = k.text });
    ui.text(c, message, .{ .size = 12.5, .color = k.secondary, .wrap = true });
}

fn header(c: *ui.Context, s: *State, k: theme.Colors, p: core.Proc, group: ?*const @import("zmon-system").apps.Group) void {
    const r = ui.div(c).row().wFull().gap(10).itemsCenter();
    defer r.end();
    if (s.ownerOf(indexOf(s, p.pid))) |g| app_icon.draw(c, &s.icons, k, g.*);
    const words = ui.div(c).column().grow().gap(2);
    defer words.end();
    ui.text(c, if (group) |g| g.name else p.name, .{ .size = 15, .weight = .semibold, .color = k.text, .wrap = true });
    const note = if (p.program.len > 0 and !std.mem.eql(u8, p.program, p.name)) c.print("{s} · process {d}", .{ p.program, p.pid }) else c.print("Process {d}", .{p.pid});
    ui.text(c, note, .{ .size = 12, .color = k.secondary, .wrap = true });
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
