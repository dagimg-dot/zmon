//! Samples the machine from /proc: every process, the CPU (as a whole and per
//! core), memory, disks, network, load. Each `collect` turns the counters
//! the kernel keeps into rates by comparing them with the previous sample.
//! A short history of the totals is kept for the charts.
const std = @import("std");
const core = @import("zmon-core");
const procfs = @import("zmon-system").platform.files;

pub const Proc = core.Proc;
pub const Memory = core.Memory;
pub const Ring = core.Ring;
pub const history_len = core.history_len;

extern "c" fn sysconf(name: c_int) c_long;

pub const History = struct {
    cpu: Ring(f32) = .{},
    memory: Ring(f32) = .{},
    disk_read: Ring(f32) = .{},
    disk_write: Ring(f32) = .{},
    net_in: Ring(f32) = .{},
    net_out: Ring(f32) = .{},
};

const Prev = struct { ticks: u64, start: u64, read: u64, write: u64 };
const Cpu = struct { busy: u64 = 0, total: u64 = 0 };

pub const Sampler = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    /// Holds the current sample's names and processes.
    arena: std.heap.ArenaAllocator,
    procs: []Proc = &.{},
    cores: []f32 = &.{},
    cpu_pct: f32 = 0,
    memory: Memory = .{},
    load: [3]f32 = .{ 0, 0, 0 },
    uptime: f64 = 0,
    disk_read_bps: f32 = 0,
    disk_write_bps: f32 = 0,
    net_in_bps: f32 = 0,
    net_out_bps: f32 = 0,
    threads: u32 = 0,
    samples: u64 = 0,
    history: History = .{},

    hz: u64 = 100,
    page: u64 = 4096,
    prev_time: f64 = 0,
    prev: std.AutoHashMapUnmanaged(i32, Prev) = .empty,
    next_prev: std.AutoHashMapUnmanaged(i32, Prev) = .empty,
    uids: std.AutoHashMapUnmanaged(i32, struct { start: u64, uid: u32 }) = .empty,
    prev_cpu: std.ArrayList(Cpu) = .empty,
    prev_disk: [2]u64 = .{ 0, 0 },
    prev_net: [2]u64 = .{ 0, 0 },

    pub fn init(gpa: std.mem.Allocator, io: std.Io) Sampler {
        var s: Sampler = .{ .gpa = gpa, .io = io, .arena = .init(gpa) };
        s.hz = @intCast(@max(1, sysconf(2))); // _SC_CLK_TCK
        s.page = @intCast(@max(1, sysconf(30))); // _SC_PAGESIZE
        return s;
    }

    pub fn deinit(s: *Sampler) void {
        s.arena.deinit();
        s.gpa.free(s.cores);
        s.prev.deinit(s.gpa);
        s.next_prev.deinit(s.gpa);
        s.uids.deinit(s.gpa);
        s.prev_cpu.deinit(s.gpa);
    }

    /// Reads everything. `now` is a clock in seconds; rates are over the
    /// time since the last call.
    pub fn collect(s: *Sampler, now: f64) void {
        const dt = @max(now - s.prev_time, 0.001);
        const first = s.samples == 0;
        _ = s.arena.reset(.retain_capacity);
        s.collectProcs(dt, first);
        s.collectCpu();
        s.collectMemory();
        s.collectDisk(dt, first);
        s.collectNet(dt, first);
        s.collectLoad();
        s.prev_time = now;
        s.samples += 1;
        s.history.cpu.push(s.cpu_pct);
        s.history.memory.push(if (s.memory.total > 0)
            @as(f32, @floatFromInt(s.memory.used())) * 100 / @as(f32, @floatFromInt(s.memory.total))
        else
            0);
        s.history.disk_read.push(s.disk_read_bps);
        s.history.disk_write.push(s.disk_write_bps);
        s.history.net_in.push(s.net_in_bps);
        s.history.net_out.push(s.net_out_bps);
    }

    /// The process with this pid in the current sample.
    pub fn find(s: *const Sampler, pid: i32) ?*const Proc {
        for (s.procs) |*p| if (p.pid == pid) return p;
        return null;
    }

    fn collectProcs(s: *Sampler, dt: f64, first: bool) void {
        const a = s.arena.allocator();
        var dir = std.Io.Dir.cwd().openDir(s.io, "/proc", .{ .iterate = true }) catch return;
        defer dir.close(s.io);
        var list: std.ArrayList(Proc) = .empty;
        s.next_prev.clearRetainingCapacity();
        s.threads = 0;

        var it = dir.iterate();
        var buf: [4096]u8 = undefined;
        var path: [64]u8 = undefined;
        var exe_buf: [512]u8 = undefined;
        while (it.next(s.io) catch null) |entry| {
            const pid = std.fmt.parseInt(i32, entry.name, 10) catch continue;
            const stat_text = procfs.read(s.io, dir, std.fmt.bufPrint(&path, "{d}/stat", .{pid}) catch continue, &buf) catch continue;
            const st = parseStat(stat_text) orelse continue;

            // The name points into `buf`, which the next reads reuse: keep a copy.
            const comm = a.dupe(u8, st.comm) catch continue;
            var p: Proc = .{
                .pid = pid,
                .ppid = st.ppid,
                .name = "",
                .state = st.state,
                .threads = st.threads,
                .kthread = st.flags & pf_kthread != 0,
                .cpu_ticks = st.utime + st.stime,
                .start = st.start,
            };
            s.threads += st.threads;

            if (!p.kthread) {
                if (procfs.read(s.io, dir, std.fmt.bufPrint(&path, "{d}/statm", .{pid}) catch continue, &buf)) |statm| {
                    var f = std.mem.tokenizeScalar(u8, statm, ' ');
                    _ = f.next();
                    const resident = std.fmt.parseInt(u64, f.next() orelse "0", 10) catch 0;
                    const shared = std.fmt.parseInt(u64, f.next() orelse "0", 10) catch 0;
                    p.memory = (resident -| shared) * s.page;
                } else |_| {}
                if (procfs.link(s.io, dir, std.fmt.bufPrint(&path, "{d}/exe", .{pid}) catch continue, &exe_buf)) |target| {
                    const clean = std.mem.trimEnd(u8, target, " (deleted)");
                    p.exe = a.dupe(u8, clean) catch "";
                }
                if (procfs.read(s.io, dir, std.fmt.bufPrint(&path, "{d}/io", .{pid}) catch continue, &buf)) |io_text| {
                    p.disk_read = core.text.field(io_text, "read_bytes:");
                    p.disk_write = core.text.field(io_text, "write_bytes:");
                    p.io_known = true;
                } else |_| {}
            }
            p.uid = s.uidOf(dir, pid, st.start);
            p.name = displayName(comm, p.exe);

            if (s.prev.get(pid)) |old| {
                if (old.start == p.start and !first) {
                    const ticks = p.cpu_ticks -| old.ticks;
                    p.cpu = @floatCast(@as(f64, @floatFromInt(ticks)) * 100.0 / (@as(f64, @floatFromInt(s.hz)) * dt));
                    if (p.io_known) {
                        const bytes = (p.disk_read -| old.read) + (p.disk_write -| old.write);
                        p.disk_bps = @floatCast(@as(f64, @floatFromInt(bytes)) / dt);
                    }
                }
            }
            s.next_prev.put(s.gpa, pid, .{ .ticks = p.cpu_ticks, .start = p.start, .read = p.disk_read, .write = p.disk_write }) catch {};
            list.append(a, p) catch break;
        }
        std.mem.swap(@TypeOf(s.prev), &s.prev, &s.next_prev);
        s.procs = list.items;
        if (s.uids.count() > 4 * (s.procs.len + 64)) s.uids.clearRetainingCapacity();
    }

    fn uidOf(s: *Sampler, dir: std.Io.Dir, pid: i32, start: u64) u32 {
        if (s.uids.get(pid)) |e| if (e.start == start) return e.uid;
        var buf: [2048]u8 = undefined;
        var path: [32]u8 = undefined;
        const text = procfs.read(s.io, dir, std.fmt.bufPrint(&path, "{d}/status", .{pid}) catch return 0, &buf) catch return 0;
        const uid: u32 = @intCast(core.text.field(text, "Uid:") & 0xffff_ffff);
        s.uids.put(s.gpa, pid, .{ .start = start, .uid = uid }) catch {};
        return uid;
    }

    fn collectCpu(s: *Sampler) void {
        var buf: [16384]u8 = undefined;
        const text = procfs.read(s.io, .cwd(), "/proc/stat", &buf) catch return;
        var now_cpu: [257]Cpu = undefined;
        const n = parseCpus(text, &now_cpu);
        if (n == 0) return;
        if (s.prev_cpu.items.len == n) {
            s.cpu_pct = percent(s.prev_cpu.items[0], now_cpu[0]);
            if (s.cores.len != n - 1) {
                s.gpa.free(s.cores);
                s.cores = s.gpa.alloc(f32, n - 1) catch &.{};
            }
            for (s.cores, 1..) |*c, i| c.* = percent(s.prev_cpu.items[i], now_cpu[i]);
        }
        s.prev_cpu.clearRetainingCapacity();
        s.prev_cpu.appendSlice(s.gpa, now_cpu[0..n]) catch {};
    }

    fn collectMemory(s: *Sampler) void {
        var buf: [4096]u8 = undefined;
        const text = procfs.read(s.io, .cwd(), "/proc/meminfo", &buf) catch return;
        s.memory = parseMeminfo(text);
    }

    fn collectDisk(s: *Sampler, dt: f64, first: bool) void {
        var buf: [32768]u8 = undefined;
        const text = procfs.read(s.io, .cwd(), "/proc/diskstats", &buf) catch return;
        const now_disk = parseDiskstats(text);
        if (!first) {
            s.disk_read_bps = rate(now_disk[0], s.prev_disk[0], dt);
            s.disk_write_bps = rate(now_disk[1], s.prev_disk[1], dt);
        }
        s.prev_disk = now_disk;
    }

    fn collectNet(s: *Sampler, dt: f64, first: bool) void {
        var buf: [8192]u8 = undefined;
        const text = procfs.read(s.io, .cwd(), "/proc/net/dev", &buf) catch return;
        const now_net = parseNetDev(text);
        if (!first) {
            s.net_in_bps = rate(now_net[0], s.prev_net[0], dt);
            s.net_out_bps = rate(now_net[1], s.prev_net[1], dt);
        }
        s.prev_net = now_net;
    }

    fn collectLoad(s: *Sampler) void {
        var buf: [256]u8 = undefined;
        if (procfs.read(s.io, .cwd(), "/proc/loadavg", &buf)) |text| {
            var f = std.mem.tokenizeScalar(u8, text, ' ');
            for (&s.load) |*l| l.* = std.fmt.parseFloat(f32, f.next() orelse "0") catch 0;
        } else |_| {}
        if (procfs.read(s.io, .cwd(), "/proc/uptime", &buf)) |text| {
            var f = std.mem.tokenizeScalar(u8, text, ' ');
            s.uptime = std.fmt.parseFloat(f64, f.next() orelse "0") catch 0;
        } else |_| {}
    }
};

