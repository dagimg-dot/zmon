//! Moving the keyboard's focus in and back out, through the focus stack
//! (core/focus.zig). Every step into something goes through `stepIn` or
//! `remember`, and every Escape through `back`, so going back always
//! retraces the way in.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("state.zig");

const State = app.State;

/// Moves the focus to `to`, remembering where it was.
pub fn stepIn(c: *ui.Context, s: *State, to: u64) void {
    if (to == 0 or to == c.focus) return;
    s.focus_stack.push(c.focus);
    c.focus = to;
    c.changed = true;
}

/// Remembers where the focus is, for a step whose target takes the focus
/// itself once drawn (the search field, a page not drawn yet).
pub fn remember(c: *ui.Context, s: *State) void {
    s.focus_stack.push(c.focus);
}

/// Escape: back one step, to the last control remembered that is still
/// drawn, or to `fallback` when there is none.
pub fn back(c: *ui.Context, s: *State, fallback: u64) void {
    // The controls drawn in the last frame: a step whose page has gone is skipped.
    backAmong(c, s, c.last_focusable_ids.items, fallback);
}

/// A dialog just closed: back to where the focus was when it opened. The
/// last frame's controls were only the dialog's, so this frame's are asked.
pub fn leaveDialog(c: *ui.Context, s: *State, fallback: u64) void {
    backAmong(c, s, c.focusable_ids.items, fallback);
}

fn backAmong(c: *ui.Context, s: *State, alive: []const u64, fallback: u64) void {
    const to = s.focus_stack.pop(alive, c.focus) orelse fallback;
    if (to == 0 or to == c.focus) return;
    c.focus = to;
    c.changed = true;
}

/// A click breaks the way back: what was remembered no longer leads anywhere.
pub fn forget(s: *State) void {
    s.focus_stack.clear();
}
