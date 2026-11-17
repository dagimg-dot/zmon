//! For systems without /proc: every read fails quietly.
const std = @import("std");

pub const Error = error{ AccessDenied, Gone, Unreadable, Truncated };

pub fn read(io: std.Io, dir: std.Io.Dir, path: []const u8, buf: []u8) Error![]u8 {
    _ = .{ io, dir, path, buf };
    return error.Unreadable;
}

pub fn readWhole(io: std.Io, dir: std.Io.Dir, path: []const u8, buf: []u8) Error![]u8 {
    _ = .{ io, dir, path, buf };
    return error.Unreadable;
}

pub fn link(io: std.Io, dir: std.Io.Dir, path: []const u8, buf: []u8) ?[]u8 {
    _ = .{ io, dir, path, buf };
    return null;
}

pub fn exists(path: [*:0]const u8, readable: bool) bool {
    _ = .{ path, readable };
    return false;
}