fn rate(now: u64, before: u64, dt: f64) f32 {
    return @floatCast(@as(f64, @floatFromInt(now -| before)) / dt);
}

fn percent(before: Cpu, now: Cpu) f32 {
    const total = now.total -| before.total;
    if (total == 0) return 0;
    return @floatCast(@as(f64, @floatFromInt(now.busy -| before.busy)) * 100.0 / @as(f64, @floatFromInt(total)));
}

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

/// The kernel cuts names at 15 characters; the executable's file name is
/// the whole of it when it starts the same way.
pub fn displayName(comm: []const u8, exe: []const u8) []const u8 {
    if (exe.len == 0) return comm;
    const base = std.fs.path.basename(exe);
    if (base.len > comm.len and std.mem.startsWith(u8, base, comm)) return base;
    return comm;
}

/// Fills `out` from the "cpu" and "cpuN" lines of /proc/stat (the total
/// first) and returns how many.
fn parseCpus(text: []const u8, out: []Cpu) usize {
    var n: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "cpu")) break;
        if (n == out.len) break;
        var f = std.mem.tokenizeScalar(u8, line, ' ');
        _ = f.next();
        var v: [8]u64 = @splat(0);
        for (&v) |*x| x.* = std.fmt.parseInt(u64, f.next() orelse break, 10) catch 0;
        // user nice system idle iowait irq softirq steal
        const idle = v[3] + v[4];
        const total = v[0] + v[1] + v[2] + v[3] + v[4] + v[5] + v[6] + v[7];
        out[n] = .{ .busy = total - idle, .total = total };
        n += 1;
    }
    return n;
}

