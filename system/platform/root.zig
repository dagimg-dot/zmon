//! What the machine readers need from the OS: quiet file reads.
const std = @import("std");
const builtin = @import("builtin");

pub const files = switch (builtin.os.tag) {
    .linux => @import("linux/files.zig"),
    else => @import("dummy/files.zig"),
};

test "the file readers compile on every OS" {
    std.testing.refAllDecls(files);
}
