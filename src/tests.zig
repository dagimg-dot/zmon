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
    _ = @import("ui/icon.zig");
}

fn tester(t: *ui.Tester, state: *app_state.State) !void {
    try t.init(std.testing.allocator, .init(state, app_view.view), .{ .width = 1180, .height = 760 });
    t.settle(0.2);
}

test "Apps lists the apps that are open, and Processes every process" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try std.testing.expectEqual(app_state.Page.apps, state.page);
    for (state.app_rows) |row| switch (row) {
        .group => |g| try std.testing.expectEqual(.app, state.groups[g].kind),
        .proc => {},
    };
    try t.clickText("Processes");
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Page.processes, state.page);
    try std.testing.expect(t.hasText("PID"));
    try std.testing.expectEqual(state.sampler.procs.len, state.proc_rows.len); // the system's own tasks are shown by default
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
    try t.clickText("Apps");
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Page.apps, state.page);
}

test "clicking a column header sorts, and again reverses" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try t.clickText("Processes");
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Sort.cpu, state.proc_order.key);
    try t.clickText("Name"); // the sidebar also says Memory and CPU, so sort by the one header it doesn't
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Sort.name, state.proc_order.key);
    try std.testing.expect(state.proc_order.ascending);
    const procs = state.sampler.procs;
    for (state.proc_rows[1..], state.proc_rows[0 .. state.proc_rows.len - 1]) |b, a|
        try std.testing.expect(!std.ascii.lessThanIgnoreCase(procs[b].name, procs[a].name));
    try t.clickText("Name");
    t.settle(0.2);
    try std.testing.expect(!state.proc_order.ascending);
    try std.testing.expectEqual(app_state.Sort.cpu, state.app_order.key); // Apps keeps its own order
}

test "searching Processes keeps the processes whose name or pid matches" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try t.clickText("Processes");
    t.settle(0.2);
    const all = state.proc_rows.len;
    try t.clickText("Search by name or PID");
    t.typeText("1");
    t.settle(0.2);
    try std.testing.expectEqualStrings("1", state.search.text());
    try std.testing.expect(state.proc_rows.len > 0 and state.proc_rows.len < all);
    for (state.proc_rows) |i| {
        const p = state.sampler.procs[i];
        var b: [16]u8 = undefined;
        const pid = try std.fmt.bufPrint(&b, "{d}", .{p.pid});
        try std.testing.expect(std.mem.indexOf(u8, p.name, "1") != null or pid[0] == '1');
    }
    state.search.set("no process is called this");
    state.rebuild();
    t.settle(0.2);
    try std.testing.expect(t.containsText("No process matches"));
}

test "opening and closing an app shows its processes beneath it" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    const g = for (state.groups) |g| {
        if (g.kind == .app and g.members.len > 1) break g;
    } else return error.SkipZigTest; // no app with helpers is running
    const before = state.app_rows.len;
    state.toggle(g.root);
    try std.testing.expectEqual(before + g.members.len - 1, state.app_rows.len);
    t.settle(0.2);
    state.toggle(g.root);
    try std.testing.expectEqual(before, state.app_rows.len);
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

test "turning off the system's own tasks takes the kernel's threads out of Processes" {
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
    for (state.proc_rows) |i| try std.testing.expect(!state.sampler.procs[i].kthread);
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
