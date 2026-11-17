//! The toolbar Apps and Processes share: the page's title and count, the
//! search, Pause, Details and End task. Short of room (a wide details pane,
//! a narrow window), the count goes first, then the buttons keep only their
//! icons and the search narrows; each keeps its name for a screen reader
//! and as a tooltip. Not a page: the two list pages both draw it.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("../app/state.zig");
const theme = @import("../ui/theme.zig");
const table = @import("../ui/table.zig");
const controls = @import("../ui/controls.zig");

const State = app.State;

/// Below this width the buttons show only their icons.
const roomy = 720;

pub fn draw(c: *ui.Context, s: *State, k: theme.Colors, title: []const u8, count: []const u8) void {
    ui.key(c, "toolbar");
    const bar = ui.div(c).row().wFull().h(56).px(table.pad + 4).itemsCenter().gap(12);
    defer bar.end();
    const width = if (c.rects.get(c.interact(bar.index, .{}).id)) |r| r.w else 1000;
    const narrow = width < roomy;
    ui.text(c, title, .{ .size = 18, .weight = .bold, .color = k.text });
    {
        // The count gives way first when the toolbar is short of room.
        const box = ui.div(c).row().grow().w(0).clip();
        defer box.end();
        ui.text(c, count, .{ .size = 12.5, .color = k.secondary });
    }
    if (controls.searchSized(c, &s.search, if (narrow) 150 else 220)) s.rebuild();
    if (controls.button(c, k, if (s.paused) "Resume" else "Pause", .{ .icon = if (s.paused) "play.fill" else "pause.fill", .hint = "Ctrl+Shift+P", .compact = narrow })) s.togglePause();
    if (controls.button(c, k, "Details", .{ .icon = "info.circle", .hint = "Ctrl+I", .compact = narrow })) s.details_open = !s.details_open;
    if (controls.button(c, k, "End task", .{ .icon = if (narrow) "xmark.octagon" else "", .disabled = s.target() == null, .hint = "Delete", .compact = narrow })) s.askEndTask(false);
}
