//! What the details pane shows of one process, read when it is selected:
//! the command line, working folder, control group and I/O totals.
const std = @import("std");
const core = @import("zmon-core");
const files = @import("../../platform/root.zig").files;
const process = @import("process.zig");

pub const Details = core.Details;

/// The details of `pid`, if it is still the process that started at `start`.
/// Text is copied into `a`. Another user's working folder and I/O totals are
/// refused by the kernel and left empty.
pub fn read(io: std.Io, a: std.mem.Allocator, pid: i32, start: u64) ?Details {
    var dir = std.Io.Dir.cwd().openDir(io, "/proc", .{}) catch return null;
    defer dir.close(io);
    var path: [64]u8 = undefined;
    var buf: [8192]u8 = undefined;
    const st_text = files.read(io, dir, std.fmt.bufPrint(&path, "{d}/stat", .{pid}) catch return null, &buf) catch return null;
    const st = process.parseStat(st_text) orelse return null;
    if (st.start != start) return null;
    var d: Details = .{ .pid = pid, .start = start };
    if (files.read(io, dir, std.fmt.bufPrint(&path, "{d}/cmdline", .{pid}) catch return d, &buf)) |cmd| {
        d.cmdline = a.dupe(u8, joinArgs(cmd)) catch "";
    } else |_| {}
    var link_buf: [1024]u8 = undefined;
    if (files.link(io, dir, std.fmt.bufPrint(&path, "{d}/cwd", .{pid}) catch return d, &link_buf)) |cwd| {
        d.cwd = a.dupe(u8, cwd) catch "";
    }
    if (files.read(io, dir, std.fmt.bufPrint(&path, "{d}/cgroup", .{pid}) catch return d, &buf)) |cg| {
        d.cgroup = a.dupe(u8, unifiedGroup(cg)) catch "";
    } else |_| {}
    if (files.read(io, dir, std.fmt.bufPrint(&path, "{d}/io", .{pid}) catch return d, &buf)) |text| {
        d.read_total = core.text.field(text, "read_bytes:");
        d.write_total = core.text.field(text, "write_bytes:");
        d.io_known = true;
    } else |_| {}
    return d;
}

/// The arguments as one line: the kernel separates them with NULs.
/// Rewrites `cmd` in place.
pub fn joinArgs(cmd: []u8) []const u8 {
    const text = std.mem.trimEnd(u8, cmd, "\x00");
    for (@constCast(text)) |*ch| {
        if (ch.* == 0) ch.* = ' ';
    }
    return text;
}

/// The path in the unified (v2) hierarchy: the "0::" line of /proc/<pid>/cgroup.
pub fn unifiedGroup(text: []const u8) []const u8 {
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "0::")) return line[3..];
    }
    return "";
}

test "a command line's arguments are joined with spaces" {
    var cmd = "/usr/bin/node\x00server.js\x00--port\x003000\x00".*;
    try std.testing.expectEqualStrings("/usr/bin/node server.js --port 3000", joinArgs(&cmd));
}

test "the unified control group is the 0:: line" {
    try std.testing.expectEqualStrings("/user.slice/user-1000.slice/user@1000.service/app.slice/app-niri-ghostty-1.scope", unifiedGroup("0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-niri-ghostty-1.scope\n"));
    try std.testing.expectEqualStrings("", unifiedGroup("12:pids:/foo\n"));
}

test "this test's own details can be read, and a wrong start time reads nothing" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const me = std.os.linux.getpid();
    var buf: [1024]u8 = undefined;
    var path: [32]u8 = undefined;
    const st = process.parseStat(try files.read(std.testing.io, .cwd(), try std.fmt.bufPrint(&path, "/proc/{d}/stat", .{me}), &buf)).?;
    const d = read(std.testing.io, arena.allocator(), me, st.start) orelse return error.NoDetails;
    try std.testing.expect(d.cmdline.len > 0);
    try std.testing.expect(d.io_known);
    try std.testing.expect(read(std.testing.io, arena.allocator(), me, st.start + 1) == null);
}