fn kb(text: []const u8, key: []const u8) u64 {
    return core.text.field(text, key) * 1024;
}

pub fn parseMeminfo(text: []const u8) Memory {
    return .{
        .total = kb(text, "MemTotal:"),
        .available = kb(text, "MemAvailable:"),
        .cached = kb(text, "Cached:"),
        .shmem = kb(text, "Shmem:"),
        .swap_total = kb(text, "SwapTotal:"),
        .swap_free = kb(text, "SwapFree:"),
    };
}

/// A whole disk, not a partition or a virtual device: sda, vda, nvme0n1,
/// mmcblk0, but not sda1, nvme0n1p1, loop0, dm-0, zram0.
fn wholeDisk(name: []const u8) bool {
    if (name.len < 3) return false;
    if (std.mem.startsWith(u8, name, "nvme") or std.mem.startsWith(u8, name, "mmcblk"))
        return std.mem.indexOfScalar(u8, name, 'p') == null;
    for ([_][]const u8{ "sd", "vd", "hd", "xvd" }) |pre| {
        if (!std.mem.startsWith(u8, name, pre)) continue;
        for (name[pre.len..]) |ch| if (!std.ascii.isAlphabetic(ch)) return false;
        return true;
    }
    return false;
}

/// Bytes read and written by every whole disk since boot.
pub fn parseDiskstats(text: []const u8) [2]u64 {
    var total: [2]u64 = .{ 0, 0 };
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        var f = std.mem.tokenizeAny(u8, line, " \t");
        _ = f.next();
        _ = f.next();
        const dev = f.next() orelse continue;
        if (!wholeDisk(dev)) continue;
        var v: [8]u64 = @splat(0);
        for (&v) |*x| x.* = std.fmt.parseInt(u64, f.next() orelse break, 10) catch 0;
        // reads, merged, sectors read, ms, writes, merged, sectors written
        total[0] += v[2] * 512;
        total[1] += v[6] * 512;
    }
    return total;
}

