//! Tests: the data layer against fixtures and the live machine, and the
//! views rendered offscreen with ui.Tester (no window opens).
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app_view = @import("app.zig");

test {
    _ = @import("sampler.zig");
    _ = @import("charts.zig");
    _ = @import("theme.zig");
    _ = @import("fonts.zig");
}

fn tester(t: *ui.Tester, state: *app_view.State) !void {
    try t.init(std.testing.allocator, .init(state, app_view.State.view), .{ .width = 1180, .height = 760 });
    t.settle(0.2);
}

test "Processes lists the machine's apps and background processes" {
    var state: app_view.State = .init(std.testing.allocator, std.testing.io);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try std.testing.expect(t.hasText("Processes"));
    try std.testing.expect(t.hasText("Background processes"));
    try std.testing.expect(state.groups.len > 0);
    try std.testing.expect(state.rows.len > state.groups.len); // sections add rows
}

test "Performance page opens from the sidebar and shows the resources" {
    var state: app_view.State = .init(std.testing.allocator, std.testing.io);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try t.clickText("Performance");
    t.settle(0.2);
    try std.testing.expectEqual(app_view.Page.performance, state.page);
    try std.testing.expect(t.hasText("Memory"));
    try t.clickText("Memory");
    t.settle(0.2);
    try std.testing.expectEqual(app_view.Resource.memory, state.resource);
    try std.testing.expect(t.hasText("In use"));
}

test "clicking a column header sorts, and again reverses" {
    var state: app_view.State = .init(std.testing.allocator, std.testing.io);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try std.testing.expectEqual(app_view.Sort.cpu, state.sort);
    try t.clickText("Memory");
    t.settle(0.2);
    try std.testing.expectEqual(app_view.Sort.memory, state.sort);
    try std.testing.expect(!state.ascending);
    try t.clickText("Memory");
    t.settle(0.2);
    try std.testing.expect(state.ascending);
}
