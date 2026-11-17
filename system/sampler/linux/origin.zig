//! Why a process is running, beyond its parents: the systemd unit that
//! keeps it (its description and file), the Git repository it works in,
//! and the network sockets it holds. Read for the selected process only,
//! and for a port being searched for. A process's open files are readable
//! only for the user's own processes: for the rest, sockets stay unknown.
const std = @import("std");
const core = @import("zmon-core");
const files = @import("../../platform/root.zig").files;

const dev = core.devices;
pub const Socket = core.Socket;

/// The folders systemd reads units from, system-wide then per user.
const system_dirs = [_][]const u8{ "/etc/systemd/system", "/run/systemd/system", "/usr/lib/systemd/system", "/lib/systemd/system" };
const user_dirs = [_][]const u8{ "/etc/systemd/user", "/usr/lib/systemd/user" };

/// A unit's Description and the file it was read from, copied into `a`.
pub fn unitInfo(io: std.Io, a: std.mem.Allocator, unit: []const u8, home: []const u8) ?struct { description: []const u8, file: []const u8 } {
    if (unit.len == 0) return null;
    // A scope is made at run time and has no file; an instance (getty@tty1)
    // reads its template (getty@.service).
    if (std.mem.endsWith(u8, unit, ".scope")) return null;
    var name_buf: [128]u8 = undefined;
    const name = if (std.mem.indexOfScalar(u8, unit, '@')) |at| blk: {
        const dot = std.mem.lastIndexOfScalar(u8, unit, '.') orelse unit.len;
        break :blk std.fmt.bufPrint(&name_buf, "{s}@{s}", .{ unit[0..at], unit[dot..] }) catch unit;
    } else unit;
    var path: [256]u8 = undefined;
    var buf: [8192]u8 = undefined;
    var user_buf: [192]u8 = undefined;
    const user_home = std.fmt.bufPrint(&user_buf, "{s}/.config/systemd/user", .{home}) catch "";
    const dirs = [_][]const u8{user_home} ++ system_dirs ++ user_dirs;
    for (dirs) |d| {
        if (d.len == 0) continue;
        const p = std.fmt.bufPrint(&path, "{s}/{s}", .{ d, name }) catch continue;
        const text = files.read(io, .cwd(), p, &buf) catch continue;
        return .{
            .description = a.dupe(u8, iniValue(text, "Description") orelse "") catch "",
            .file = a.dupe(u8, p) catch "",
        };
    }
    return null;
}

/// The value of `key=` in a unit file's text.
pub fn iniValue(text: []const u8, key: []const u8) ?[]const u8 {
    var lines = std.mem.tokenizeScalar(u8, text, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len <= key.len or !std.mem.startsWith(u8, line, key)) continue;
        if (line[key.len] != '=') continue;
        return std.mem.trim(u8, line[key.len + 1 ..], " \t");
    }
    return null;
}

/// The Git repository `cwd` is in: its folder's name and the branch checked
/// out (or the commit, when none is). Looks up at most 32 folders.
pub fn gitRepo(io: std.Io, a: std.mem.Allocator, cwd: []const u8) ?struct { name: []const u8, branch: []const u8 } {
    if (cwd.len == 0 or cwd[0] != '/') return null;
    var dir = cwd;
    var path: [1100]u8 = undefined;
    var buf: [256]u8 = undefined;
    for (0..32) |_| {
        const p = std.fmt.bufPrint(&path, "{s}/.git/HEAD", .{if (dir.len == 1) "" else dir}) catch return null;
        if (files.read(io, .cwd(), p, &buf)) |head| {
            return .{ .name = a.dupe(u8, std.fs.path.basename(dir)) catch "", .branch = a.dupe(u8, branchOf(head)) catch "" };
        } else |_| {}
        if (dir.len <= 1) return null;
        dir = std.fs.path.dirname(dir) orelse return null;
    }
    return null;
}

/// "ref: refs/heads/main" names the branch; a bare commit, its first 7.
pub fn branchOf(head: []const u8) []const u8 {
    const h = std.mem.trim(u8, head, " \n");
    if (std.mem.cutPrefix(u8, h, "ref: refs/heads/")) |b| return b;
    return h[0..@min(7, h.len)];
}

/// The sockets of `pid` (only the user's own can be read): what it listens
/// on and what it is connected to, by matching its open files' socket
/// numbers against the kernel's TCP and UDP tables.
pub fn sockets(io: std.Io, pid: i32, out: []Socket) ?usize {
    var inodes: [512]u64 = undefined;
    const n_inodes = socketInodes(io, pid, &inodes) orelse return null;
    if (n_inodes == 0) return 0;
    var n: usize = 0;
    var buf: [65536]u8 = undefined;
    for ([_]struct { path: []const u8, proto: []const u8, v6: bool }{
        .{ .path = "/proc/net/tcp", .proto = "TCP", .v6 = false },
        .{ .path = "/proc/net/tcp6", .proto = "TCP", .v6 = true },
        .{ .path = "/proc/net/udp", .proto = "UDP", .v6 = false },
        .{ .path = "/proc/net/udp6", .proto = "UDP", .v6 = true },
    }) |table| {
        const text = files.readWhole(io, .cwd(), table.path, &buf) catch continue;
        var lines = std.mem.tokenizeScalar(u8, text, '\n');
        _ = lines.next();
        while (lines.next()) |line| {
            if (n == out.len) return n;
            const e = parseEntry(line) orelse continue;
            if (std.mem.indexOfScalar(u64, inodes[0..n_inodes], e.inode) == null) continue;
            out[n] = describe(e, table.proto, table.v6);
            n += 1;
        }
    }
    return n;
}

