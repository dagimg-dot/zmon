//! zmon: a system monitor, in Zig, drawn by nanoui.
const std = @import("std");
const nanoui = @import("nanoui");
const app_state = @import("app/state.zig");
const app_view = @import("app/view.zig");
const fonts = @import("ui/fonts.zig");
const icon = @import("ui/icon.zig");
const theme = @import("ui/theme.zig");

pub const panic = nanoui.panic;
/// See `main`; `app/root_lookup.zig` runs it.
pub const port_holders_flag = "--port-holders";
pub const std_options = nanoui.std_options;
pub const std_options_debug_threaded_io = nanoui.std_options_debug_threaded_io;

pub fn main(init: nanoui.Init) !void {
    // `zmon --port-holders PORT`: run by zmon itself through pkexec when you
    // ask to see which of another user's processes holds a port. It prints
    // their pids, one a line, and exits; no window, nothing else.
    var args = init.minimal.args.iterate();
    _ = args.next();
    if (args.next()) |flag| if (std.mem.eql(u8, flag, port_holders_flag)) {
        const port = std.fmt.parseInt(u16, args.next() orelse "", 10) catch 0;
        if (port == 0) {
            std.debug.print("usage: zmon {s} PORT (a number from 1 to 65535)\n", .{port_holders_flag});
            std.process.exit(2);
        }
        const h = @import("zmon-system").sampler.portHoldersAll(init.io, port);
        var buf: [512]u8 = undefined;
        var w = std.Io.File.stdout().writer(init.io, &buf);
        for (h.pids[0..h.count]) |pid| try w.interface.print("{d}\n", .{pid});
        try w.interface.flush();
        return;
    };
    if (!fonts.register()) std.log.warn("couldn't load the bundled Lexend font; using the system's", .{});
    const system = @import("zmon-system");
    _ = system.desktop.setName("zmon");
    const app = try nanoui.App.create(init, .{ .name = "zmon" });
    defer app.destroy();
    var arena: std.heap.ArenaAllocator = .init(init.gpa);
    defer arena.deinit();
    var state: app_state.State = .init(init.gpa, init.io, system.config.location(arena.allocator()));
    defer state.deinit();
    state.threaded = true;
    _ = try app.newWindow(.{
        .title = "zmon",
        .icon = icon.png,
        .width = 1180,
        .height = 760,
        // Below this the lists' fixed columns leave the names no room.
        .min_width = 860,
        .min_height = 520,
        .theme = theme.uiTheme(theme.colors(state.theme(state.isDark(nanoui.isDark())), .{})),
        .content = .{ .view = .init(&state, app_view.view) },
    });
    try app.run();
}
