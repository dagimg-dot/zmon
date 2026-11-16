//! Small, quiet file readers for /proc, /sys and the data directories.
//!
//! These files can be opened and then refuse to be read (another user's
//! process, a process that exited in between). Zig's own file reader treats
//! those errnos as bugs and prints a stack trace, so reads go straight to
//! the kernel and report plain errors instead.
const std = @import("std");
const linux = std.os.linux;

pub const Error = error{ AccessDenied, Gone, Unreadable };

/// Reads up to `buf.len` bytes of `path` (relative to `dir`) into `buf`.
pub fn read(io: std.Io, dir: std.Io.Dir, path: []const u8, buf: []u8) Error![]u8 {
    const file = dir.openFile(io, path, .{}) catch |e| return switch (e) {
        error.AccessDenied, error.PermissionDenied => error.AccessDenied,
        error.FileNotFound => error.Gone,
        else => error.Unreadable,
    };
    defer file.close(io);
    var n: usize = 0;
    while (n < buf.len) {
        const rc = linux.read(file.handle, buf[n..].ptr, buf.len - n);
        switch (linux.errno(rc)) {
            .SUCCESS => {
                if (rc == 0) break;
                n += rc;
            },
            .INTR => continue,
            .ACCES, .PERM => return error.AccessDenied,
            .SRCH, .NOENT => return error.Gone,
            else => return error.Unreadable,
        }
    }
    return buf[0..n];
}

/// The target of the symbolic link `path` (relative to `dir`), or null.
pub fn link(io: std.Io, dir: std.Io.Dir, path: []const u8, buf: []u8) ?[]u8 {
    _ = io;
    var z: [128:0]u8 = undefined;
    if (path.len >= z.len) return null;
    @memcpy(z[0..path.len], path);
    z[path.len] = 0;
    const rc = linux.readlinkat(dir.handle, &z, buf.ptr, buf.len);
    if (linux.errno(rc) != .SUCCESS) return null;
    return buf[0..rc];
}
