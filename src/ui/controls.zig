//! zmon's own controls: a switch, a segmented control and a button. nanoui's
//! take their colours from fixed theme fields and its buttons can't take the
//! keyboard's focus; these follow the active theme's accent, Tab reaches each,
//! Space or Return presses it, and a screen reader is told what it is.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const theme = @import("theme.zig");

/// Makes `d` a control: Tab stops on it, Space or Return presses it, and a
/// screen reader reads it as `desc`. True when it was pressed this frame.
pub fn press(c: *ui.Context, d: ui.Div, desc: ui.access.Describe) bool {
    const it = c.interact(d.index, .{ .focusable = true });
    ui.access.describe(c, d.index, desc);
    if (it.clicked) c.changed = true;
    return it.clicked;
}

/// The search field Apps and Processes share; true when its text changed.
/// Placeholder and width are the same on both, so they read as one search.
pub fn search(c: *ui.Context, buf: *ui.TextBuffer) bool {
    ui.key(c, "search");
    return ui.textField(c, buf, .{ .placeholder = "Search", .width = .{ .px = 220 }, .size = 13 }).changed;
}

pub const ButtonOptions = struct {
    icon: []const u8 = "",
    disabled: bool = false,
    /// It does something that can't be undone (End task).
    danger: bool = false,
    /// What a screen reader adds after the label ("Asks first").
    hint: []const u8 = "",
};

/// An outlined button; true when it was pressed.
pub fn button(c: *ui.Context, k: theme.Colors, label: []const u8, opts: ButtonOptions) bool {
    ui.key(c, label);
    const b = ui.div(c).row().h(30).px(12).gap(6).itemsCenter().rounded(8).border(if (opts.danger and !opts.disabled) k.danger else k.border).control();
    defer b.end();
    const ink = if (opts.disabled) k.tertiary else if (opts.danger) k.danger else k.text;
    if (opts.disabled) {
        ui.access.describe(c, b.index, .{ .label = label, .enabled = false });
    } else {
        _ = b.hover(k.hover);
    }
    const pressed = !opts.disabled and press(c, b, .{ .label = label, .hint = opts.hint });
    if (opts.icon.len > 0) ui.icon(c, opts.icon, .{ .size = 12, .frame = 14, .color = ink });
    ui.text(c, label, .{ .size = 12.5, .weight = .medium, .color = ink });
    return pressed;
}

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
        if (press(c, seg, .{ .role = .radio_button, .label = label, .selected = on }) and !on) {
            selected.* = i;
            changed = true;
            c.changed = true;
        }
        ui.text(c, label, .{ .size = 12.5, .weight = if (on) .semibold else .regular, .color = if (on) k.text else k.secondary });
    }
    return changed;
}
