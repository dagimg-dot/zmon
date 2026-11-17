//! The keyboard: zmon's shortcuts, read at the start of each frame, before
//! any widget sees the keys. They follow GNOME's conventions where it has
//! one (Ctrl+F, Ctrl+Q, Ctrl+?, Ctrl+Page Up and Down), the editors' for
//! the sidebar (Ctrl+B), the browsers' for pages (Ctrl+1 to 6), and Task
//! Manager's for ending a task (Delete).
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("state.zig");
const focus = @import("focus.zig");

const State = app.State;
const Page = app.Page;
const S = ui.Shortcut;
/// nanoui's key enum, as the context's input holds it.
const Key = @typeInfo(@FieldType(@FieldType(ui.Context, "input"), "key")).optional.child;

/// The pages Ctrl+1 to Ctrl+6 open, in the sidebar's order.
const numbered = [_]Page{ .apps, .processes, .cpu, .memory, .disk, .network };
/// Rows Page Up and Page Down move: as many as the list shows, less one so
/// a row stays in view across the jump.
fn pageRows(c: *ui.Context, s: *const State) isize {
    const h = if (c.rects.get(s.list_id)) |r| r.h else 450;
    return @max(1, @as(isize, @intFromFloat(h / 30)) - 1);
}

pub fn handle(c: *ui.Context, s: *State) void {
    // Focus a click left behind (on the sidebar, say) isn't the keyboard's:
    // the list's keys still go to the list.
    const by_pointer = !s.keyboard and !c.input.pressed;
    // A click hides the focus ring again; a key shows it (focus-visible).
    if (c.input.pressed) {
        s.keyboard = false;
        focus.forget(s);
    }
    if (c.input.key != null or c.input.shortcut != null) s.keyboard = true;
    // Tab moves the focus before the view runs, so a move since the last
    // frame ended is the keyboard's.
    if (c.focus != s.last_focus and c.focus != 0) s.keyboard = true;
    // An open dialog owns the keyboard (its Escape closes it).
    if (s.confirm or s.shortcuts_open) return;

    if (ctrl(c, 'q') or ctrl(c, 'w')) c.close_request = true;
    if (ctrl(c, ',')) s.open(.settings);
    if (c.shortcut(.{ .key = 'p', .cmd = true, .shift = true })) s.togglePause();
    if (ctrl(c, 'b')) s.toggleSidebar();
    if (ctrl(c, 'i') and s.onList()) s.details_open = !s.details_open;
    if (c.shortcut(.{ .key = '?', .cmd = true, .shift = true }) or ctrl(c, '?') or c.shortcut(.{ .key = '/', .cmd = true, .shift = true }) or plain(c, .f1))
        s.shortcuts_open = true;
    for (numbered, 0..) |page, i| {
        if (ctrl(c, '1' + @as(u21, @intCast(i)))) s.open(page);
    }
    if (withCtrl(c, .page_down)) cycle(s, 1);
    if (withCtrl(c, .page_up)) cycle(s, -1);
    const in_search = c.focus != 0 and c.focus_is_text;
    if (ctrl(c, 'f') and !in_search) {
        focus.remember(c, s);
        if (!s.onList()) s.open(.processes);
        s.search.focus();
    }
    if (c.shortcut(.{ .key = S.escape }) or plain(c, .escape)) escape(c, s, in_search);
    if (s.onList()) list(c, s, by_pointer, in_search);
}

/// Escape goes back one step through the focus stack. Leaving the search
/// clears it, so no filter stays on unseen. With nothing to go back to, the
/// search falls back to its list and anything else to the page's sidebar entry.
fn escape(c: *ui.Context, s: *State, in_search: bool) void {
    if (in_search) {
        if (s.search.text().len > 0) {
            s.search.clear();
            s.rebuild();
        }
        return focus.back(c, s, s.list_id);
    }
    focus.back(c, s, s.nav_ids.get(s.page));
}

/// The list pages' keys: moving the selection, opening apps, ending a task,
/// and typing to search. They belong to the list when it has the focus, or
/// nothing has; when a button or the sidebar has it, Return presses that.
/// The arrows also work from the search field, so a search can be walked.
fn list(c: *ui.Context, s: *State, by_pointer: bool, in_search: bool) void {
    const owns = c.focus == 0 or c.focus == s.list_id or (by_pointer and !in_search);
    if (!owns and !in_search) return;
    var moved = false;
    if (arrow(c, S.down, .down)) {
        s.moveSelection(1);
        moved = true;
    }
    if (arrow(c, S.up, .up)) {
        s.moveSelection(-1);
        moved = true;
    }
    if (plain(c, .page_down)) {
        s.moveSelection(pageRows(c, s));
        moved = true;
    }
    if (plain(c, .page_up)) {
        s.moveSelection(-pageRows(c, s));
        moved = true;
    }
    if (moved) s.list_key_time = c.time;
    // Moving from nowhere, or from where a click left the focus, puts it on
    // the list, where the ring shows it.
    if (moved and !in_search) c.focus = s.list_id;
    // Inside the search field these keys edit the text.
    if (in_search) return;
    if (plain(c, .home)) s.selectEnd(false);
    if (plain(c, .end)) s.selectEnd(true);
    if (plain(c, .right)) s.openSelected(true);
    if (plain(c, .left)) s.openSelected(false);
    if (plain(c, .enter)) s.toggleSelected();
    if (plain(c, .delete)) s.askEndTask(false);
    if (withShift(c, .delete)) s.askEndTask(true);
    // Typing on the list starts a search with what was typed.
    const typed = c.input.chars;
    if (typed.len > 0 and !c.input.ctrl and !c.input.alt and !c.input.cmd and typed[0] > ' ' and typed[0] != 0x7f) {
        focus.remember(c, s);
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
    var at: i8 = @intCast(@backingInt(s.page));
    // Battery only where there is one.
    while (true) {
        at = @mod(at + by, n);
        if (pages[@intCast(at)] != .battery or s.sample.devices.battery.present) break;
    }
    s.open(pages[@intCast(at)]);
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

fn withShift(c: *ui.Context, k: Key) bool {
    if (c.input.key != k or !c.input.shift or c.input.ctrl or c.input.alt or c.input.cmd) return false;
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
