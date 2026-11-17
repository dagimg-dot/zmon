//! The one time zmon asks for root, and only when you press the button: to
//! see which of another user's processes holds a port. It runs zmon itself
//! through pkexec (`zmon --port-holders PORT`, see main.zig), which prints
//! the pids and exits; zmon reads them and shows those rows. pkexec waits
//! for your password, so this runs on a thread of its own and hands the
//! answer back through `status`.
const std = @import("std");
const system = @import("zmon-system");

pub const Status = enum(u8) { running, found, failed };

pub const Lookup = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    port: u16,
    waker: ?system.sampler.Waker,
    status: std.atomic.Value(Status) = .init(.running),
    pids: [16]i32 = undefined,
    count: u8 = 0,
    /// Why it failed, in words, when it did.
    reason: []const u8 = "",
    thread: ?std.Thread = null,

    /// Starts asking; the lookup is the caller's to `finish` once its
    /// status isn't `running`.
    pub fn start(gpa: std.mem.Allocator, io: std.Io, port: u16, waker: ?system.sampler.Waker) !*Lookup {
        const l = try gpa.create(Lookup);
        l.* = .{ .gpa = gpa, .io = io, .port = port, .waker = waker };
        l.thread = std.Thread.spawn(.{}, run, .{l}) catch |e| {
            gpa.destroy(l);
            return e;
        };
        return l;
    }

    /// Joins the thread and frees the lookup. While pkexec still waits for a
    /// password (zmon is closing), the thread is let go and its few bytes
    /// with it, rather than holding the window open.
    pub fn finish(l: *Lookup) void {
        if (l.status.load(.acquire) == .running) {
            if (l.thread) |t| t.detach();
            return;
        }
        if (l.thread) |t| t.join();
        l.gpa.destroy(l);
    }

    fn run(l: *Lookup) void {
        defer if (l.waker) |w| w.wake(w.ctx);
        var exe_buf: [std.fs.max_path_bytes]u8 = undefined;
        const n = std.os.linux.readlink("/proc/self/exe", &exe_buf, exe_buf.len);
        if (std.os.linux.errno(n) != .SUCCESS) return l.fail("zmon couldn't find its own program.");
        var port_buf: [8]u8 = undefined;
        const port = std.fmt.bufPrint(&port_buf, "{d}", .{l.port}) catch unreachable;
        const result = std.process.run(l.gpa, l.io, .{
            .argv = &.{ "pkexec", exe_buf[0..n], "--port-holders", port },
        }) catch return l.fail("pkexec couldn't be started. Is polkit installed?");
        defer l.gpa.free(result.stdout);
        defer l.gpa.free(result.stderr);
        switch (result.term) {
            .exited => |code| switch (code) {
                0 => {},
                // pkexec: 126, the prompt was dismissed; 127, not authorised or no agent.
                126 => return l.fail("The password prompt was dismissed."),
                127 => return l.fail("Not authorised, or no password prompt could be shown (no polkit agent running)."),
                else => return l.fail("The lookup didn't finish."),
            },
            else => return l.fail("The lookup didn't finish."),
        }
        l.count = @intCast(parsePids(result.stdout, &l.pids));
        l.status.store(.found, .release);
    }

    fn fail(l: *Lookup, reason: []const u8) void {
        l.reason = reason;
        l.status.store(.failed, .release);
    }
};

/// The pids the helper printed, one a line; anything else is skipped.
pub fn parsePids(text: []const u8, out: []i32) usize {
    var n: usize = 0;
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (n == out.len) break;
        const pid = std.fmt.parseInt(i32, std.mem.trim(u8, line, " \r"), 10) catch continue;
        if (pid <= 0) continue;
        out[n] = pid;
        n += 1;
    }
    return n;
}

test "the helper's answer is its pids, one a line" {
    var out: [4]i32 = undefined;
    try std.testing.expectEqual(@as(usize, 2), parsePids("812\n\nnot a pid\n-4\n3141\n", &out));
    try std.testing.expectEqualSlices(i32, &.{ 812, 3141 }, out[0..2]);
}
