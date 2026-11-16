//! zmon's dialog: a panel over the window that keeps the keyboard while it is
//! open. Tab moves only between its own controls, Escape closes it, and the
//! focus goes to its main button. The view hides the page behind it from a
//! screen reader (app/view.zig) and takes the focus back when it closes.
//! nanoui's kit.dialog does none of this, and its buttons can't take the focus.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const theme = @import("theme.zig");
const controls = @import("controls.zig");

const motion = ui.motion;
const layer_backdrop = 10;
const layer_panel = 11;

pub const Options = struct {
    title: []const u8,
    description: []const u8 = "",
    width: f32 = 440,
    /// The buttons at the bottom ("" leaves one out). OK is the main one.
    ok: []const u8 = "",
    cancel: []const u8 = "",
    /// A second action between Cancel and OK ("" leaves it out).
    alt: []const u8 = "",
    /// The second action can't be undone.
    alt_danger: bool = false,
    /// OK does something that can't be undone.
    danger: bool = false,
};

/// What the dialog's buttons did this frame.
pub const Result = enum { none, ok, alt, cancel };

/// An open dialog: draw its content, then `end`.
pub const Dialog = struct {
    c: *ui.Context,
    k: theme.Colors,
    open: *bool,
    opts: Options,
    panel: ui.Div,
    body: ui.Div,
    /// Where its controls start among the frame's Tab stops.
    first: usize,

    /// Draws the buttons; says whether OK or Cancel was chosen (then it closes).
    pub fn end(d: Dialog) Result {
        const c = d.c;
        d.body.end();
        var result: Result = .none;
        var main: u64 = 0;
        if (d.opts.ok.len > 0 or d.opts.cancel.len > 0 or d.opts.alt.len > 0) {
            const f = ui.div(c).row().wFull().gap(8).justifyEnd().pt(4);
            defer f.end();
            if (d.opts.cancel.len > 0 and controls.button(c, d.k, d.opts.cancel, .{})) result = .cancel;
            if (d.opts.alt.len > 0 and controls.button(c, d.k, d.opts.alt, .{ .danger = d.opts.alt_danger })) result = .alt;
            if (d.opts.ok.len > 0) {
                if (controls.button(c, d.k, d.opts.ok, .{ .danger = d.opts.danger })) result = .ok;
                main = last(c);
            }
        }
        d.panel.end();
        if (result != .none) close(c, d.open);
        keepFocus(c, d.open.*, d.first, main);
        return result;
    }
};

/// A dialog keyed `id` while `open.*`; null once closed and gone.
pub fn begin(c: *ui.Context, k: theme.Colors, id: []const u8, open: *bool, opts: Options) ?Dialog {
    const t = kit.tokens(c);
    if (open.* and escape(c)) close(c, open);
    if (backdrop(c, t.overlay, c.print("{s}-backdrop", .{id}), open.*)) close(c, open);
    const f = motion.present(c, id, open.*, .{
        .initial = .{ .opacity = 0, .scale = 0.95, .y = 8 },
        .exit = .{ .opacity = 0, .scale = 0.97 },
        .transition = .{ .spring = motion.Spring.snappy },
    }) orelse return null;
    const first = c.focusable_ids.items.len;
    const panel_id = c.peekId(null);
    const h = if (c.rects.get(panel_id)) |r| r.h else 200;
    const w = @min(opts.width, c.size.w - 32);
    const panel = ui.div(c).fixed().offset((c.size.w - w) / 2, @max(16, (c.size.h - h) / 2 - c.size.h * 0.06)).w(w).layer(layer_panel).column().gap(14).p(22).rounded(14).bg(t.popover).border(k.border).shadow(.{ .color = t.shadow.alpha(1), .blur = 40, .y = 16 }).motion(f);
    _ = panel.interaction();
    {
        const head = ui.div(c).row().wFull().gap(8).itemsStart();
        defer head.end();
        const words = ui.div(c).column().grow().gap(5);
        ui.text(c, opts.title, .{ .size = 16, .weight = .semibold, .color = k.text });
        if (opts.description.len > 0) ui.text(c, opts.description, .{ .size = 13, .color = k.secondary, .wrap = true });
        words.end();
        if (closeButton(c, k)) close(c, open);
    }
    const body = ui.div(c).column().wFull().gap(10);
    return .{ .c = c, .k = k, .open = open, .opts = opts, .panel = panel, .body = body, .first = first };
}

/// Open, only the dialog's own controls are Tab stops, and the focus is
/// pulled in from the page behind it onto `main` (else the first control).
/// Leaving, it takes no focus while it fades.
fn keepFocus(c: *ui.Context, open: bool, first: usize, main: u64) void {
    const ids = &c.focusable_ids;
    if (!open) {
        ids.shrinkRetainingCapacity(first);
        return;
    }
    const own = ids.items[first..];
    std.mem.copyForwards(u64, ids.items[0..own.len], own);
    ids.shrinkRetainingCapacity(own.len);
    if (ids.items.len == 0 or std.mem.indexOfScalar(u64, ids.items, c.focus) != null) return;
    c.focus = if (main != 0) main else ids.items[0];
    c.changed = true;
    ui.access.screenChanged(c);
}

/// The id of the control drawn last.
fn last(c: *ui.Context) u64 {
    const ids = c.focusable_ids.items;
    return if (ids.len > 0) ids[ids.len - 1] else 0;
}

fn close(c: *ui.Context, open: *bool) void {
    open.* = false;
    c.changed = true;
}

/// Escape, as a shortcut or as a key (Linux sends it as either).
fn escape(c: *ui.Context) bool {
    if (c.shortcut(.{ .key = ui.Shortcut.escape })) return true;
    if (c.input.key != .escape or c.input.ctrl or c.input.alt or c.input.cmd) return false;
    c.input.key = null;
    return true;
}

/// The dimming behind the panel; true when it was clicked.
fn backdrop(c: *ui.Context, dim: ui.Color, key: []const u8, show: bool) bool {
    const f = motion.present(c, key, show, .{ .initial = .{ .opacity = 0 }, .exit = .{ .opacity = 0 }, .transition = .{ .tween = .{ .duration = 0.18 } } }) orelse return false;
    const d = ui.div(c).fixed().w(c.size.w).h(c.size.h).layer(layer_backdrop).bg(dim).motion(f);
    const it = d.interaction();
    d.end();
    return it.clicked and show;
}

fn closeButton(c: *ui.Context, k: theme.Colors) bool {
    ui.key(c, "close");
    const b = ui.div(c).row().size(28, 28).itemsCenter().justifyCenter().rounded(7).control().hover(k.hover);
    defer b.end();
    const pressed = controls.press(c, b, .{ .label = "Close" });
    ui.icon(c, "xmark", .{ .size = 11, .frame = 14, .color = k.secondary });
    return pressed;
}
