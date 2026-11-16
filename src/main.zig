//! zmon: a system monitor, in Zig, drawn by nanoui.
const std = @import("std");
const nanoui = @import("nanoui");
const app_view = @import("app.zig");

pub const panic = nanoui.panic;
pub const std_options = nanoui.std_options;
pub const std_options_debug_threaded_io = nanoui.std_options_debug_threaded_io;

pub fn main(init: nanoui.Init) void {
    const app = nanoui.App.create(init, .{ .name = "zmon" }) catch return;
    defer app.destroy();
    var state: app_view.State = .init(init.gpa, init.io);
    defer state.deinit();
    _ = app.newWindow(.{
        .title = "zmon",
        .width = 1180,
        .height = 760,
        .content = .{ .view = .init(&state, app_view.State.view) },
    }) catch return;
    app.run() catch return;
}
