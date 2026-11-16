//! zmon's own switch and segmented control. nanoui's take their colours from
//! fixed theme fields (a switch is "success" green when on); these follow the
//! active theme's accent, so every theme gets controls that belong to it.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const theme = @import("theme.zig");

/// A switch as drawn; the row that holds it takes the click, so the whole
/// row flips it.
pub fn switchLook(c: *ui.Context, k: theme.Colors, on: bool) void {
    const track = ui.div(c).row().size(40, 24).rounded(12).p(3).itemsCenter().bg(if (on) k.accent else k.border);
    defer track.end();
    if (on) _ = track.justifyEnd();
    const knob = ui.div(c).size(18, 18).roundedFull().bg(if (on) k.accent_text else k.page).shadowSm();
    knob.end();
}

/// A row of choices with the chosen one raised; true when the choice changed.
pub fn segmented(c: *ui.Context, k: theme.Colors, key: []const u8, options: []const []const u8, selected: *usize) bool {
    ui.key(c, key);
    const bar = ui.div(c).row().p(3).gap(2).rounded(9).bg(k.stripe).border(k.separator);
    defer bar.end();
    var changed = false;
    for (options, 0..) |label, i| {
        ui.key(c, label);
        const on = selected.* == i;
        const seg = ui.div(c).row().px(14).h(28).itemsCenter().justifyCenter().rounded(7).control();
        defer seg.end();
        if (on) _ = seg.bg(k.page).shadowSm() else _ = seg.hover(k.hover);
        if (seg.clicked() and !on) {
            selected.* = i;
            changed = true;
            c.changed = true;
        }
        ui.text(c, label, .{ .size = 12.5, .weight = if (on) .semibold else .regular, .color = if (on) k.text else k.secondary });
    }
    return changed;
}
