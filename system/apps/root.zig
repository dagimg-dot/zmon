//! Apps: the launcher entries a machine has, their icons, and the grouping of
//! processes into apps, background services and kernel threads. Where the
//! entries and icons come from depends on the OS.
const std = @import("std");
const builtin = @import("builtin");

const platform = switch (builtin.os.tag) {
    .linux => @import("linux/root.zig"),
    else => @import("dummy/root.zig"),
};

pub const grouping = @import("grouping.zig");

pub const Entry = platform.Entry;
pub const Index = platform.Index;
pub const loadEntries = platform.loadEntries;
pub const Icons = platform.Icons;
pub const Icon = platform.Icon;
pub const IconKind = platform.IconKind;

pub const Kind = grouping.Kind;
pub const Group = grouping.Group;
pub const group = grouping.build;

// See the sampler: referencing the declarations makes a cross-compile check analyse them.
test "the apps backend compiles on every OS" {
    std.testing.refAllDecls(platform);
    std.testing.refAllDecls(Index);
    std.testing.refAllDecls(Icons);
    std.testing.refAllDecls(grouping);
}
