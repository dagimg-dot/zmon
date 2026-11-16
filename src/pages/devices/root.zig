//! A device's page: its history drawn large, with its figures below. The
//! sidebar's tiles open these pages.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const fmt = core.fmt;
const system = @import("zmon-system");
const app = @import("../../app/state.zig");
const charts = @import("../../ui/charts.zig");
const theme = @import("../../ui/theme.zig");
const detail = @import("detail.zig");

const State = app.State;

pub fn page(c: *ui.Context, s: *State, k: theme.Colors) void {
    detail.view(c, s, k);
}
