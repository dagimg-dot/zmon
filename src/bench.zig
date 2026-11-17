//! `zig build bench -Doptimize=ReleaseSafe`: what zmon costs, phase by phase,
//! on the live machine. Times each part a sample and a frame go through and
//! counts what each allocates, through a counting allocator over libc's.
//! No window opens: frames are drawn offscreen by ui.Tester, as the tests do,
//! so what a window adds (GTK, OpenGL) isn't in these figures.
//! `ZMON_BENCH_TRACE=1` prints where each allocation of 256 KiB or more is
//! made while the first frames are drawn.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const system = @import("zmon-system");
const app_state = @import("app/state.zig");
const app_view = @import("app/view.zig");
const theme = @import("ui/theme.zig");
const fonts = @import("ui/fonts.zig");

const clock = system.platform.clock;

/// Counts calls and bytes, live and at the peak.
const Counting = struct {
    child: std.mem.Allocator,
    allocs: usize = 0,
    frees: usize = 0,
    live: usize = 0,
    peak: usize = 0,

    fn allocator(c: *Counting) std.mem.Allocator {
        return .{ .ptr = c, .vtable = &.{ .alloc = alloc, .resize = resize, .remap = remap, .free = free } };
    }
    fn add(c: *Counting, n: usize) void {
        c.live += n;
        c.peak = @max(c.peak, c.live);
    }
    fn alloc(ctx: *anyopaque, len: usize, a: std.mem.Alignment, ra: usize) ?[*]u8 {
        const c: *Counting = @ptrCast(@alignCast(ctx));
        const p = c.child.rawAlloc(len, a, ra) orelse return null;
        c.allocs += 1;
        c.add(len);
        if (trace_big and len >= 256 * 1024) {
            std.debug.print("--- alloc {d} KiB\n", .{len / 1024});
            std.debug.dumpCurrentStackTrace(.{ .first_address = ra });
        }
        return p;
    }
    fn resize(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) bool {
        const c: *Counting = @ptrCast(@alignCast(ctx));
        if (!c.child.rawResize(m, a, n, ra)) return false;
        c.live -= m.len;
        c.add(n);
        return true;
    }
    fn remap(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, n: usize, ra: usize) ?[*]u8 {
        const c: *Counting = @ptrCast(@alignCast(ctx));
        const p = c.child.rawRemap(m, a, n, ra) orelse return null;
        c.allocs += 1;
        c.live -= m.len;
        c.add(n);
        return p;
    }
    fn free(ctx: *anyopaque, m: []u8, a: std.mem.Alignment, ra: usize) void {
        const c: *Counting = @ptrCast(@alignCast(ctx));
        c.child.rawFree(m, a, ra);
        c.frees += 1;
        c.live -= m.len;
    }
};

var trace_big = false;
var counting: Counting = .{ .child = std.heap.c_allocator };

const Span = struct {
    t: f64,
    allocs: usize,
    fn begin() Span {
        return .{ .t = clock.now(), .allocs = counting.allocs };
    }
    fn report(s: Span, label: []const u8, n: usize) void {
        const us = (clock.now() - s.t) * 1e6 / @as(f64, @floatFromInt(n));
        const allocs = @as(f64, @floatFromInt(counting.allocs - s.allocs)) / @as(f64, @floatFromInt(n));
        std.debug.print("{s:<44} {d:>9.1} us  {d:>8.1} allocs  live {d:>7} KiB\n", .{ label, us, allocs, counting.live / 1024 });
    }
};

