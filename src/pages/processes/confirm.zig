//! The confirmation before ending a task.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const app = @import("../../app/state.zig");

const State = app.State;

pub fn confirmDialog(c: *ui.Context, s: *State) void {
    const t = s.target();
    const name = if (t) |x| x.name else "";
    const count = if (t) |x| x.count else 0;
    const dlg = kit.dialog(c, "end-task", &s.confirm, .{
        .title = c.print("End {s}?", .{name}),
        .description = if (count > 1)
            c.print("This asks {d} processes to quit. Unsaved work in them may be lost.", .{count})
        else
            "This asks the process to quit. Unsaved work in it may be lost.",
        .ok = "End task",
        .ok_variant = .danger,
        .cancel = "Cancel",
    }) orelse return;
    if (dlg.end() == .ok) s.endTask(false);
}
