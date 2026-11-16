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
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
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

test "a device tile in the sidebar opens that device's page" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try std.testing.expect(t.hasText("Devices"));
    try t.clickText("Memory"); // the sidebar is drawn first, so its tile is the first "Memory"
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Page.memory, state.page);
    try std.testing.expect(t.hasText("In use"));
    try t.clickText("Processes");
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Page.processes, state.page);
}

test "clicking a column header sorts, and again reverses" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try std.testing.expectEqual(app_state.Sort.cpu, state.sort);
    try t.clickText("Name"); // the sidebar also says Memory and CPU, so sort by the one header it doesn't
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Sort.name, state.sort);
    try std.testing.expect(state.ascending);
    try t.clickText("Name");
    t.settle(0.2);
    try std.testing.expect(!state.ascending);
}

test "collapsing a group at the end of the list does not read past the rows" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
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

/// Scrolls the page until the text `s` is inside the window, whichever sign the wheel uses.
fn reveal(t: *ui.Tester, s: []const u8) !void {
    var dy: f32 = -200;
    var last: f32 = std.math.inf(f32);
    for (0..40) |_| {
        const r = t.findText(s) orelse return error.TextNotFound;
        if (r.y >= 0 and r.y + r.h <= 740) return;
        if (r.y >= last) dy = -dy; // it didn't come closer: the wheel goes the other way
        last = r.y;
        t.scroll(700, 400, dy);
        t.settle(0.3);
    }
    return error.TextNotFound;
}

fn openSettings(t: *ui.Tester, state: *app_state.State) !void {
    try t.clickText("Settings"); // the sidebar's row comes before the page's title
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Page.settings, state.page);
}

test "Settings opens from the sidebar, and a theme card becomes the light theme" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try openSettings(&t, &state);
    try std.testing.expect(t.hasText("Appearance"));
    try std.testing.expectEqualStrings("graphite-light", state.theme(false).id);
    try t.clickText("Catppuccin Latte");
    t.settle(0.2);
    try std.testing.expectEqualStrings("catppuccin-latte", state.settings.light_theme.slice());
    try std.testing.expectEqualStrings("catppuccin-latte", state.theme(false).id);
    try std.testing.expectEqualStrings("graphite-dark", state.settings.dark_theme.slice());
}

test "choosing Dark shows the dark themes and uses the dark one" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try openSettings(&t, &state);
    try t.clickText("Dark");
    t.settle(0.2);
    try std.testing.expectEqual(.dark, state.settings.appearance);
    try std.testing.expect(state.isDark(false));
    try std.testing.expect(t.hasText("Dark theme"));
    try std.testing.expect(t.hasText("Graphite Dark"));
    try std.testing.expect(!t.hasText("Graphite Light"));
}

test "under Match system the gallery switches between dark and light themes" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try openSettings(&t, &state);
    try std.testing.expect(t.hasText("Light theme"));
    try t.clickText("When it's dark");
    t.settle(0.2);
    try std.testing.expect(t.hasText("Dark theme"));
    try t.clickText("Nord");
    t.settle(0.2);
    try std.testing.expectEqualStrings("nord", state.settings.dark_theme.slice());
    try std.testing.expectEqualStrings("graphite-light", state.theme(false).id);
}

test "turning off the system's own tasks takes Kernel threads off the list" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try openSettings(&t, &state);
    try reveal(&t, "Show the system's own tasks");
    try t.clickText("Show the system's own tasks");
    t.settle(0.2);
    try std.testing.expect(!state.settings.show_kernel_threads);
    for (state.rows) |row| switch (row) {
        .group => |gi| try std.testing.expect(state.groups[gi].kind != .kernel),
        else => {},
    };
}

test "Reset to defaults brings back Graphite and the default switches" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    state.chooseTheme(false, "nord-light");
    state.settings.colored_graphs = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try openSettings(&t, &state);
    try reveal(&t, "Reset to defaults");
    try t.clickText("Reset to defaults");
    t.settle(0.2);
    try std.testing.expectEqualStrings("graphite-light", state.theme(false).id);
    try std.testing.expect(state.settings.colored_graphs);
}
