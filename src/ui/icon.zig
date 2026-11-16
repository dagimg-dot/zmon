//! zmon's icon: the Ring, thirty ticks of sample history round a dial, on a
//! dark plate. The window carries the PNG (title bars and docks that read it
//! from the window); `zig build install` puts the rest of `assets/app` where
//! launchers and the Wayland shell look, beside `zmon.desktop`.
const std = @import("std");

pub const png = @embedFile("assets/app/zmon-256.png");

test "the window icon is a PNG" {
    try std.testing.expect(std.mem.startsWith(u8, png, "\x89PNG\r\n\x1a\n"));
}
