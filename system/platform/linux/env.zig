//! The environment the XDG directories are read from.
const std = @import("std");

/// The variable's value, or null when it is unset or empty.
pub fn get(name: [:0]const u8) ?[]const u8 {
    const v = std.c.getenv(name.ptr) orelse return null;
    const s = std.mem.span(v);
    return if (s.len == 0) null else s;
}

pub fn home() []const u8 {
    return get("HOME") orelse ".";
}
