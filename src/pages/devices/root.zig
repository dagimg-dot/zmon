//! A device's page: its history drawn large, with its figures below. The
//! sidebar's tiles open these pages.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app = @import("../../app/state.zig");
const theme = @import("../../ui/theme.zig");
const detail = @import("detail.zig");

const State = app.State;

pub fn page(c: *ui.Context, s: *State, k: theme.Colors) void {
    detail.view(c, s, k);
}
