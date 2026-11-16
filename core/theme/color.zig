//! Colours as theme files write them, and the few operations themes are derived
//! with. Theme files come from vicinae, which hands colour strings to Qt, so
//! eight hex digits mean `#AARRGGBB` (alpha first), not CSS's `#RRGGBBAA`.
const std = @import("std");

pub const Rgba = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,

    pub const white: Rgba = .{ .r = 255, .g = 255, .b = 255 };
    pub const black: Rgba = .{};

    /// "#rgb", "#rrggbb" or "#aarrggbb", with or without the "#"; null otherwise.
    pub fn parse(text: []const u8) ?Rgba {
        const t = std.mem.trim(u8, text, " \t");
        const h = if (t.len > 0 and t[0] == '#') t[1..] else t;
        for (h) |ch| if (!std.ascii.isHex(ch)) return null;
        return switch (h.len) {
            3 => .{ .r = nib(h[0]) * 17, .g = nib(h[1]) * 17, .b = nib(h[2]) * 17 },
            6 => .{ .r = byte(h[0..2]), .g = byte(h[2..4]), .b = byte(h[4..6]) },
            8 => .{ .a = byte(h[0..2]), .r = byte(h[2..4]), .g = byte(h[4..6]), .b = byte(h[6..8]) },
            else => null,
        };
    }

    /// `a` blended toward `b` by `t` (0 is `a`, 1 is `b`), alpha included.
    pub fn mix(a: Rgba, b: Rgba, t: f32) Rgba {
        return .{ .r = lerp(a.r, b.r, t), .g = lerp(a.g, b.g, t), .b = lerp(a.b, b.b, t), .a = lerp(a.a, b.a, t) };
    }

    /// The same colour at `alpha` (0 to 1) of its opacity.
    pub fn withAlpha(c: Rgba, alpha: f32) Rgba {
        var out = c;
        out.a = @intFromFloat(@round(@as(f32, @floatFromInt(c.a)) * std.math.clamp(alpha, 0, 1)));
        return out;
    }

    /// The opaque colour `c` shows as over `bg`.
    pub fn over(c: Rgba, bg: Rgba) Rgba {
        const t = @as(f32, @floatFromInt(c.a)) / 255;
        var out = mix(bg, c, t);
        out.a = 255;
        return out;
    }

    /// Qt's QColor::darker: the HSV value divided by `factor` / 100 (110 is about 9% darker).
    pub fn darker(c: Rgba, factor: u32) Rgba {
        if (factor == 0) return c;
        var hsv = toHsv(c);
        hsv.v = hsv.v * 100 / @as(f32, @floatFromInt(factor));
        return fromHsv(hsv, c.a);
    }

    /// Qt's QColor::lighter: the HSV value times `factor` / 100; past white, saturation gives way.
    pub fn lighter(c: Rgba, factor: u32) Rgba {
        var hsv = toHsv(c);
        var v = hsv.v * @as(f32, @floatFromInt(factor)) / 100;
        if (v > 1) {
            hsv.s = @max(0, hsv.s - (v - 1));
            v = 1;
        }
        hsv.v = v;
        return fromHsv(hsv, c.a);
    }

    /// WCAG relative luminance, 0 (black) to 1 (white).
    pub fn luminance(c: Rgba) f32 {
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b);
    }

    /// WCAG contrast ratio between two opaque colours, 1 to 21.
    pub fn contrast(a: Rgba, b: Rgba) f32 {
        const la = luminance(a);
        const lb = luminance(b);
        return (@max(la, lb) + 0.05) / (@min(la, lb) + 0.05);
    }

    pub fn eql(a: Rgba, b: Rgba) bool {
        return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a;
    }
};

fn nib(ch: u8) u8 {
    return std.fmt.charToDigit(ch, 16) catch 0;
}

fn byte(two: []const u8) u8 {
    return nib(two[0]) * 16 + nib(two[1]);
}

