//! zmon's icon: the Ring, thirty ticks of sample history round a dial, on a
//! dark plate. The window carries the PNG (title bars and docks that read it
//! from the window); `zig build install` puts the rest of `assets/app` where
//! launchers and the Wayland shell look, beside `zmon.desktop`.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const motion = @import("motion.zig");

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

/// Readings for the Ring's ticks, from the logo (design/logo.html), 0 to 1.
const levels = [_]f32{ 0.35, 0.5, 0.8, 0.6, 0.4, 0.55, 0.9, 1, 0.7, 0.45, 0.3, 0.4, 0.6, 0.5, 0.35, 0.3, 0.45, 0.7, 0.85, 0.6, 0.4, 0.5, 0.65, 0.9, 0.75, 0.5, 0.35, 0.3, 0.4, 0.3 };

/// The Ring, live, `size` points wide: its ticks are readings round a dial,
/// and a new one comes in every tenth of a second, so the history rolls
/// round as in the logo's Live mode. For waiting on the first readings.
/// The logo's medium cut: twenty ticks on a 64-unit grid. Still under
/// Reduce motion.
pub fn live(c: *ui.Context, size: f32, color: ui.Color) void {
    const ticks = 20;
    const n = motion.step(c, 0.1);
    const cv = ui.canvas(c, .{ .width = .{ .px = size }, .height = .{ .px = size } });
    const unit = size / 64;
    const mid: ui.Point = .{ .x = size / 2, .y = size / 2 };
    for (0..ticks) |i| {
        const v = levels[(i * levels.len / ticks + n) % levels.len];
        const angle = (-90 + @as(f32, @floatFromInt(i)) * 360 / ticks) * std.math.pi / 180;
        const dir: ui.Point = .{ .x = @cos(angle), .y = @sin(angle) };
        const inner = 11.5 * unit;
        const outer = inner + (4 + 13 * v) * unit;
        cv.line(
            .{ .x = mid.x + dir.x * inner, .y = mid.y + dir.y * inner },
            .{ .x = mid.x + dir.x * outer, .y = mid.y + dir.y * outer },
            .{ .width = 3.4 * unit, .color = color },
        );
    }
}

test "the in-app icon is an SVG drawing" {
    try std.testing.expect(std.mem.indexOf(u8, svg, "<svg") != null);
}

test "the window icon is a PNG" {
    try std.testing.expect(std.mem.startsWith(u8, png, "\x89PNG\r\n\x1a\n"));
}
