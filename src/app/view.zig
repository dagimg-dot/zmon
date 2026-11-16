//! The window's view: the sidebar beside the page it opens. The view is a
//! function of the state, drawn again on every input.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const state = @import("state.zig");
const theme = @import("../ui/theme.zig");
const processes = @import("../pages/processes/root.zig");
const devices = @import("../pages/devices/root.zig");
const sidebar = @import("sidebar.zig");

const State = state.State;

pub fn view(s: *State, c: *ui.Context) void {
    const dark = s.dark orelse nanoui.isDark();
    // The window takes its font from the theme the view *chose*, not from `c.theme`.
    const chosen = theme.theme(dark);
    c.theme = chosen;
    c.theme_chosen = chosen;
    const k = theme.colors(dark);
    c.frameIn(s.tick(c.time));

    const root = ui.div(c).row().sizeFull().bg(k.page);
    defer root.end();
    sidebar.draw(c, s, k);
    _ = c.leaf(.{ .width = .{ .px = 1 }, .height = .fill, .background = k.separator }, .none, null);
    {
        const main = ui.div(c).column().grow().w(0).hFull().clip();
        defer main.end();
        switch (s.page) {
            .processes => processes.page(c, s, k),
            .cpu, .memory, .disk, .network => devices.page(c, s, k),
        }
    }
    processes.confirmDialog(c, s);
    s.toaster.view(c);
}
