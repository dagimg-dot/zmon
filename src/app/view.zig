//! The window's view: the sidebar beside the page it opens. The view is a
//! function of the state, drawn again on every input.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const state = @import("state.zig");
const theme = @import("../ui/theme.zig");
const apps_page = @import("../pages/apps/root.zig");
const processes = @import("../pages/processes/root.zig");
const confirm = @import("confirm.zig");
const keys = @import("keys.zig");
const details = @import("details.zig");
const focus = @import("focus.zig");
const shortcuts = @import("shortcuts.zig");
const devices = @import("../pages/devices/root.zig");
const sidebar = @import("sidebar.zig");
const motion = @import("../ui/motion.zig");
const app_icon = @import("../ui/app_icon.zig");
const settings_page = @import("../pages/settings/root.zig");

const State = state.State;
const system = @import("zmon-system");

pub fn view(s: *State, c: *ui.Context) void {
    if (s.reload_themes) {
        s.reload_themes = false;
        s.reloadThemes();
    }
    const dark = s.isDark(nanoui.isDark());
    const k = theme.colors(s.theme(dark), .{ .colored_graphs = s.settings.colored_graphs, .more_contrast = s.settings.more_contrast });
    // nanoui draws widgets from c.theme; the window's font comes from the
    // window's own theme (main.zig), and c.theme_chosen keeps them in step.
    const chosen = theme.uiTheme(k);
    c.theme = chosen;
    c.theme_chosen = chosen;
    app_icon.startSmall(c);
    if (s.threaded and !s.worker.running()) {
        // The worker asks for a frame through the window when a sample is ready.
        const w: ?system.sampler.Waker = if (c.waker) |wk| .{ .ctx = wk.ctx, .wake = wk.wake } else null;
        s.startSampling(w);
    }
    c.frameIn(s.tick(c.time));
    c.setZoom(s.settings.text_size.scale());
    reduceMotion(c, s);
    keys.handle(c, s);
    // Focus is drawn only after a key, as browsers' :focus-visible.
    c.focus_ring = if (s.keyboard) .{ .color = k.accent, .width = 2 } else null;

    const root = ui.div(c).row().sizeFull().bg(k.page);
    {
        defer root.end();
        sidebar.draw(c, s, k);
        const sidebar_stops = c.focusable_ids.items.len;
        _ = c.leaf(.{ .width = .{ .px = 1 }, .height = .fill, .background = k.separator }, .none, null);
        {
            const main = ui.div(c).column().grow().w(0).hFull().clip();
            defer main.end();
            switch (s.page) {
                .apps => apps_page.page(c, s, k),
                .processes => processes.page(c, s, k),
                .cpu, .memory, .disk, .network, .battery => devices.page(c, s, k),
                .settings => settings_page.page(c, s, k),
            }
        }
        // The pane slides in and out; a page without one hides it at once.
        if (s.onList()) {
            if (motion.reveal(c, "details", s.details_open)) |open| {
                details.edge(c, s, k, sidebar.width(c, s));
                details.pane(c, s, k, open);
            }
        } else motion.jump(c, "details", if (s.details_open) 1 else 0);
        if (s.focus_content) {
            s.focus_content = false;
            focusContent(c, s, sidebar_stops);
        }
        s.toaster.view(c);
    }
    dialogs(c, s, k, root);
    s.last_focus = c.focus;
}

/// The dialogs, over the page. One opening remembers where the focus was, so
/// closing it goes back there; while one is open, a screen reader is kept
/// to it, as Tab is (ui/dialog.zig).
fn dialogs(c: *ui.Context, s: *State, k: theme.Colors, behind: ui.Div) void {
    if (s.dialogOpen() and !s.dialog_was_open) focus.remember(c, s);
    if (s.dialogOpen()) ui.access.hide(c, behind.index);
    confirm.confirmDialog(c, s, k);
    shortcuts.overlay(c, s, k);
    if (s.dialog_was_open and !s.dialogOpen()) focus.leaveDialog(c, s, if (s.onList()) s.list_id else s.nav_ids.get(s.page));
    s.dialog_was_open = s.dialogOpen();
}

/// Moves the focus into the page just opened: a list page's list, else the
/// page's first control. A device page has none, so its tile keeps it.
fn focusContent(c: *ui.Context, s: *State, sidebar_stops: usize) void {
    const target = if (s.onList()) s.list_id else if (c.focusable_ids.items.len > sidebar_stops) c.focusable_ids.items[sidebar_stops] else 0;
    if (target == 0) return;
    c.focus = target;
    c.changed = true;
}

/// Settings' Reduce motion, on top of the system's: turning it off gives the
/// system's own choice back.
fn reduceMotion(c: *ui.Context, s: *State) void {
    if (s.settings.reduce_motion) {
        c.reduced_motion = true;
        c.reduce_motion = true;
        s.motion_forced = true;
    } else if (s.motion_forced) {
        c.reduced_motion = false;
        c.reduce_motion = false;
        s.motion_forced = false;
    }
}
