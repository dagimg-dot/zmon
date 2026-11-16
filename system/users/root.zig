//! Who owns a process, by name: the machine's accounts, read once.
const std = @import("std");
const builtin = @import("builtin");

const backend = switch (builtin.os.tag) {
    .linux => @import("linux/root.zig"),
    else => @import("dummy/root.zig"),
};

/// User names by uid. A uid with no account shows as its number.
pub const Users = backend.Users;

test "the users backend compiles on every OS" {
    std.testing.refAllDecls(backend);
    std.testing.refAllDecls(Users);
}
