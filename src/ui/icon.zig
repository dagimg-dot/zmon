//! zmon's icon: the Ring, thirty ticks of sample history round a dial, on a
//! dark plate. The window carries the PNG (title bars and docks that read it
//! from the window); `zig build install` puts the rest of `assets/app` where
//! launchers and the Wayland shell look, beside `zmon.desktop`.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

pub const png = @embedFile("assets/app/zmon-256.png");
/// The same icon as a drawing, crisp at any size inside the app.
pub const svg = @embedFile("assets/app/zmon.svg");

/// The icon at `size` points, as the app shows itself (sidebar, About).
pub fn draw(c: *ui.Context, size: f32) void {
    const box = ui.div(c).size(size, size);
    defer box.end();
    ui.access.hide(c, box.index); // the name beside it says what it is
    _ = ui.svg(c, .{ .key = "zmon-icon", .bytes = svg, .size = size });
}

test "the in-app icon is an SVG drawing" {
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
}

test "the window icon is a PNG" {
    try std.testing.expect(std.mem.startsWith(u8, png, "\x89PNG\r\n\x1a\n"));
}