/// Bytes received and sent by every interface but loopback since boot.
pub fn parseNetDev(text: []const u8) [2]u64 {
    var total: [2]u64 = .{ 0, 0 };
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const dev = std.mem.trim(u8, line[0..colon], " ");
        if (std.mem.eql(u8, dev, "lo")) continue;
        var f = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
        var v: [16]u64 = @splat(0);
        for (&v) |*x| x.* = std.fmt.parseInt(u64, f.next() orelse break, 10) catch 0;
        total[0] += v[0]; // bytes received
        total[1] += v[8]; // bytes sent
    }
    return total;
}

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

test "displayName prefers the longer executable name" {
    try std.testing.expectEqualStrings("gnome-terminal-server", displayName("gnome-terminal-", "/usr/libexec/gnome-terminal-server"));
    try std.testing.expectEqualStrings("bash", displayName("bash", "/usr/bin/bash"));
    try std.testing.expectEqualStrings("sh", displayName("sh", ""));
}

test "cpu lines: busy is everything but idle and iowait" {
    const text = "cpu  100 0 50 800 50 0 0 0 0 0\ncpu0 60 0 30 400 10 0 0 0 0 0\ncpu1 40 0 20 400 40 0 0 0 0 0\nintr 1\n";
    var out: [8]Cpu = undefined;
    try std.testing.expectEqual(@as(usize, 3), parseCpus(text, &out));
    try std.testing.expectEqual(@as(u64, 150), out[0].busy);
    try std.testing.expectEqual(@as(u64, 1000), out[0].total);
    try std.testing.expectApproxEqAbs(@as(f32, 50), percent(.{ .busy = 0, .total = 0 }, .{ .busy = 50, .total = 100 }), 0.001);
}

