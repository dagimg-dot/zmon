//! The confirmation before ending a task. The focus starts on End task, so
//! Return finishes what Delete started; Tab reaches Cancel, Escape cancels.
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
            c.print("This asks {d} processes to quit. Unsaved work in them may be lost.", .{count})
        else
            "This asks the process to quit. Unsaved work in it may be lost.",
        .ok = "End task",
        .danger = true,
        .cancel = "Cancel",
    }) orelse return;
    if (dlg.end() == .ok) s.endTask(false);
}
