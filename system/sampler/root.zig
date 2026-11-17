//! Samples the machine: every process, the CPU (as a whole and per core), memory,
//! disks, network and load. Each `collect` reads the counters the OS keeps through
//! a backend and turns them into rates by comparing them with the previous sample.
//! A short history of the totals is kept for the charts.
const std = @import("std");
const builtin = @import("builtin");
const core = @import("zmon-core");
const platform = @import("../platform/root.zig");

const backend = switch (builtin.os.tag) {
    .linux => @import("linux/root.zig"),
    else => @import("dummy/root.zig"),
};

const Proc = core.Proc;
const Memory = core.Memory;
const Ring = core.Ring;
const Cpu = backend.cpu.Times;

pub const Worker = @import("worker.zig").Worker;
pub const Waker = @import("worker.zig").Waker;

/// Ending tasks: who we are, and signals that only reach the process that was sampled.
pub const control = struct {
    pub const Signal = backend.process.Signal;
    pub const signal = backend.process.signal;
    pub const currentUid = backend.process.currentUid;
    pub const selfPid = backend.process.selfPid;
};

pub const History = struct {
    cpu: Ring(f32) = .{},
    memory: Ring(f32) = .{},
    disk_read: Ring(f32) = .{},
    disk_write: Ring(f32) = .{},
    net_in: Ring(f32) = .{},
    net_out: Ring(f32) = .{},
    /// Percent of swap in use, and of the battery's charge (0 without one).
    swap: Ring(f32) = .{},
    battery: Ring(f32) = .{},
};

const Prev = struct { ticks: u64, start: u64, read: u64, write: u64 };

/// What the next sample reads. The process list costs most, so the app asks
/// for it only while a list (or something watching a process) needs it.
pub const Want = struct {
    procs: bool = true,
    kernel_threads: bool = true,
    /// The device page's costlier readings (each disk, interface, clock...).
    devices: core.devices.DeviceWant = .{},
    /// Milliseconds between samples, and whether sampling is paused.
    interval_ms: u16 = 1000,
    paused: bool = false,
    /// A port being searched for (0: none): who holds it is looked up.
    port: u16 = 0,
    /// The process the details pane shows (0: none), and when it started.
    detail_pid: i32 = 0,
    detail_start: u64 = 0,
};