/// The socket numbers among `pid`'s open files; null when they can't be read.
fn socketInodes(io: std.Io, pid: i32, out: []u64) ?usize {
    var path: [48]u8 = undefined;
    const fd_dir = std.fmt.bufPrint(&path, "/proc/{d}/fd", .{pid}) catch return null;
    var dir = std.Io.Dir.cwd().openDir(io, fd_dir, .{ .iterate = true }) catch return null;
    defer dir.close(io);
    var it = dir.iterate();
    var n: usize = 0;
    var link_buf: [64]u8 = undefined;
    while (it.next(io) catch null) |e| {
        if (n == out.len) break;
        const target = files.link(io, dir, e.name, &link_buf) orelse continue;
        const inode = socketInode(target) orelse continue;
        out[n] = inode;
        n += 1;
    }
    return n;
}

/// "socket:[4534502]" is socket number 4534502.
pub fn socketInode(target: []const u8) ?u64 {
    const rest = std.mem.cutPrefix(u8, target, "socket:[") orelse return null;
    return std.fmt.parseInt(u64, std.mem.trimEnd(u8, rest, "]"), 10) catch null;
}

pub const Entry = struct { local: []const u8, remote: []const u8, state: u8, uid: u32, inode: u64 };

/// One line of /proc/net/{tcp,udp}{,6}.
pub fn parseEntry(line: []const u8) ?Entry {
    var f = std.mem.tokenizeScalar(u8, line, ' ');
    _ = f.next() orelse return null; // sl
    const local = f.next() orelse return null;
    const remote = f.next() orelse return null;
    const state = std.fmt.parseInt(u8, f.next() orelse return null, 16) catch return null;
    _ = f.next(); // tx:rx queue
    _ = f.next(); // timer
    _ = f.next(); // retransmits
    const uid = std.fmt.parseInt(u32, f.next() orelse return null, 10) catch return null;
    _ = f.next(); // timeout
    const inode = std.fmt.parseInt(u64, f.next() orelse return null, 10) catch return null;
    return .{ .local = local, .remote = remote, .state = state, .uid = uid, .inode = inode };
}

/// The port of an "ADDR:PORT" field (the port is hex).
pub fn portOf(field: []const u8) u16 {
    const colon = std.mem.lastIndexOfScalar(u8, field, ':') orelse return 0;
    return std.fmt.parseInt(u16, field[colon + 1 ..], 16) catch 0;
}

/// TCP's LISTEN state, or an unconnected UDP socket.
fn listening(e: Entry, proto: []const u8) bool {
    if (std.mem.eql(u8, proto, "TCP")) return e.state == 0x0A;
    return portOf(e.remote) == 0;
}

fn describe(e: Entry, proto: []const u8, v6: bool) Socket {
    var s: Socket = .{ .proto = .init(proto), .listening = listening(e, proto) };
    var buf: [128]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    address(&w, e.local, v6);
    if (!s.listening) {
        w.writeAll(" → ") catch {};
        address(&w, e.remote, v6);
    }
    s.text = .init(w.buffered());
    return s;
}

/// Writes "127.0.0.1:5000" or "[::1]:5000" from the kernel's hex form, in
/// which each 32-bit word is in the machine's own byte order.
pub fn address(w: *std.Io.Writer, field: []const u8, v6: bool) void {
    const colon = std.mem.lastIndexOfScalar(u8, field, ':') orelse return;
    const hex = field[0..colon];
    const port = portOf(field);
    if (!v6 and hex.len == 8) {
        const word = std.fmt.parseInt(u32, hex, 16) catch return;
        const b: [4]u8 = @bitCast(std.mem.nativeToBig(u32, word));
        // The kernel prints the word as the machine holds it: undo that.
        const ip: [4]u8 = if (@import("builtin").cpu.arch.endian() == .little) .{ b[3], b[2], b[1], b[0] } else b;
        w.print("{d}.{d}.{d}.{d}:{d}", .{ ip[0], ip[1], ip[2], ip[3], port }) catch {};
        return;
    }
    if (v6 and hex.len == 32) {
        var bytes: [16]u8 = undefined;
        for (0..4) |i| {
            const word = std.fmt.parseInt(u32, hex[i * 8 ..][0..8], 16) catch return;
            const be: [4]u8 = @bitCast(std.mem.nativeToBig(u32, word));
            const host: [4]u8 = if (@import("builtin").cpu.arch.endian() == .little) .{ be[3], be[2], be[1], be[0] } else be;
            @memcpy(bytes[i * 4 ..][0..4], &host);
        }
        w.writeByte('[') catch {};
        var all_zero = true;
        for (bytes) |x| all_zero = all_zero and x == 0;
        if (all_zero) {
            w.writeAll("::") catch {};
        } else for (0..8) |g| {
            if (g > 0) w.writeByte(':') catch {};
            w.print("{x}", .{@as(u16, bytes[g * 2]) << 8 | bytes[g * 2 + 1]}) catch {};
        }
        w.print("]:{d}", .{port}) catch {};
    }
}

