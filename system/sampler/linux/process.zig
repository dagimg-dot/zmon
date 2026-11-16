//! Every process, from /proc/<pid>/{stat,statm,exe,io,status}. It reports the
//! counters as the kernel keeps them; turning them into rates is the sampler's job.
const std = @import("std");
const core = @import("zmon-core");
const files = @import("../../platform/root.zig").files;
const units = @import("units.zig");
const Proc = core.Proc;

const pf_kthread: u64 = 0x00200000;

pub const Stat = struct {
    comm: []const u8,
    state: u8,
    ppid: i32,
    flags: u64,
    utime: u64,
    stime: u64,
    threads: u32,
    start: u64,
};

/// Parses /proc/<pid>/stat. The name is in parentheses and may itself contain
/// spaces and parentheses, so the fields are counted from its last ")".
pub fn parseStat(text: []const u8) ?Stat {
    const open = std.mem.indexOfScalar(u8, text, '(') orelse return null;
    const close = std.mem.lastIndexOfScalar(u8, text, ')') orelse return null;
    if (close < open) return null;
    var f = std.mem.tokenizeScalar(u8, text[close + 1 ..], ' ');
    var v: [20][]const u8 = undefined;
    for (&v) |*x| x.* = f.next() orelse return null;
    // After the name: state(0) ppid(1) pgrp session tty tpgid flags(6)
    // minflt cminflt majflt cmajflt utime(11) stime(12) cutime cstime
    // priority nice threads(17) itrealvalue starttime(19)
    return .{
        .comm = text[open + 1 .. close],
        .state = v[0][0],
        .ppid = std.fmt.parseInt(i32, v[1], 10) catch return null,
        .flags = std.fmt.parseInt(u64, v[6], 10) catch 0,
        .utime = std.fmt.parseInt(u64, v[11], 10) catch 0,
        .stime = std.fmt.parseInt(u64, v[12], 10) catch 0,
        .threads = std.fmt.parseInt(u32, v[17], 10) catch 1,
        .start = std.fmt.parseInt(u64, v[19], 10) catch 0,
    };
}

/// The executable a /proc/<pid>/exe link names: the kernel marks a file that
/// has been replaced since it started with a " (deleted)" suffix.
pub fn exePath(target: []const u8) []const u8 {
    return std.mem.cutSuffix(u8, target, " (deleted)") orelse target;
}

/// The kernel cuts names at 15 characters; the executable's file name is
/// the whole of it when it starts the same way.
pub fn displayName(comm: []const u8, exe: []const u8) []const u8 {
    if (exe.len == 0) return comm;
    const base = std.fs.path.basename(exe);
    if (base.len > comm.len and std.mem.startsWith(u8, base, comm)) return base;
    return comm;
}

pub const Signal = enum { quit, kill };

pub fn currentUid() u32 {
    return std.os.linux.getuid();
}

pub fn selfPid() i32 {
    return std.os.linux.getpid();
}

/// Sends `sig` to `pid` only if it is still the process that started at
/// `start`: a pid freed since the sample may already belong to another process.
pub fn signal(io: std.Io, pid: i32, start: u64, sig: Signal) bool {
    var buf: [1024]u8 = undefined;
    var path: [32]u8 = undefined;
    const text = files.read(io, .cwd(), std.fmt.bufPrint(&path, "/proc/{d}/stat", .{pid}) catch return false, &buf) catch return false;
    const st = parseStat(text) orelse return false;
    if (st.start != start) return false;
    const linux = std.os.linux;
    return linux.errno(linux.kill(pid, if (sig == .kill) .KILL else .TERM)) == .SUCCESS;
}

