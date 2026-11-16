//! How zmon introduces itself to the desktop. The shell finds an app's icon
//! through the name its windows carry (the Wayland app id, the X11 class),
//! which must match `zmon.desktop`.
const std = @import("std");
const builtin = @import("builtin");

const program = switch (builtin.os.tag) {
    .linux => @import("linux/program.zig"),
    else => @import("dummy/program.zig"),
};

/// Gives the program its name for the desktop. Call it before the first
/// window opens, because the toolkit reads it once per window. False when
/// there is nothing to name it with.
pub const setName = program.setName;

/// The name set by `setName`, or null before it.
pub const name = program.name;

test "the desktop backends compile on every OS" {
    std.testing.refAllDecls(program);
}

test "a named program reports that name back" {
    if (!setName("zmon")) return error.SkipZigTest;
    try std.testing.expectEqualStrings("zmon", name().?);
}
