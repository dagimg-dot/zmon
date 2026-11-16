//! The active theme's colours, as the pages and nanoui's widgets use them. A
//! theme's palette is resolved once when it loads (core/theme); this only
//! turns it into nanoui colours, which is cheap enough to do every frame.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const Color = ui.Color;
const core = @import("zmon-core");
const fonts = @import("fonts.zig");

const Theme = core.themes.Theme;
const Rgba = core.themes.Rgba;

pub const Colors = struct {
    dark: bool,
    page: Color,
    panel: Color,
    card: Color,
    text: Color,
    secondary: Color,
    tertiary: Color,
    separator: Color,
    border: Color,
    hover: Color,
    selected: Color,
    selected_text: Color,
    stripe: Color,
    accent: Color,
    accent_text: Color,
    danger: Color,
    success: Color,
    /// One colour per device graph: the theme's accents, or its text when graphs are plain.
    cpu: Color,
    memory: Color,
    disk: Color,
    network: Color,
};

/// A theme colour as nanoui draws it.
pub fn color(c: Rgba) Color {
    return .{
        .r = @as(f32, @floatFromInt(c.r)) / 255,
        .g = @as(f32, @floatFromInt(c.g)) / 255,
        .b = @as(f32, @floatFromInt(c.b)) / 255,
        .a = @as(f32, @floatFromInt(c.a)) / 255,
    };
}

pub fn colors(t: *const Theme, colored_graphs: bool) Colors {
    const text = color(t.color(.foreground));
    return .{
        .dark = t.dark,
        .page = color(t.color(.background)),
        .panel = color(t.color(.panel)),
        .card = color(t.color(.card)),
        .text = text,
        .secondary = color(t.color(.muted)),
        .tertiary = color(t.color(.placeholder)),
        .separator = color(t.color(.hairline)),
        .border = color(t.color(.border)),
        .hover = color(t.color(.hover)),
        .selected = color(t.color(.selection_bg)),
        .selected_text = color(t.color(.selection_fg)),
        .stripe = color(t.color(.stripe)),
        .accent = color(t.color(.accent)),
        .accent_text = color(t.color(.accent_fg)),
        .danger = color(t.color(.danger)),
        .success = color(t.color(.success)),
        .cpu = if (colored_graphs) color(t.color(.blue)) else text,
        .memory = if (colored_graphs) color(t.color(.purple)) else text,
        .disk = if (colored_graphs) color(t.color(.orange)) else text,
        .network = if (colored_graphs) color(t.color(.cyan)) else text,
    };
}

/// nanoui's theme (what its buttons, dialogs, toasts and fields read), with
/// every field set from the active theme and the font set to Lexend.
pub fn uiTheme(k: Colors) ui.Theme {
    var t: ui.Theme = if (k.dark) .dark_theme else .light;
    t.dark = k.dark;
    t.background = k.page;
    t.surface = k.panel;
    t.surface_hover = k.hover;
    t.text = k.text;
    t.muted = k.secondary;
    t.border = k.separator;
    t.accent = k.accent;
    t.accent_hover = k.accent.mix(k.page, 0.15);
    t.accent_text = k.accent_text;
    t.track = k.border;
    t.knob = k.page;
    t.danger = k.danger;
    t.success = k.success;
    t.shadow = Color.black.alpha(if (k.dark) 0.45 else 0.14);
    t.font = fonts.family;
    t.mono_font = fonts.family;
    return t;
}

test "every theme gives readable nanoui colours and keeps Lexend" {
    var lib = core.themes.Library.init(std.testing.allocator);
    defer lib.deinit();
    core.themes.builtin.addAll(&lib);
    lib.resolveAll();
    for (lib.themes.items) |*t| {
        const k = colors(t, true);
        const u = uiTheme(k);
        try std.testing.expectEqualStrings(fonts.family, u.font.?);
        try std.testing.expectEqual(t.dark, u.dark);
        try std.testing.expectEqual(@as(f32, 1), k.page.a);
    }
}
