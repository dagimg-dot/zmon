//! zmon is monochrome: neutral surfaces, hairline separators, and ink that
//! flips with the system's light or dark setting. Emphasis comes from weight
//! and contrast, not from hue.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const Color = ui.Color;
const fonts = @import("fonts.zig");

pub const Colors = struct {
    page: Color,
    panel: Color,
    text: Color,
    secondary: Color,
    tertiary: Color,
    separator: Color,
    hover: Color,
    selected: Color,
    selected_text: Color,
    stripe: Color,
    danger: Color,
};

pub fn colors(dark: bool) Colors {
    return if (dark) .{
        .page = .hex(0x141414),
        .panel = .hex(0x1b1b1b),
        .text = .hex(0xf2f2f2),
        .secondary = .hex(0x9a9a9a),
        .tertiary = .hex(0x66666a),
        .separator = .hex(0x2a2a2a),
        .hover = .hex(0x232323),
        .selected = .hex(0xeeeeee),
        .selected_text = .hex(0x141414),
        .stripe = .hex(0x181818),
        .danger = .hex(0xff6b5e),
    } else .{
        .page = .hex(0xffffff),
        .panel = .hex(0xf6f6f6),
        .text = .hex(0x161616),
        .secondary = .hex(0x6b6b6b),
        .tertiary = .hex(0xa4a4a4),
        .separator = .hex(0xe6e6e6),
        .hover = .hex(0xf0f0f0),
        .selected = .hex(0x161616),
        .selected_text = .hex(0xffffff),
        .stripe = .hex(0xfafafa),
        .danger = .hex(0xd92d20),
    };
}

/// nanoui's theme (what its buttons, dialogs and toasts use), made monochrome.
pub fn theme(dark: bool) ui.Theme {
    const k = colors(dark);
    var t: ui.Theme = if (dark) .dark_theme else .light;
    t.background = k.page;
    t.surface = k.panel;
    t.surface_hover = k.hover;
    t.text = k.text;
    t.muted = k.secondary;
    t.border = k.separator;
    t.accent = k.selected;
    t.accent_hover = k.selected.alpha(0.85);
    t.accent_text = k.selected_text;
    t.danger = k.danger;
    t.font = fonts.family;
    t.mono_font = fonts.family;
    return t;
}
