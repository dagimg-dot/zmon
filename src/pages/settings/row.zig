//! Settings laid out as libadwaita and vicinae do it: a small heading over a
//! card of rows, each row a label and a line of help on the left and its
//! control on the right.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const theme = @import("../../ui/theme.zig");
const controls = @import("../../ui/controls.zig");

pub fn heading(c: *ui.Context, k: theme.Colors, title: []const u8) void {
    ui.key(c, title);
    const r = ui.div(c).row().wFull().px(4).pt(18).pb(6);
    defer r.end();
    ui.text(c, title, .{ .size = 12.5, .weight = .semibold, .color = k.secondary });
}

/// A card that holds rows; end it after the last row.
pub fn group(c: *ui.Context, k: theme.Colors, key: []const u8) ui.Div {
    ui.key(c, key);
    return ui.div(c).column().wFull().rounded(12).bg(k.panel).border(k.separator).clip();
}

/// A row with a switch; a click anywhere on it flips `value`. True when it did.
pub fn switchRow(c: *ui.Context, k: theme.Colors, key: []const u8, label: []const u8, help: []const u8, first: bool, value: *bool) bool {
    const r = begin(c, k, key, label, help, first);
    defer r.end();
    _ = r.control().hover(k.hover);
    const flipped = controls.press(c, r, .{ .role = .switch_toggle, .label = label, .value = if (value.*) "On" else "Off", .selected = value.* });
    if (flipped) value.* = !value.*;
    controls.switchLook(c, k, value.*);
    return flipped;
}

/// A row: draw its control, then end it. Rows after the first get a hairline above.
pub fn begin(c: *ui.Context, k: theme.Colors, key: []const u8, label: []const u8, help: []const u8, first: bool) ui.Div {
    ui.key(c, key);
    if (!first) _ = c.leaf(.{ .width = .fill, .height = .{ .px = 1 }, .background = k.separator }, .none, null);
    const r = ui.div(c).row().wFull().px(16).py(12).itemsCenter().gap(16);
    {
        const words = ui.div(c).column().grow().gap(3);
        defer words.end();
        ui.text(c, label, .{ .size = 13.5, .weight = .medium, .color = k.text });
        if (help.len > 0) ui.text(c, help, .{ .size = 12, .color = k.secondary, .wrap = true });
    }
    return r;
}