pub fn main(init: std.process.Init) !void {
    const gpa = counting.allocator();
    const io = init.io;
    std.debug.print("{s:<44} {s:>12}  {s:>15}\n", .{ "phase (per call)", "time", "allocations" });

    {
        var s: system.sampler.Sampler = .init(gpa, io);
        defer s.deinit();
        s.want.kernel_threads = false; // hidden, as the app starts
        var t = Span.begin();
        s.collectNow();
        t.report("sampler: first sample (procs)", 1);
        const n = 40;
        t = Span.begin();
        for (0..n) |_| s.collectNow();
        t.report("sampler: sample with the process list", n);
        std.debug.print("  processes: {d}, windows: {d}\n", .{ s.procs.len, s.window_count });
        s.want.procs = false;
        t = Span.begin();
        for (0..n) |_| s.collectNow();
        t.report("sampler: sample without the process list", n);
        s.want.procs = true;
        s.want.devices = .{ .cpu = true, .disks = true, .network = true };
        t = Span.begin();
        for (0..n) |_| s.collectNow();
        t.report("sampler: sample with procs and devices", n);
        var sn: system.sampler.Snapshot = .init(gpa);
        defer sn.deinit();
        t = Span.begin();
        for (0..n) |_| sn.fill(&s);
        t.report("snapshot: copy a sample out", n);
        std.debug.print("  sizeof Sampler {d} KiB, Snapshot {d} KiB\n", .{ @sizeOf(system.sampler.Sampler) / 1024, @sizeOf(system.sampler.Snapshot) / 1024 });
    }
    const after_sampler = counting.live;

    _ = fonts.register();
    var t = Span.begin();
    var state: app_state.State = .init(gpa, io, null);
    defer state.deinit();
    t.report("state: init (launchers, users, themes)", 1);
    const after_state = counting.live;
    state.dark = true;

    var tester: ui.Tester = undefined;
    trace_big = init.environ_map.get("ZMON_BENCH_TRACE") != null;
    t = Span.begin();
    // Lexend, named by the window's theme, as main.zig sets them up.
    const window_theme = theme.uiTheme(theme.colors(state.theme(true), .{}));
    try tester.init(gpa, .init(&state, app_view.view), .{ .width = 1180, .height = 760, .scale = 2, .theme = window_theme });
    defer tester.deinit();
    tester.settle(0.5);
    t.report("first frames (sample, icons, layout)", 1);
    const after_first = counting.live;
    trace_big = false;

    const frames = 300;
    t = Span.begin();
    for (0..frames) |_| tester.frameImpl();
    t.report("frame: Apps", frames);

    t = Span.begin();
    for (0..20) |_| state.rebuild();
    t.report("rebuild: group and sort a sample (Apps)", 20);

    try tester.clickText("Processes");
    tester.settle(0.5);
    t = Span.begin();
    for (0..frames) |_| tester.frameImpl();
    t.report("frame: Processes", frames);
    t = Span.begin();
    for (0..20) |_| state.rebuild();
    t.report("rebuild: group and sort a sample (Processes)", 20);

    try tester.clickText("CPU");
    tester.settle(0.5);
    t = Span.begin();
    for (0..frames) |_| tester.frameImpl();
    t.report("frame: CPU", frames);

    try tester.clickText("Memory");
    tester.settle(0.5);
    t = Span.begin();
    for (0..frames) |_| tester.frameImpl();
    t.report("frame: Memory", frames);

    try tester.clickText("Apps");
    tester.settle(0.5);
    // A minute of the real thing: a sample a second and the frames it wakes.
    t = Span.begin();
    for (0..60) |_| {
        state.worker.step();
        tester.frameImpl();
        tester.frameImpl();
    }
    t.report("a sample and its frames (Apps)", 60);

    std.debug.print("\nheap (ours and nanoui's, through the counter):\n", .{});
    std.debug.print("  after the sampler bench   {d:>7} KiB\n", .{after_sampler / 1024});
    std.debug.print("  after State.init          {d:>7} KiB\n", .{after_state / 1024});
    std.debug.print("  after the first frames    {d:>7} KiB\n", .{after_first / 1024});
    std.debug.print("  now                       {d:>7} KiB, peak {d} KiB\n", .{ counting.live / 1024, counting.peak / 1024 });
}
