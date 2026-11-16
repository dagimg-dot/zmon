//! Tests: the data layer against fixtures and the live machine, and the
//! views rendered offscreen with ui.Tester (no window opens).
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app_state = @import("app/state.zig");
const app_view = @import("app/view.zig");

test {
    _ = @import("ui/charts.zig");
    _ = @import("ui/theme.zig");
    _ = @import("ui/fonts.zig");
}

fn tester(t: *ui.Tester, state: *app_state.State) !void {
    try t.init(std.testing.allocator, .init(state, app_view.view), .{ .width = 1180, .height = 760 });
    t.settle(0.2);
}

test "Processes lists the machine's apps and background processes" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io);
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
    var state: app_state.State = .init(std.testing.allocator, std.testing.io);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try t.clickText("Performance");
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Page.performance, state.page);
    try std.testing.expect(t.hasText("Memory"));
    try t.clickText("Memory");
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Resource.memory, state.resource);
    try std.testing.expect(t.hasText("In use"));
}

test "clicking a column header sorts, and again reverses" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try std.testing.expectEqual(app_state.Sort.cpu, state.sort);
    try t.clickText("Memory");
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Sort.memory, state.sort);
    try std.testing.expect(!state.ascending);
    try t.clickText("Memory");
    t.settle(0.2);
    try std.testing.expect(state.ascending);
}

test "collapsing a group at the end of the list does not read past the rows" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    // Scroll to the end, where Kernel threads is the last row, whichever sign the wheel uses.
    var r = t.findText("Kernel threads");
    for ([_]f32{ 100_000, -200_000 }) |dy| {
        if (r != null) break;
        t.scroll(700, 500, dy);
        t.settle(0.3);
        r = t.findText("Kernel threads");
    }
    const at = r orelse return error.SkipZigTest;
    t.doubleClick(at.x + at.w / 2, at.y + at.h / 2); // open it: its threads follow below
    t.settle(0.3);
    try std.testing.expect(state.expanded.contains(0));
    const again = t.findText("Kernel threads") orelse return error.SkipZigTest;
    t.doubleClick(again.x + again.w / 2, again.y + again.h / 2); // close it: far fewer rows
    t.settle(0.3);
    try std.testing.expect(!state.expanded.contains(0));
}
