//! No windows where zmon doesn't know the compositor.
const std = @import("std");
const core = @import("zmon-core");

pub fn list(io: std.Io, out: []core.Window) usize {
    _ = .{ io, out };
    return 0;
}