/// Who holds `port`: the user's own processes by pid (their open files can
/// be read), and the owner of any socket on it whose process can't be.
pub const Holders = struct {
    pids: [16]i32 = undefined,
    count: u8 = 0,
    /// A socket on the port belongs to another user: zmon can't see which
    /// process without root. Their uid, or null.
    other_uid: ?u32 = null,
};

/// `all`: every socket on the port, whoever owns it (as root, every
/// process's open files can be read).
pub fn holders(io: std.Io, port: u16, me: u32, all: bool) Holders {
    var h: Holders = .{};
    var want: [64]u64 = undefined;
    var n_want: usize = 0;
    var buf: [65536]u8 = undefined;
    for ([_][]const u8{ "/proc/net/tcp", "/proc/net/tcp6", "/proc/net/udp", "/proc/net/udp6" }) |table| {
        const text = files.readWhole(io, .cwd(), table, &buf) catch continue;
        var lines = std.mem.tokenizeScalar(u8, text, '\n');
        _ = lines.next();
        while (lines.next()) |line| {
            const e = parseEntry(line) orelse continue;
            if (portOf(e.local) != port or e.inode == 0) continue;
            if (e.uid != me and !all) {
                h.other_uid = e.uid;
                continue;
            }
            if (n_want < want.len) {
                want[n_want] = e.inode;
                n_want += 1;
            }
        }
    }
    if (n_want == 0) return h;
    var dir = std.Io.Dir.cwd().openDir(io, "/proc", .{ .iterate = true }) catch return h;
    defer dir.close(io);
    var it = dir.iterate();
    var inodes: [512]u64 = undefined;
    while (it.next(io) catch null) |e| {
        if (h.count == h.pids.len) break;
        const pid = std.fmt.parseInt(i32, e.name, 10) catch continue;
        const n = socketInodes(io, pid, &inodes) orelse continue;
        for (inodes[0..n]) |inode| if (std.mem.indexOfScalar(u64, want[0..n_want], inode) != null) {
            h.pids[h.count] = pid;
            h.count += 1;
            break;
        };
    }
    return h;
}

test "a unit file's description is its Description= line" {
    const text = "[Unit]\nDescription=Docker Application Container Engine\nDocumentation=https://docs.docker.com\n[Service]\nExecStart=/usr/bin/dockerd\n";
    try std.testing.expectEqualStrings("Docker Application Container Engine", iniValue(text, "Description").?);
    try std.testing.expect(iniValue(text, "Desc") == null);
}

test "HEAD names the branch, or the commit when none is checked out" {
    try std.testing.expectEqualStrings("main", branchOf("ref: refs/heads/main\n"));
    try std.testing.expectEqualStrings("feature/x", branchOf("ref: refs/heads/feature/x\n"));
    try std.testing.expectEqualStrings("3f2a9c1", branchOf("3f2a9c1d0e5b7a8c9d0e1f2a3b4c5d6e7f8a9b0c\n"));
}

test "socket table lines give addresses, state, owner and number" {
    const e = parseEntry("   0: 0100007F:14B4 00000000:0000 0A 00000000:00000000 00:00000000 00000000  1001        0 4534502 1 0000000073d686d5 100 0 0 10 0").?;
    try std.testing.expectEqual(@as(u16, 5300), portOf(e.local));
    try std.testing.expectEqual(@as(u8, 0x0A), e.state);
    try std.testing.expectEqual(@as(u32, 1001), e.uid);
    try std.testing.expectEqual(@as(u64, 4534502), e.inode);
    const s = describe(e, "TCP", false);
    try std.testing.expect(s.listening);
    if (@import("builtin").cpu.arch.endian() == .little) try std.testing.expectEqualStrings("127.0.0.1:5300", s.text.slice());
    try std.testing.expectEqual(@as(?u64, 4534502), socketInode("socket:[4534502]"));
    try std.testing.expect(socketInode("pipe:[48694804]") == null);
}

test "IPv6 any-address prints as [::]" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    address(&w, "00000000000000000000000000000000:14EB", true);
    try std.testing.expectEqualStrings("[::]:5355", w.buffered());
}

test "this machine: a unit file is found, and this test's own sockets can be read" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var out: [8]Socket = undefined;
    try std.testing.expect(sockets(std.testing.io, std.os.linux.getpid(), &out) != null); // ours: readable
    _ = unitInfo(std.testing.io, arena.allocator(), "systemd-journald.service", "/nonexistent");
}
