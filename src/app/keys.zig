//! The keyboard: zmon's shortcuts, read at the start of each frame, before
//! any widget sees the keys. They follow GNOME's conventions where it has
//! one (Ctrl+F, Ctrl+Q, Ctrl+?, Ctrl+Page Up and Down), the browsers' for
//! pages (Ctrl+1 to 6), and Task Manager's for ending a task (Delete).
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("state.zig");

const State = app.State;
const Page = app.Page;
const S = ui.Shortcut;
/// nanoui's key enum, as the context's input holds it.
const Key = @typeInfo(@FieldType(@FieldType(ui.Context, "input"), "key")).optional.child;

/// The pages Ctrl+1 to Ctrl+6 open, in the sidebar's order.
const numbered = [_]Page{ .apps, .processes, .cpu, .memory, .disk, .network };
/// Rows Page Up and Page Down move.
const page_rows = 15;

pub fn handle(c: *ui.Context, s: *State) void {
    // A click hides the focus ring again; a key shows it (focus-visible).
    if (c.input.pressed) s.keyboard = false;
    if (c.input.key != null or c.input.shortcut != null) s.keyboard = true;
    // Tab moves the focus before the view runs, so a move since the last
    // frame ended is the keyboard's.
    if (c.focus != s.last_focus and c.focus != 0) s.keyboard = true;
    // An open dialog owns the keyboard (its Escape closes it).
    if (s.confirm or s.shortcuts_open) return;

    if (ctrl(c, 'q') or ctrl(c, 'w')) c.close_request = true;
    if (ctrl(c, ',')) s.open(.settings);
    if (c.shortcut(.{ .key = '?', .cmd = true, .shift = true }) or ctrl(c, '?') or c.shortcut(.{ .key = '/', .cmd = true, .shift = true }) or plain(c, .f1))
        s.shortcuts_open = true;
    for (numbered, 0..) |page, i| {
        if (ctrl(c, '1' + @as(u21, @intCast(i)))) s.open(page);
    }
    if (withCtrl(c, .page_down)) cycle(s, 1);
    if (withCtrl(c, .page_up)) cycle(s, -1);
    if (ctrl(c, 'f')) {
        if (!s.onList()) s.open(.processes);
        s.search.focus();
    }
    if (s.onList()) list(c, s);
}

/// The list pages' keys: moving the selection, opening apps, ending a task,
/// and typing to search.
fn list(c: *ui.Context, s: *State) void {
    const in_search = c.focus != 0 and c.focus_is_text;
    if (arrow(c, S.down, .down)) s.moveSelection(1);
    if (arrow(c, S.up, .up)) s.moveSelection(-1);
    if (plain(c, .page_down)) s.moveSelection(page_rows);
    if (plain(c, .page_up)) s.moveSelection(-page_rows);
    if (c.shortcut(.{ .key = S.escape }) or plain(c, .escape)) {
        if (s.search.text().len > 0) {
            s.search.clear();
            s.rebuild();
        } else if (in_search) {
            c.focus = 0;
        } else s.clearSelection();
    }
    // Inside the search field these keys edit the text.
    if (in_search) return;
    if (plain(c, .home)) s.selectEnd(false);
    if (plain(c, .end)) s.selectEnd(true);
    if (plain(c, .right)) s.openSelected(true);
    if (plain(c, .left)) s.openSelected(false);
    if (plain(c, .enter)) s.toggleSelected();
    if (plain(c, .delete)) s.askEndTask();
    // Typing on the list starts a search with what was typed.
    const typed = c.input.chars;
    if (typed.len > 0 and !c.input.ctrl and !c.input.alt and !c.input.cmd and typed[0] > ' ' and typed[0] != 0x7f) {
        s.search.focus();
        const end = s.search.text().len;
        _ = s.search.insert(end, typed);
        s.search.want_caret = end + typed.len;
        c.input.chars = "";
        c.changed = true;
        s.rebuild();
    }
}

fn cycle(s: *State, by: i8) void {
    const pages = std.enums.values(Page);
    const n: i8 = @intCast(pages.len);
    const at: i8 = @intCast(@backingInt(s.page));
    s.open(pages[@intCast(@mod(at + by, n))]);
}

/// Ctrl and a character (Command on the Mac).
fn ctrl(c: *ui.Context, key: u21) bool {
    return c.shortcut(.{ .key = key, .cmd = true });
}

/// A key with no modifier, as plain key input (how Linux sends Home, Enter, Delete).
fn plain(c: *ui.Context, k: Key) bool {
    if (c.input.key != k or c.input.ctrl or c.input.alt or c.input.cmd) return false;
    c.input.key = null;
    c.changed = true;
    return true;
}

fn withCtrl(c: *ui.Context, k: Key) bool {
    if (c.input.key != k or !c.input.ctrl) return false;
    c.input.key = null;
    c.changed = true;
    return true;
}

/// An arrow, offered as a shortcut first and as a key if no one took it.
fn arrow(c: *ui.Context, code: u21, k: Key) bool {
    return c.shortcut(.{ .key = code }) or plain(c, k);
}
