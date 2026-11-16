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

/// What doesn't change while a process runs one program: who owns it and which
/// executable it is. A pid keeps its start time across exec, so the kernel name
/// is part of the key too.
const Known = struct {
    start: u64,
    comm: u64,
    uid: u32,
    /// Owned by the reader; "" when the link can't be read.
    exe: []const u8,
    /// The scan that last met it.
    seen: u32,
};

/// Walks /proc. Owner and executable are read once per process and remembered,
/// so a steady machine costs three small reads per process a sample: stat,
/// statm, and io for the user's own processes (the kernel refuses the rest).
pub const Reader = struct {
    gpa: std.mem.Allocator,
    page: u64,
    me: u32,
    known: std.AutoHashMapUnmanaged(i32, Known) = .empty,
    scans: u32 = 0,

    pub fn init(gpa: std.mem.Allocator) Reader {
        return .{ .gpa = gpa, .page = units.pageSize(), .me = currentUid() };
    }

    pub fn deinit(r: *Reader) void {
        var it = r.known.valueIterator();
        while (it.next()) |k| r.gpa.free(k.exe);
        r.known.deinit(r.gpa);
    }

    /// Appends every process to `out`; names are copied into `a`. Executable
    /// paths belong to the reader and last as long as their process.
    pub fn scan(r: *Reader, io: std.Io, a: std.mem.Allocator, out: *std.ArrayList(Proc)) void {
        r.scans +%= 1;
        defer r.forget();
        var dir = std.Io.Dir.cwd().openDir(io, "/proc", .{ .iterate = true }) catch return;
        defer dir.close(io);
        var it = dir.iterate();
        var buf: [4096]u8 = undefined;
        var path: [64]u8 = undefined;
        while (it.next(io) catch null) |entry| {
            const pid = std.fmt.parseInt(i32, entry.name, 10) catch continue;
            const stat_text = files.read(io, dir, std.fmt.bufPrint(&path, "{d}/stat", .{pid}) catch continue, &buf) catch continue;
            const st = parseStat(stat_text) orelse continue;
            const kthread = st.flags & pf_kthread != 0;
            const known = r.knownFor(io, dir, pid, st, kthread);

            // The name points into `buf`, which the next reads reuse: keep a copy.
            const comm = a.dupe(u8, st.comm) catch continue;
            var p: Proc = .{
                .pid = pid,
                .ppid = st.ppid,
                .name = displayName(comm, known.exe),
                .comm = comm,
                .exe = known.exe,
                .uid = known.uid,
                .state = st.state,
                .threads = st.threads,
                .kthread = kthread,
                .cpu_ticks = st.utime + st.stime,
                .start = st.start,
            };

            if (!kthread) {
                if (files.read(io, dir, std.fmt.bufPrint(&path, "{d}/statm", .{pid}) catch continue, &buf)) |statm| {
                    var f = std.mem.tokenizeScalar(u8, statm, ' ');
                    _ = f.next();
                    const resident = std.fmt.parseInt(u64, f.next() orelse "0", 10) catch 0;
                    const shared = std.fmt.parseInt(u64, f.next() orelse "0", 10) catch 0;
                    p.memory = (resident -| shared) * r.page;
                } else |_| {}
                // Another user's I/O counters are refused unless we are root.
                if (r.me == 0 or p.uid == r.me) {
                    if (files.read(io, dir, std.fmt.bufPrint(&path, "{d}/io", .{pid}) catch continue, &buf)) |io_text| {
                        p.disk_read = core.text.field(io_text, "read_bytes:");
                        p.disk_write = core.text.field(io_text, "write_bytes:");
                        p.io_known = true;
                    } else |_| {}
                }
            }
            out.append(a, p) catch break;
        }
    }

    /// The owner and executable of `pid`, read only when the process is new to
    /// the reader or has become another program. Kernel threads have neither.
    fn knownFor(r: *Reader, io: std.Io, dir: std.Io.Dir, pid: i32, st: Stat, kthread: bool) Known {
        const comm = std.hash.Wyhash.hash(0, st.comm);
        var fresh: Known = .{ .start = st.start, .comm = comm, .uid = 0, .exe = "", .seen = r.scans };
        const slot = r.known.getOrPut(r.gpa, pid) catch return fresh;
        if (slot.found_existing) {
            if (slot.value_ptr.start == st.start and slot.value_ptr.comm == comm) {
                slot.value_ptr.seen = r.scans;
                return slot.value_ptr.*;
            }
            r.gpa.free(slot.value_ptr.exe);
        }
        if (!kthread) {
            var path: [32]u8 = undefined;
            var buf: [2048]u8 = undefined;
            if (files.read(io, dir, std.fmt.bufPrint(&path, "{d}/status", .{pid}) catch "", &buf)) |text| {
                fresh.uid = @intCast(core.text.field(text, "Uid:") & 0xffff_ffff);
            } else |_| {}
            var exe_buf: [512]u8 = undefined;
            if (files.link(io, dir, std.fmt.bufPrint(&path, "{d}/exe", .{pid}) catch "", &exe_buf)) |target| {
                fresh.exe = r.gpa.dupe(u8, exePath(target)) catch "";
            }
        }
        slot.value_ptr.* = fresh;
        return fresh;
    }

    /// Lets go of the processes the last scan didn't meet.
    fn forget(r: *Reader) void {
        var gone: [256]i32 = undefined;
        while (true) {
            var n: usize = 0;
            var it = r.known.iterator();
            while (it.next()) |e| {
                if (e.value_ptr.seen == r.scans) continue;
                gone[n] = e.key_ptr.*;
                n += 1;
                if (n == gone.len) break;
            }
            for (gone[0..n]) |pid| if (r.known.fetchRemove(pid)) |kv| r.gpa.free(kv.value.exe);
            if (n < gone.len) return;
        }
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