/// Walks /proc. It remembers who owns each process, which can't change while
/// the process lives, so /proc/<pid>/status is read once per process.
pub const Reader = struct {
    gpa: std.mem.Allocator,
    page: u64,
    uids: std.AutoHashMapUnmanaged(i32, struct { start: u64, uid: u32 }) = .empty,

    pub fn init(gpa: std.mem.Allocator) Reader {
        return .{ .gpa = gpa, .page = units.pageSize() };
    }

    pub fn deinit(r: *Reader) void {
        r.uids.deinit(r.gpa);
    }

    /// Appends every process to `out`; names and paths are copied into `a`.
    pub fn scan(r: *Reader, io: std.Io, a: std.mem.Allocator, out: *std.ArrayList(Proc)) void {
        var dir = std.Io.Dir.cwd().openDir(io, "/proc", .{ .iterate = true }) catch return;
        defer dir.close(io);
        var it = dir.iterate();
        var buf: [4096]u8 = undefined;
        var path: [64]u8 = undefined;
        var exe_buf: [512]u8 = undefined;
        while (it.next(io) catch null) |entry| {
            const pid = std.fmt.parseInt(i32, entry.name, 10) catch continue;
            const stat_text = files.read(io, dir, std.fmt.bufPrint(&path, "{d}/stat", .{pid}) catch continue, &buf) catch continue;
            const st = parseStat(stat_text) orelse continue;

            // The name points into `buf`, which the next reads reuse: keep a copy.
            const comm = a.dupe(u8, st.comm) catch continue;
            var p: Proc = .{
                .pid = pid,
                .ppid = st.ppid,
                .name = "",
                .comm = comm,
                .state = st.state,
                .threads = st.threads,
                .kthread = st.flags & pf_kthread != 0,
                .cpu_ticks = st.utime + st.stime,
                .start = st.start,
            };

            if (!p.kthread) {
                if (files.read(io, dir, std.fmt.bufPrint(&path, "{d}/statm", .{pid}) catch continue, &buf)) |statm| {
                    var f = std.mem.tokenizeScalar(u8, statm, ' ');
                    _ = f.next();
                    const resident = std.fmt.parseInt(u64, f.next() orelse "0", 10) catch 0;
                    const shared = std.fmt.parseInt(u64, f.next() orelse "0", 10) catch 0;
                    p.memory = (resident -| shared) * r.page;
                } else |_| {}
                if (files.link(io, dir, std.fmt.bufPrint(&path, "{d}/exe", .{pid}) catch continue, &exe_buf)) |target| {
                    p.exe = a.dupe(u8, exePath(target)) catch "";
                }
                if (files.read(io, dir, std.fmt.bufPrint(&path, "{d}/io", .{pid}) catch continue, &buf)) |io_text| {
                    p.disk_read = core.text.field(io_text, "read_bytes:");
                    p.disk_write = core.text.field(io_text, "write_bytes:");
                    p.io_known = true;
                } else |_| {}
            }
            p.uid = r.uidOf(io, dir, pid, st.start);
            p.name = displayName(comm, p.exe);
            out.append(a, p) catch break;
        }
        if (r.uids.count() > 4 * (out.items.len + 64)) r.uids.clearRetainingCapacity();
    }

    fn uidOf(r: *Reader, io: std.Io, dir: std.Io.Dir, pid: i32, start: u64) u32 {
        if (r.uids.get(pid)) |e| if (e.start == start) return e.uid;
        var buf: [2048]u8 = undefined;
        var path: [32]u8 = undefined;
        const text = files.read(io, dir, std.fmt.bufPrint(&path, "{d}/status", .{pid}) catch return 0, &buf) catch return 0;
        const uid: u32 = @intCast(core.text.field(text, "Uid:") & 0xffff_ffff);
        r.uids.put(r.gpa, pid, .{ .start = start, .uid = uid }) catch {};
        return uid;
    }
};

test "parseStat survives names with spaces and parentheses" {
    const text = "4242 (Web Content (x)) S 4000 4242 4242 0 -1 4194560 100 0 5 0 70 30 0 0 20 0 12 0 99999 1000 200 18446744073709551615";
    const st = parseStat(text).?;
    try std.testing.expectEqualStrings("Web Content (x)", st.comm);
    try std.testing.expectEqual(@as(i32, 4000), st.ppid);
    try std.testing.expectEqual(@as(u64, 70), st.utime);
    try std.testing.expectEqual(@as(u64, 30), st.stime);
    try std.testing.expectEqual(@as(u32, 12), st.threads);
    try std.testing.expectEqual(@as(u64, 99999), st.start);
    try std.testing.expect(st.flags & pf_kthread == 0);
}

test "parseStat spots kernel threads" {
    const text = "2 (kthreadd) S 0 0 0 0 -1 2129984 0 0 0 0 0 0 0 0 20 0 1 0 2 0 0 18446744073709551615";
    const st = parseStat(text).?;
    try std.testing.expect(st.flags & pf_kthread != 0);
    try std.testing.expectEqual(@as(i32, 0), st.ppid);
}

test "a signal never reaches a process that started at another time" {
    try std.testing.expect(!signal(std.testing.io, selfPid(), 0, .quit)); // our own pid, but not our start time
    try std.testing.expect(!signal(std.testing.io, std.math.maxInt(i32), 0, .quit)); // no such process
}

test "an executable path keeps its own name and only loses a deleted marker" {
    try std.testing.expectEqualStrings("/usr/bin/node", exePath("/usr/bin/node"));
    try std.testing.expectEqualStrings("/usr/lib/xdg-desktop-portal", exePath("/usr/lib/xdg-desktop-portal"));
    try std.testing.expectEqualStrings("/usr/lib/systemd/systemd", exePath("/usr/lib/systemd/systemd"));
    try std.testing.expectEqualStrings("/usr/bin/node", exePath("/usr/bin/node (deleted)"));
}

test "displayName prefers the longer executable name" {
    try std.testing.expectEqualStrings("gnome-terminal-server", displayName("gnome-terminal-", "/usr/libexec/gnome-terminal-server"));
    try std.testing.expectEqualStrings("bash", displayName("bash", "/usr/bin/bash"));
    try std.testing.expectEqualStrings("sh", displayName("sh", ""));
}
