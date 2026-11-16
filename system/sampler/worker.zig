//! The sampler on its own thread, so reading /proc (8 to 17 ms a sample on a
//! slow-clocked core) never holds up a frame. The worker owns the Sampler;
//! the app reads only Snapshots, handed over through a triple buffer: the
//! worker always owns one to write, the app one to read, and a single atomic
//! swap trades the third, so neither ever sees a buffer the other is using.
//!
//! Without a thread (`step`), the same sample and hand-over run on the
//! caller's thread: tests use that.
const std = @import("std");
const root = @import("root.zig");

const Sampler = root.Sampler;
const Snapshot = root.Snapshot;

/// Asks the app's window for a frame, from any thread.
pub const Waker = struct { ctx: *anyopaque, wake: *const fn (ctx: *anyopaque) void };

pub const Worker = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    /// The worker's alone (the caller's when there's no thread).
    sampler: Sampler,
    bufs: [3]Snapshot,
    /// The buffer being written, and the one the app reads.
    back: u8 = 0,
    front: u8 = 1,
    /// The third buffer's index, with `fresh` set when it holds a sample the
    /// app hasn't taken.
    middle: std.atomic.Value(u8) = .init(2),
    /// What the app wants read (`Want` packed), set from the app's thread.
    want: std.atomic.Value(u32) = .init(packWant(.{})),
    /// Bumped to wake the worker early: a list opened, or stop.
    signal: std.atomic.Value(u32) = .init(0),
    stopping: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,
    waker: ?Waker = null,

    const fresh: u8 = 0x80;
    const index_mask: u8 = 0x03;

    /// Heap-allocated: the thread holds its address.
    pub fn create(gpa: std.mem.Allocator, io: std.Io) !*Worker {
        const w = try gpa.create(Worker);
        w.* = .{
            .gpa = gpa,
            .io = io,
            .sampler = .init(gpa, io),
            .bufs = .{ .init(gpa), .init(gpa), .init(gpa) },
        };
        return w;
    }

    pub fn destroy(w: *Worker) void {
        w.stop();
        w.sampler.deinit();
        for (&w.bufs) |*b| b.deinit();
        w.gpa.destroy(w);
    }

    /// Starts sampling on a thread; `waker` asks the window for a frame when a
    /// sample is ready.
    pub fn start(w: *Worker, waker: ?Waker) !void {
        if (w.thread != null) return;
        w.waker = waker;
        w.thread = try std.Thread.spawn(.{}, run, .{w});
    }

    pub fn stop(w: *Worker) void {
        const th = w.thread orelse return;
        w.stopping.store(true, .release);
        w.poke();
        th.join();
        w.thread = null;
    }

    pub fn running(w: *const Worker) bool {
        return w.thread != null;
    }

    /// Says what to read from the next sample on. `now`: sample at once
    /// rather than at the next second (a list was just opened).
    pub fn ask(w: *Worker, want: root.Want, now: bool) void {
        w.want.store(packWant(want), .release);
        if (now) w.poke();
    }

    /// The newest sample, if one came since the last call; it stays valid
    /// until the next call that returns one.
    pub fn take(w: *Worker) ?*const Snapshot {
        if (w.middle.load(.acquire) & fresh == 0) return null;
        const got = w.middle.swap(w.front, .acq_rel);
        w.front = got & index_mask;
        return &w.bufs[w.front];
    }

    /// The sample the app holds (empty until the first is taken).
    pub fn current(w: *const Worker) *const Snapshot {
        return &w.bufs[w.front];
    }

    /// Takes one sample now on the caller's thread and hands it over, as
    /// the thread does. For tests and for running without a thread.
    pub fn step(w: *Worker) void {
        std.debug.assert(w.thread == null);
        w.sampleOnce();
    }

    /// Whether the last sample has nothing to measure rates against, so
    /// the next should come soon.
    pub fn ratesPending(w: *const Worker) bool {
        return w.sampler.rates_pending or w.sampler.samples <= 1;
    }

    fn sampleOnce(w: *Worker) void {
        w.sampler.want = unpackWant(w.want.load(.acquire));
        w.sampler.collectNow();
        w.bufs[w.back].fill(&w.sampler);
        const old = w.middle.swap(w.back | fresh, .acq_rel);
        w.back = old & index_mask;
        if (w.waker) |k| k.wake(k.ctx);
    }

    fn poke(w: *Worker) void {
        _ = w.signal.fetchAdd(1, .release);
        w.io.futexWake(u32, &w.signal.raw, 1);
    }

    fn run(w: *Worker) void {
        const clock = @import("../platform/root.zig").clock;
        var next = clock.now();
        var seen = w.signal.load(.acquire);
        while (!w.stopping.load(.acquire)) {
            const left = next - clock.now();
            if (left > 0) {
                const ns: i96 = @intFromFloat(left * 1e9);
                w.io.futexWaitTimeout(u32, &w.signal.raw, seen, .{ .duration = .{ .raw = .{ .nanoseconds = ns }, .clock = .awake } }) catch {};
                const now_signal = w.signal.load(.acquire);
                if (w.stopping.load(.acquire)) break;
                // Woken early (a list opened): sample now; else keep waiting.
                if (now_signal == seen and clock.now() < next) continue;
                seen = now_signal;
            }
            w.sampleOnce();
            // On the second, not a second after each sample; soon when the
            // sample had nothing to measure rates against; after a stall, from now.
            const period: f64 = if (w.ratesPending()) 0.3 else 1.0;
            const t = clock.now();
            next = if (t - next < period) next + period else t + period;
            if (next < t) next = t + period;
        }
    }
};

fn packWant(want: root.Want) u32 {
    return @as(u32, @intFromBool(want.procs)) | @as(u32, @intFromBool(want.kernel_threads)) << 1;
}

fn unpackWant(v: u32) root.Want {
    return .{ .procs = v & 1 != 0, .kernel_threads = v & 2 != 0 };
}

test "the triple buffer hands over each sample once, and never the one being written" {
    var w = try Worker.create(std.testing.allocator, std.testing.io);
    defer w.destroy();
    try std.testing.expect(w.take() == null);
    w.step();
    const a = w.take() orelse return error.NoSample;
    try std.testing.expect(w.take() == null); // taken once
    w.step();
    w.step(); // two before the app looks: it gets the newest
    const b = w.take() orelse return error.NoSample;
    try std.testing.expectEqual(@as(u64, 3), b.samples);
    try std.testing.expect(a != b or a.samples == 3);
    // The three indices stay distinct whatever the order.
    const mid = w.middle.load(.acquire) & Worker.index_mask;
    try std.testing.expect(w.back != w.front and w.back != mid and w.front != mid);
}

test "the thread samples on its own, wakes early when asked, and stops" {
    var w = try Worker.create(std.testing.allocator, std.testing.io);
    defer w.destroy();
    w.ask(.{ .procs = false }, false);
    try w.start(null);
    const clock = @import("../platform/root.zig").clock;
    const until = clock.now() + 5;
    var got: ?*const Snapshot = null;
    while (got == null and clock.now() < until) got = w.take();
    try std.testing.expect(got != null);
    try std.testing.expect(!got.?.procs_read);
    w.ask(.{ .procs = true }, true); // a list opened: read it now, not in a second
    const asked = clock.now();
    var listed = false;
    while (!listed and clock.now() < until + 5) {
        if (w.take()) |s| listed = s.procs_read;
    }
    try std.testing.expect(listed);
    try std.testing.expect(clock.now() - asked < 0.9);
    w.stop();
    try std.testing.expect(!w.running());
}
