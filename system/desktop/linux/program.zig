//! GLib keeps the program's name, and GTK takes the window's app id from it.
//! nanoui never sets it, so without this every window is "GTK Application"
//! and the shell can't match zmon to its desktop entry or icon. GLib is
//! loaded the way nanoui loads it, so both share the one copy.
const std = @import("std");

const SetPrgname = *const fn (name: [*:0]const u8) callconv(.c) void;
const GetPrgname = *const fn () callconv(.c) ?[*:0]const u8;

fn glib(comptime T: type, symbol: [:0]const u8) ?T {
    const lib = std.c.dlopen("libglib-2.0.so.0", .{ .NOW = true, .GLOBAL = true }) orelse return null;
    return @ptrCast(@alignCast(std.c.dlsym(lib, symbol) orelse return null));
}

/// False when GLib isn't installed, and then no window will need the name.
pub fn setName(program: [:0]const u8) bool {
    const set = glib(SetPrgname, "g_set_prgname") orelse return false;
    set(program.ptr);
    return true;
}

pub fn name() ?[]const u8 {
    const get = glib(GetPrgname, "g_get_prgname") orelse return null;
    return std.mem.span(get() orelse return null);
}
