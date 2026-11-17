//! What Apps and Processes show before they have rows to show: the live Ring
//! while the processes are read, or why they aren't. Not a page: the two
//! list pages both draw it.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("../app/state.zig");
const theme = @import("../ui/theme.zig");
const table = @import("../ui/table.zig");

/// Draws the wait, if the list is waiting; false once the processes are read.
pub fn draw(c: *ui.Context, s: *const app.State, k: theme.Colors) bool {
    switch (s.waiting()) {
        .no => return false,
        .reading => table.loading(c, k, "Reading the processes…"),
        .paused => table.empty(c, k, "Updates are paused. Resume them to see the processes."),
    }
    return true;
}