fn lerp(a: u8, b: u8, t: f32) u8 {
    const x = @as(f32, @floatFromInt(a)) + (@as(f32, @floatFromInt(b)) - @as(f32, @floatFromInt(a))) * std.math.clamp(t, 0, 1);
    return @intFromFloat(@round(x));
}

fn linear(v: u8) f32 {
    const c = @as(f32, @floatFromInt(v)) / 255;
    return if (c <= 0.04045) c / 12.92 else std.math.pow(f32, (c + 0.055) / 1.055, 2.4);
}

const Hsv = struct { h: f32, s: f32, v: f32 };

fn toHsv(c: Rgba) Hsv {
    const r = @as(f32, @floatFromInt(c.r)) / 255;
    const g = @as(f32, @floatFromInt(c.g)) / 255;
    const b = @as(f32, @floatFromInt(c.b)) / 255;
    const hi = @max(r, @max(g, b));
    const lo = @min(r, @min(g, b));
    const d = hi - lo;
    var h: f32 = 0;
    if (d > 0) {
        if (hi == r) h = @mod((g - b) / d, 6) else if (hi == g) h = (b - r) / d + 2 else h = (r - g) / d + 4;
        h *= 60;
    }
    return .{ .h = h, .s = if (hi == 0) 0 else d / hi, .v = hi };
}

fn fromHsv(hsv: Hsv, a: u8) Rgba {
    const c = hsv.v * hsv.s;
    const x = c * (1 - @abs(@mod(hsv.h / 60, 2) - 1));
    const m = hsv.v - c;
    const sector: u32 = @intFromFloat(@floor(@mod(hsv.h, 360) / 60));
    const rgb: [3]f32 = switch (sector) {
        0 => .{ c, x, 0 },
        1 => .{ x, c, 0 },
        2 => .{ 0, c, x },
        3 => .{ 0, x, c },
        4 => .{ x, 0, c },
        else => .{ c, 0, x },
    };
    return .{
        .r = @intFromFloat(@round((rgb[0] + m) * 255)),
        .g = @intFromFloat(@round((rgb[1] + m) * 255)),
        .b = @intFromFloat(@round((rgb[2] + m) * 255)),
        .a = a,
    };
}

test "hex colours: six digits, three digits, and eight with alpha first as Qt reads them" {
    try std.testing.expect(Rgba.parse("#1E1E2E").?.eql(.{ .r = 0x1e, .g = 0x1e, .b = 0x2e }));
    try std.testing.expect(Rgba.parse("fff").?.eql(Rgba.white));
    try std.testing.expect(Rgba.parse("#bb2e2e32").?.eql(.{ .a = 0xbb, .r = 0x2e, .g = 0x2e, .b = 0x32 }));
    try std.testing.expect(Rgba.parse("#12345") == null);
    try std.testing.expect(Rgba.parse("colors.core.accent") == null);
}

test "mixing, alpha and compositing" {
    const black = Rgba.black;
    const white = Rgba.white;
    try std.testing.expect(Rgba.mix(black, white, 0.5).eql(.{ .r = 128, .g = 128, .b = 128 }));
    try std.testing.expectEqual(@as(u8, 179), white.withAlpha(0.7).a);
    try std.testing.expect(white.withAlpha(0.5).over(black).eql(.{ .r = 128, .g = 128, .b = 128 }));
}

test "darker and lighter follow Qt's HSV value scaling" {
    // Qt: QColor("#41425d").darker(110) == #3b3c55
    try std.testing.expect(Rgba.parse("#41425d").?.darker(110).eql(Rgba.parse("#3b3c55").?));
    try std.testing.expect(Rgba.parse("#808080").?.lighter(150).eql(Rgba.parse("#c0c0c0").?));
    try std.testing.expect(Rgba.white.lighter(150).eql(Rgba.white));
}

test "contrast ratio is 21 for black on white and 1 for a colour on itself" {
    try std.testing.expectApproxEqAbs(@as(f32, 21), Rgba.contrast(Rgba.black, Rgba.white), 0.01);
    try std.testing.expectApproxEqAbs(@as(f32, 1), Rgba.contrast(Rgba.white, Rgba.white), 0.001);
}
