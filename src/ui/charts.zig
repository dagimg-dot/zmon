//! Live charts drawn on a nanoui canvas: a filled line over a history that
//! scrolls in from the right, with faint gridlines.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");

pub const Options = struct {
    height: f32 = 160,
    /// The value at the top of the chart; null scales to the history, with a floor.
    max: ?f32 = null,
    floor: f32 = 1,
    color: ui.Color,
    grid: ui.Color,
    /// A second history drawn over the first (writes over reads, upload over download).
    second: ?*const core.Ring(f32) = null,
    grid_lines: u32 = 4,
    /// How many of the newest samples the chart spans (one a second).
    window: usize = 60,
};

/// The top of a chart for these histories: the largest value with headroom,
/// never below `floor`.
pub fn scale(a: *const core.Ring(f32), b: ?*const core.Ring(f32), floor: f32, window: usize) f32 {
    var m = a.maxOfNewest(window);
    if (b) |r| m = @max(m, r.maxOfNewest(window));
    return @max(floor, m * 1.15);
}

pub fn area(c: *ui.Context, ring: *const core.Ring(f32), o: Options) void {
    const cv = ui.canvas(c, .{ .width = .fill, .height = .{ .px = o.height } });
    const w = cv.size.w;
    const h = cv.size.h;
    if (w < 2 or h < 2) return;
    const top = o.max orelse scale(ring, o.second, o.floor, o.window);

    var i: u32 = 1;
    while (i <= o.grid_lines) : (i += 1) {
        const y = h * @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(o.grid_lines + 1));
        cv.line(.{ .x = 0, .y = y }, .{ .x = w, .y = y }, .{ .width = 1, .color = o.grid });
    }
    series(c, cv, ring, o.window, w, h, top, o.color, true);
    if (o.second) |r| series(c, cv, r, o.window, w, h, top, o.color.alpha(0.55), false);
}

fn series(c: *ui.Context, cv: *ui.Canvas, ring: *const core.Ring(f32), window: usize, w: f32, h: f32, top: f32, color: ui.Color, fill: bool) void {
    const n = @min(ring.len, window);
    if (n < 2) return;
    const first = ring.len - n;
    // An hour is 3600 samples in a few hundred pixels: one point per pixel,
    // the highest sample in it, so a short spike still shows.
    const step = @max(1, window / @max(1, @as(usize, @intFromFloat(w))));
    const count = (n + step - 1) / step;
    if (count < 2) return;
    const pts = c.alloc().alloc(ui.Point, count) catch return;
    const span: f32 = @floatFromInt(window - 1);
    const offset: f32 = @floatFromInt(window - n);
    for (pts, 0..) |*p, k| {
        const from = k * step;
        var peak: f32 = 0;
        for (from..@min(n, from + step)) |j| peak = @max(peak, ring.at(first + j));
        const v = std.math.clamp(peak / top, 0, 1);
        p.* = .{ .x = w * (offset + @as(f32, @floatFromInt(from))) / span, .y = h - 1 - v * (h - 2) };
    }
    const n_pts = pts.len;
    if (fill) {
        const poly = c.alloc().alloc(ui.Point, n_pts + 2) catch return;
        @memcpy(poly[0..n_pts], pts);
        poly[n_pts] = .{ .x = pts[n_pts - 1].x, .y = h };
        poly[n_pts + 1] = .{ .x = pts[0].x, .y = h };
        cv.fill(poly, color.alpha(0.14));
    }
    cv.polyline(pts, .{ .width = 1.6, .color = color });
}

/// A small chart for a tile: no gridlines, no second series.
pub fn spark(c: *ui.Context, ring: *const core.Ring(f32), height: f32, max: ?f32, color: ui.Color) void {
    area(c, ring, .{ .height = height, .max = max, .color = color, .grid = .hex(0x00000000), .grid_lines = 0 });
}
