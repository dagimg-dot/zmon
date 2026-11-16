//! The confirmation before ending a task, as Activity Monitor asks it: End
//! task asks the process to quit, Force quit ends it at once. The focus starts
//! on End task, so Return finishes what Delete started; Escape cancels.
const app = @import("state.zig");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const theme = @import("../ui/theme.zig");
const dialog = @import("../ui/dialog.zig");

const State = app.State;

pub fn confirmDialog(c: *ui.Context, s: *State, k: theme.Colors) void {
    const t = s.target();
    const name = if (t) |x| x.name else "";
    const count = if (t) |x| x.count else 0;
    const dlg = dialog.begin(c, k, "end-task", &s.confirm, .{
        .title = c.print("End {s}?", .{name}),
        .description = if (count > 1)
            c.print("End task asks its {d} processes to quit, which lets them save. Force quit stops them at once, and unsaved work is lost.", .{count})
        else
            "End task asks it to quit, which lets it save. Force quit stops it at once, and unsaved work is lost.",
        .ok = "End task",
        .alt = "Force quit",
        .alt_danger = true,
        .cancel = "Cancel",
    }) orelse return;
    switch (dlg.end()) {
        .ok => s.endTask(false),
        .alt => s.endTask(true),
        .none, .cancel => {},
    }
}