pub const Sampler = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    /// Holds the current sample's names and processes.
    arena: std.heap.ArenaAllocator,
    reader: backend.process.Reader,
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
    /// Every thread and every process on the machine, counted each sample
    /// whether or not the process list was read.
    threads: u32 = 0,
    process_count: u32 = 0,
    samples: u64 = 0,
    want: Want = .{},
    /// This sample read the process list but has no earlier one to measure
    /// against (the first sample, or the first after the list was closed):
    /// its rates are zero, and a second sample should follow soon.
    rates_pending: bool = false,
    /// The last sample read the process list.
    procs_read: bool = false,
    /// The details of `want.detail_pid`, in the arena, when it asked for them.
    detail: ?core.Details = null,
    /// Who holds `want.port`.
    port_holders: backend.origin.Holders = .{},
    history: History = .{},

    hz: u64 = 100,
    machine_buf: [128]u8 = undefined,
    machine_len: usize = 0,
    prev_time: f64 = 0,
    /// Up to when history has entries (one a second).
    history_time: f64 = 0,
    prev: std.AutoHashMapUnmanaged(i32, Prev) = .empty,
    next_prev: std.AutoHashMapUnmanaged(i32, Prev) = .empty,
    prev_cpu: std.ArrayList(Cpu) = .empty,
    prev_disk: [2]u64 = .{ 0, 0 },
    prev_net: [2]u64 = .{ 0, 0 },
    interfaces: backend.network.Interfaces = .{},
    devices_reader: backend.devices.Reader = .{},
    /// Each disk, filesystem, interface, sensor, the battery and pressure.
    devices: core.devices.Devices = .{},

    pub fn init(gpa: std.mem.Allocator, io: std.Io) Sampler {
        var s: Sampler = .{
            .gpa = gpa,
            .io = io,
            .arena = .init(gpa),
            .reader = .init(gpa),
            .hz = backend.clockTicks(),
        };
        s.machine_len = backend.machine.name(io, &s.machine_buf).len;
        return s;
    }

    /// What the machine is called, read once at start; "" when nothing says.
    pub fn machine(s: *const Sampler) []const u8 {
        return s.machine_buf[0..s.machine_len];
    }

    pub fn deinit(s: *Sampler) void {
        s.arena.deinit();
        s.reader.deinit();
        s.gpa.free(s.cores);
        s.prev.deinit(s.gpa);
        s.next_prev.deinit(s.gpa);
        s.prev_cpu.deinit(s.gpa);
    }

    /// Reads everything now, timing rates by the machine's clock, so they hold
    /// however late a frame was or however a test drives the UI's clock.
    pub fn collectNow(s: *Sampler) void {
        s.collect(platform.clock.now());
    }

    /// Reads everything. `now` is a clock in seconds; rates are over the
    /// time since the last call.
    pub fn collect(s: *Sampler, now: f64) void {
        const dt = @max(now - s.prev_time, 0.001);
        const first = s.samples == 0;
        _ = s.arena.reset(.retain_capacity);
        s.collectProcs(dt, first);
        s.detail = if (s.want.detail_pid > 0) backend.details.read(s.io, s.arena.allocator(), s.want.detail_pid, s.want.detail_start, s.unitOf(s.want.detail_pid)) else null;
        s.port_holders = if (s.want.port > 0) backend.origin.holders(s.io, s.want.port, backend.process.currentUid()) else .{};
        s.collectCpu();
        s.memory = backend.memory.read(s.io);
        s.collectDisk(dt, first);
        s.collectNet(dt, first);
        s.devices_reader.read(s.io, &s.devices, s.want.devices, dt, now, &s.interfaces);
        const l = backend.load.read(s.io);
        s.load = l.avg;
        s.uptime = l.uptime;
        s.threads = l.threads;
        s.prev_time = now;
        s.samples += 1;
        // History keeps one entry a second whatever the sampling speed: a
        // faster speed adds a value once a second has gone by, a slower one
        // repeats it for each second between (a pause isn't filled in).
        const pushes = s.historyPushes(now);
        for (0..pushes) |_| s.pushHistory();
    }

    /// How many seconds of history this sample stands for.
    fn historyPushes(s: *Sampler, now: f64) usize {
        if (s.history_time == 0) {
            s.history_time = now;
            return 1;
        }
        const whole: usize = @intFromFloat(@max(0, @floor(now - s.history_time)));
        if (whole == 0) return 0;
        s.history_time += @floatFromInt(whole);
        // A slower speed is a few seconds; a long gap is a pause, left out.
        const most: usize = @intFromFloat(@ceil(@as(f64, @floatFromInt(s.want.interval_ms)) / 1000));
        return @min(whole, @max(1, most));
    }

    fn pushHistory(s: *Sampler) void {
        s.history.cpu.push(s.cpu_pct);
        s.history.memory.push(if (s.memory.total > 0)
            @as(f32, @floatFromInt(s.memory.used())) * 100 / @as(f32, @floatFromInt(s.memory.total))
        else
            0);
        s.history.disk_read.push(s.disk_read_bps);
        s.history.disk_write.push(s.disk_write_bps);
        s.history.net_in.push(s.net_in_bps);
        s.history.net_out.push(s.net_out_bps);
        s.history.swap.push(if (s.memory.swap_total > 0)
            @as(f32, @floatFromInt(s.memory.swapUsed())) * 100 / @as(f32, @floatFromInt(s.memory.swap_total))
        else
            0);
        s.history.battery.push(s.devices.battery.percent);
    }

    fn unitOf(s: *const Sampler, pid: i32) []const u8 {
        return if (s.find(pid)) |p| p.unit else "";
    }

    /// The process with this pid in the current sample.
    pub fn find(s: *const Sampler, pid: i32) ?*const Proc {
        for (s.procs) |*p| if (p.pid == pid) return p;
        return null;
    }

    fn collectProcs(s: *Sampler, dt: f64, first: bool) void {
        if (!s.want.procs) {
            s.procs = &.{};
            s.process_count = s.reader.count(s.io);
            s.procs_read = false;
            s.rates_pending = false;
            return;
        }
        // After a gap the earlier ticks are stale: measure from this sample on.
        const fresh = first or !s.procs_read;
        s.procs_read = true;
        s.rates_pending = fresh;
        const a = s.arena.allocator();
        var list: std.ArrayList(Proc) = .empty;
        s.process_count = s.reader.scan(s.io, a, &list, .{ .kernel_threads = s.want.kernel_threads });
        s.applyRates(list.items, dt, fresh);
        s.procs = list.items;
    }

    /// Turns each process's counters into rates against the last sample. A
    /// pid with another start time is a new process (the pid was reused) and
    /// has no rate yet; counters that went backwards count as nothing.
    fn applyRates(s: *Sampler, procs: []Proc, dt: f64, fresh: bool) void {
        s.next_prev.clearRetainingCapacity();
        for (procs) |*p| {
            if (s.prev.get(p.pid)) |old| {
                if (old.start == p.start and !fresh) {
                    const ticks = p.cpu_ticks -| old.ticks;
                    p.cpu = @floatCast(@as(f64, @floatFromInt(ticks)) * 100.0 / (@as(f64, @floatFromInt(s.hz)) * dt));
                    if (p.io_known) {
                        const bytes = (p.disk_read -| old.read) + (p.disk_write -| old.write);
                        p.disk_bps = @floatCast(@as(f64, @floatFromInt(bytes)) / dt);
                    }
                }
            }
            s.next_prev.put(s.gpa, p.pid, .{ .ticks = p.cpu_ticks, .start = p.start, .read = p.disk_read, .write = p.disk_write }) catch {};
        }
        std.mem.swap(@TypeOf(s.prev), &s.prev, &s.next_prev);
    }

    fn collectCpu(s: *Sampler) void {
        var now_cpu: [257]Cpu = undefined;
        const n = backend.cpu.read(s.io, &now_cpu);
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

    fn collectDisk(s: *Sampler, dt: f64, first: bool) void {
        // A failed read leaves the last counters: the next good one measures from them.
        const now_disk = backend.disk.read(s.io) orelse return;
        if (!first) {
            s.disk_read_bps = rate(now_disk[0], s.prev_disk[0], dt);
            s.disk_write_bps = rate(now_disk[1], s.prev_disk[1], dt);
        }
        s.prev_disk = now_disk;
    }

    fn collectNet(s: *Sampler, dt: f64, first: bool) void {
        const now_net = backend.network.read(s.io, &s.interfaces) orelse return;
        if (!first) {
            s.net_in_bps = rate(now_net[0], s.prev_net[0], dt);
            s.net_out_bps = rate(now_net[1], s.prev_net[1], dt);
        }
        s.prev_net = now_net;
    }
};