test "meminfo is read in bytes" {
    const m = parseMeminfo("MemTotal:  1000 kB\nMemAvailable:  400 kB\nCached: 100 kB\nSwapTotal: 50 kB\nSwapFree: 20 kB\n");
    try std.testing.expectEqual(@as(u64, 1000 * 1024), m.total);
    try std.testing.expectEqual(@as(u64, 600 * 1024), m.used());
    try std.testing.expectEqual(@as(u64, 30 * 1024), m.swapUsed());
}

test "disks: whole devices only" {
    try std.testing.expect(wholeDisk("nvme0n1"));
    try std.testing.expect(wholeDisk("sda"));
    try std.testing.expect(wholeDisk("mmcblk0"));
    try std.testing.expect(!wholeDisk("nvme0n1p2"));
    try std.testing.expect(!wholeDisk("sda1"));
    try std.testing.expect(!wholeDisk("loop3"));
    try std.testing.expect(!wholeDisk("dm-0"));
    const text = "   8  0 sda 10 0 2000 5 20 0 4000 9 0 0 0\n   8  1 sda1 5 0 1000 2 10 0 2000 4 0 0 0\n";
    const d = parseDiskstats(text);
    try std.testing.expectEqual(@as(u64, 2000 * 512), d[0]);
    try std.testing.expectEqual(@as(u64, 4000 * 512), d[1]);
}

test "network: loopback is left out" {
    const text =
        \\Inter-|   Receive                                                |  Transmit
        \\ face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
        \\    lo: 999 9 0 0 0 0 0 0 999 9 0 0 0 0 0 0
        \\  wlan0: 1000 10 0 0 0 0 0 0 500 5 0 0 0 0 0 0
    ;
    const n = parseNetDev(text);
    try std.testing.expectEqual(@as(u64, 1000), n[0]);
    try std.testing.expectEqual(@as(u64, 500), n[1]);
}

test "the live machine: this test process is found, and the totals are sane" {
    var s = Sampler.init(std.testing.allocator, std.testing.io);
    defer s.deinit();
    s.collect(1.0);
    s.collect(2.0);
    try std.testing.expect(s.procs.len > 1);
    const me = s.find(std.os.linux.getpid()) orelse return error.TestUnexpectedResult;
    // Names are real names, not leftovers of the buffers they were read through.
    try std.testing.expect(me.name.len > 0 and !std.ascii.isDigit(me.name[0]));
    var comm: [64]u8 = undefined;
    const kernel_name = std.mem.trimEnd(u8, try procfs.read(std.testing.io, .cwd(), "/proc/self/comm", &comm), "\n");
    try std.testing.expect(std.mem.startsWith(u8, me.name, kernel_name));
    try std.testing.expect(s.memory.total > 0);
    try std.testing.expect(s.cores.len > 0);
    try std.testing.expect(s.cpu_pct >= 0 and s.cpu_pct <= 100.5);
    try std.testing.expectEqual(@as(usize, 2), s.history.cpu.len);
}
