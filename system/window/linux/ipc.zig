//! One request to a compositor's Unix socket and its whole reply, with a
//! short timeout either way.
const std = @import("std");
const linux = std.os.linux;

pub const Framing = enum {
    /// One line of JSON (niri).
    line,
    /// i3's binary header, then the payload (sway).
    i3,
    /// Whatever arrives until the compositor closes (Hyprland).
    until_closed,
};

/// The reply to `request` on the socket at `path`, in `a`; null when the
/// compositor can't be reached or doesn't answer in time.
pub fn ask(a: std.mem.Allocator, path: []const u8, request: []const u8, framing: Framing) ?[]const u8 {
    const fd_rc = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
    if (linux.errno(fd_rc) != .SUCCESS) return null;
    const fd: i32 = @intCast(fd_rc);
    defer _ = linux.close(fd);
    var addr: linux.sockaddr.un = .{ .path = @splat(0) };
    if (path.len >= addr.path.len) return null;
    @memcpy(addr.path[0..path.len], path);
    // A compositor that doesn't answer in a quarter second is left alone.
    const tv: linux.timeval = .{ .sec = 0, .usec = 250_000 };
    _ = linux.setsockopt(fd, linux.SOL.SOCKET, linux.SO.RCVTIMEO, std.mem.asBytes(&tv), @sizeOf(linux.timeval));
    _ = linux.setsockopt(fd, linux.SOL.SOCKET, linux.SO.SNDTIMEO, std.mem.asBytes(&tv), @sizeOf(linux.timeval));
    if (linux.errno(linux.connect(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.un))) != .SUCCESS) return null;
    var sent: usize = 0;
    while (sent < request.len) {
        const rc = linux.write(fd, request[sent..].ptr, request.len - sent);
        if (linux.errno(rc) != .SUCCESS or rc == 0) return null;
        sent += rc;
    }
    var reply: std.ArrayList(u8) = .empty;
    var chunk: [16384]u8 = undefined;
    while (reply.items.len < 4 * 1024 * 1024) {
        const rc = linux.read(fd, &chunk, chunk.len);
        if (linux.errno(rc) != .SUCCESS) break;
        if (rc == 0) break;
        reply.appendSlice(a, chunk[0..rc]) catch return null;
        if (complete(reply.items, framing)) break;
    }
    return if (reply.items.len > 0) reply.items else null;
}

fn complete(have: []const u8, framing: Framing) bool {
    return switch (framing) {
        .line => std.mem.indexOfScalar(u8, have, '\n') != null,
        .i3 => have.len >= 14 and have.len >= 14 + std.mem.readInt(u32, have[6..10], .little),
        .until_closed => false,
    };
}