/// One sample as the app reads it: the sampler's results copied out, names
/// and paths included, so the sampler can go on reading on its own thread.
pub const Snapshot = struct {
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
    process_count: u32 = 0,
    /// Samples taken so far, this one included (0: none yet).
    samples: u64 = 0,
    /// It read the process list.
    procs_read: bool = false,
    /// The selected process's details, when the app asked for them.
    detail: ?core.Details = null,
    /// The port searched for, and who holds it.
    port: u16 = 0,
    port_holders: backend.origin.Holders = .{},
    /// Clock ticks a second, to turn start times into ages.
    hz: u64 = 100,
    devices: core.devices.Devices = .{},
    history: History = .{},
    machine_buf: [128]u8 = undefined,
    machine_len: usize = 0,

    pub fn init(gpa: std.mem.Allocator) Snapshot {
        return .{ .arena = .init(gpa) };
    }

    pub fn deinit(sn: *Snapshot) void {
        sn.arena.deinit();
    }

    /// What the machine is called; "" when nothing says.
    pub fn machine(sn: *const Snapshot) []const u8 {
        return sn.machine_buf[0..sn.machine_len];
    }

    /// The process with this pid in the sample.
    pub fn find(sn: *const Snapshot, pid: i32) ?*const Proc {
        for (sn.procs) |*p| if (p.pid == pid) return p;
        return null;
    }

    /// Copies the sampler's last sample in, replacing what was here.
    pub fn fill(sn: *Snapshot, s: *const Sampler) void {
        _ = sn.arena.reset(.retain_capacity);
        const a = sn.arena.allocator();
        sn.procs = &.{};
        if (a.alloc(Proc, s.procs.len)) |procs| {
            for (procs, s.procs) |*d, p| {
                d.* = p;
                // The reader owns these and lets them go when a process ends.
                d.comm = a.dupe(u8, p.comm) catch "";
                d.exe = a.dupe(u8, p.exe) catch "";
                d.name = a.dupe(u8, p.name) catch "";
                d.program = a.dupe(u8, p.program) catch "";
                d.unit = a.dupe(u8, p.unit) catch "";
            }
            sn.procs = procs;
        } else |_| {}
        sn.cores = a.dupe(f32, s.cores) catch &.{};
        sn.cpu_pct = s.cpu_pct;
        sn.memory = s.memory;
        sn.load = s.load;
        sn.uptime = s.uptime;
        sn.disk_read_bps = s.disk_read_bps;
        sn.disk_write_bps = s.disk_write_bps;
        sn.net_in_bps = s.net_in_bps;
        sn.net_out_bps = s.net_out_bps;
        sn.threads = s.threads;
        sn.process_count = s.process_count;
        sn.samples = s.samples;
        sn.procs_read = s.procs_read;
        sn.hz = s.hz;
        sn.devices = s.devices;
        sn.port = s.want.port;
        sn.port_holders = s.port_holders;
        sn.detail = null;
        if (s.detail) |d| {
            var c = d;
            c.cmdline = a.dupe(u8, d.cmdline) catch "";
            c.cwd = a.dupe(u8, d.cwd) catch "";
            c.cgroup = a.dupe(u8, d.cgroup) catch "";
            c.unit_description = a.dupe(u8, d.unit_description) catch "";
            c.unit_file = a.dupe(u8, d.unit_file) catch "";
            c.repo = a.dupe(u8, d.repo) catch "";
            c.branch = a.dupe(u8, d.branch) catch "";
            sn.detail = c;
        }
        sn.history = s.history;
        sn.machine_buf = s.machine_buf;
        sn.machine_len = s.machine_len;
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

test "a share of the ticks between two reads is a percentage" {
    try std.testing.expectApproxEqAbs(@as(f32, 50), percent(.{ .busy = 0, .total = 0 }, .{ .busy = 50, .total = 100 }), 0.001);
    try std.testing.expectEqual(@as(f32, 0), percent(.{ .busy = 5, .total = 10 }, .{ .busy = 5, .total = 10 }));
    try std.testing.expectApproxEqAbs(@as(f32, 1000), rate(2000, 1000, 1.0), 0.001);
}

// Zig only analyses what is referenced, so this is what makes a cross-compile
// check look inside a backend the host never calls.
test "the sampler and its backend compile on every OS" {
    std.testing.refAllDecls(backend);
    std.testing.refAllDecls(backend.process);
    std.testing.refAllDecls(backend.process.Reader);
    std.testing.refAllDecls(control);
    std.testing.refAllDecls(backend.cpu);
    std.testing.refAllDecls(backend.memory);
    std.testing.refAllDecls(backend.disk);
    std.testing.refAllDecls(backend.network);
    std.testing.refAllDecls(backend.load);
    std.testing.refAllDecls(backend.machine);
    std.testing.refAllDecls(Sampler);
    std.testing.refAllDecls(Snapshot);
    std.testing.refAllDecls(Worker);
}

test "rates come from the last sample of the same process, never a reused pid's" {
    var s = Sampler.init(std.testing.allocator, std.testing.io);
    defer s.deinit();
    s.hz = 100;
    var one = [_]Proc{.{ .pid = 10, .ppid = 1, .name = "a", .start = 5, .cpu_ticks = 100, .disk_read = 1000, .io_known = true }};
    s.applyRates(&one, 1, false);
    try std.testing.expectEqual(@as(f32, 0), one[0].cpu); // nothing to measure against yet
    var two = [_]Proc{.{ .pid = 10, .ppid = 1, .name = "a", .start = 5, .cpu_ticks = 150, .disk_read = 3000, .io_known = true }};
    s.applyRates(&two, 1, false);
    try std.testing.expectApproxEqAbs(@as(f32, 50), two[0].cpu, 0.01); // 50 ticks of 100 a second
    try std.testing.expectApproxEqAbs(@as(f32, 2000), two[0].disk_bps, 0.01);
    var reused = [_]Proc{.{ .pid = 10, .ppid = 1, .name = "b", .start = 9, .cpu_ticks = 400, .io_known = true }};
    s.applyRates(&reused, 1, false);
    try std.testing.expectEqual(@as(f32, 0), reused[0].cpu); // another process under the same pid
    var backwards = [_]Proc{.{ .pid = 10, .ppid = 1, .name = "b", .start = 9, .cpu_ticks = 300, .disk_read = 0, .io_known = true }};
    s.applyRates(&backwards, 1, false);
    try std.testing.expectEqual(@as(f32, 0), backwards[0].cpu);
    try std.testing.expectEqual(@as(f32, 0), backwards[0].disk_bps);
    var after_gap = [_]Proc{.{ .pid = 10, .ppid = 1, .name = "b", .start = 9, .cpu_ticks = 900 }};
    s.applyRates(&after_gap, 1, true); // the list was closed: earlier ticks are stale
    try std.testing.expectEqual(@as(f32, 0), after_gap[0].cpu);
}

test "history keeps one entry a second at any sampling speed" {
    var s = Sampler.init(std.testing.allocator, std.testing.io);
    defer s.deinit();
    s.want.interval_ms = 500;
    try std.testing.expectEqual(@as(usize, 1), s.historyPushes(100.0));
    try std.testing.expectEqual(@as(usize, 0), s.historyPushes(100.5)); // half a second: none yet
    try std.testing.expectEqual(@as(usize, 1), s.historyPushes(101.0));
    s.want.interval_ms = 5000;
    try std.testing.expectEqual(@as(usize, 5), s.historyPushes(106.0)); // five seconds stand for five entries
    try std.testing.expectEqual(@as(usize, 5), s.historyPushes(400.0)); // a pause isn't filled in
}

test "a snapshot owns its names, so the sampler can drop its own" {
    var s = Sampler.init(std.testing.allocator, std.testing.io);
    defer s.deinit();
    s.collect(1.0);
    var sn = Snapshot.init(std.testing.allocator);
    defer sn.deinit();
    sn.fill(&s);
    try std.testing.expectEqual(s.procs.len, sn.procs.len);
    if (sn.procs.len > 0) try std.testing.expect(sn.procs[0].name.ptr != s.procs[0].name.ptr);
    s.collect(2.0); // the sampler's own memory is reused here
    for (sn.procs) |p| _ = std.mem.indexOfScalar(u8, p.name, 0); // still readable
}

test "the live machine: this test process is found, and the totals are sane" {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const procfs = @import("../platform/root.zig").files;
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
