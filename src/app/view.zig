//! The window's view: the sidebar beside the page it opens. The view is a
//! function of the state, drawn again on every input.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const state = @import("state.zig");
const theme = @import("../ui/theme.zig");
const apps_page = @import("../pages/apps/root.zig");
const processes = @import("../pages/processes/root.zig");
const confirm = @import("confirm.zig");
const devices = @import("../pages/devices/root.zig");
const sidebar = @import("sidebar.zig");
const settings_page = @import("../pages/settings/root.zig");

const State = state.State;

pub fn view(s: *State, c: *ui.Context) void {
    if (s.reload_themes) {
        s.reload_themes = false;
        s.reloadThemes();
    }
    const dark = s.isDark(nanoui.isDark());
    const k = theme.colors(s.theme(dark), s.settings.colored_graphs);
    // nanoui draws widgets from c.theme; the window's font comes from the
    // window's own theme (main.zig), and c.theme_chosen keeps them in step.
    const chosen = theme.uiTheme(k);
    c.theme = chosen;
    c.theme_chosen = chosen;
    c.frameIn(s.tick(c.time));

    const root = ui.div(c).row().sizeFull().bg(k.page);
    defer root.end();
    sidebar.draw(c, s, k);
    _ = c.leaf(.{ .width = .{ .px = 1 }, .height = .fill, .background = k.separator }, .none, null);
    {
        const main = ui.div(c).column().grow().w(0).hFull().clip();
        defer main.end();
        switch (s.page) {
            .apps => apps_page.page(c, s, k),
            .processes => processes.page(c, s, k),
            .cpu, .memory, .disk, .network => devices.page(c, s, k),
            .settings => settings_page.page(c, s, k),
        }
    }
    confirm.confirmDialog(c, s);
    s.toaster.view(c);
}
