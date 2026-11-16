//! zmon: a system monitor, in Zig, drawn by nanoui.
const std = @import("std");
const nanoui = @import("nanoui");
const app_state = @import("app/state.zig");
const app_view = @import("app/view.zig");
const fonts = @import("ui/fonts.zig");
const icon = @import("ui/icon.zig");
const theme = @import("ui/theme.zig");

pub const panic = nanoui.panic;
pub const std_options = nanoui.std_options;
pub const std_options_debug_threaded_io = nanoui.std_options_debug_threaded_io;

pub fn main(init: nanoui.Init) !void {
    if (!fonts.register()) std.log.warn("couldn't load the bundled Lexend font; using the system's", .{});
    const system = @import("zmon-system");
    _ = system.desktop.setName("zmon");
    const app = try nanoui.App.create(init, .{ .name = "zmon" });
    defer app.destroy();
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    var state: app_state.State = .init(init.gpa, init.io, system.config.location(arena.allocator()));
    defer state.deinit();
    _ = try app.newWindow(.{
        .title = "zmon",
        .icon = icon.png,
        .width = 1180,
        .height = 760,
        .theme = theme.uiTheme(theme.colors(state.theme(state.isDark(nanoui.isDark())), true)),
        .content = .{ .view = .init(&state, app_view.view) },
    });
    try app.run();
}
