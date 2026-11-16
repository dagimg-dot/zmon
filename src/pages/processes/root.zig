//! The Processes page: apps first, then background processes and the kernel's
//! threads. A group shows its totals; open it to see what it started. Columns
//! sort when their header is clicked.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const app = @import("../../app/state.zig");
const theme = @import("../../ui/theme.zig");
const table = @import("table.zig");
const confirm = @import("confirm.zig");

const State = app.State;
const pad = 14;

pub const confirmDialog = confirm.confirmDialog;

pub fn page(c: *ui.Context, s: *State, k: theme.Colors) void {
    toolbar(c, s, k);
    table.view(c, s, k);
}

fn toolbar(c: *ui.Context, s: *State, k: theme.Colors) void {
    const bar = ui.div(c).row().wFull().h(56).px(pad + 4).itemsCenter().gap(12);
    defer bar.end();
    ui.text(c, "Processes", .{ .size = 18, .weight = .bold, .color = k.text });
    ui.text(c, c.print("{d} running, {d} threads", .{ s.sampler.procs.len, s.sampler.threads }), .{ .size = 12.5, .color = k.secondary });
    ui.spacer(c);
    const t = s.target();
    if (kit.button(c, "End task", .{ .variant = .outline, .size = .sm, .disabled = t == null }).clicked) {
        if (s.settings.confirm_end_task) s.confirm = true else s.endTask(false);
    }
}
