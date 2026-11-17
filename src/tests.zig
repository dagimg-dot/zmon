//! Tests: the data layer against fixtures and the live machine, and the
//! views rendered offscreen with ui.Tester (no window opens).
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const app_state = @import("app/state.zig");
const app_view = @import("app/view.zig");
const core = @import("zmon-core");

test {
    _ = @import("ui/charts.zig");
    _ = @import("ui/theme.zig");
    _ = @import("ui/fonts.zig");
    _ = @import("app/details.zig");
    _ = @import("app/root_lookup.zig");
    _ = @import("ui/table.zig");
    _ = @import("ui/shortcut.zig");
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
    for (state.app_rows) |row| switch (row) { // Background is closed: apps only above it
        .group => |g| try std.testing.expectEqual(.app, state.groups[g].kind),
        .proc, .background => {},
    };
    try t.clickText("Processes");
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Page.processes, state.page);
    try std.testing.expect(t.hasText("PID"));
    for (state.proc_rows) |i| try std.testing.expect(!state.sample.procs[i].kthread); // kernel threads are hidden by default
    try std.testing.expect(state.proc_rows.len > 0);
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
    const procs = state.sample.procs;
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
    try t.clickText("Search");
    t.typeText("1");
    t.settle(0.2);
    try std.testing.expectEqualStrings("1", state.search.text());
    try std.testing.expect(state.proc_rows.len > 0 and state.proc_rows.len < all);
    for (state.proc_rows) |i| {
        const p = state.sample.procs[i];
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
    try reveal(&t, "Catppuccin Latte");
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
    try std.testing.expect(t.hasText("Theme")); // one kind of theme, so no dark or light in the heading
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
    try reveal(&t, "When it's dark");
    try t.clickText("When it's dark");
    t.settle(0.2);
    try std.testing.expect(t.hasText("Dark theme"));
    try reveal(&t, "Nord");
    try t.clickText("Nord");
    t.settle(0.2);
    try std.testing.expectEqualStrings("nord", state.settings.dark_theme.slice());
    try std.testing.expectEqualStrings("graphite-light", state.theme(false).id);
}

test "showing kernel threads puts them in Processes, and hiding them takes them out" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    const f = try Fixture.init(&state);
    defer f.deinit();
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try openSettings(&t, &state);
    try reveal(&t, "Show kernel threads");
    try t.clickText("Show kernel threads");
    t.settle(0.2);
    try std.testing.expect(state.settings.show_kernel_threads);
    var kernel: usize = 0;
    for (state.proc_rows) |i| kernel += @intFromBool(state.sample.procs[i].kthread);
    try std.testing.expectEqual(@as(usize, 2), kernel);
    try t.clickText("Show kernel threads");
    t.settle(0.2);
    for (state.proc_rows) |i| try std.testing.expect(!state.sample.procs[i].kthread);
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

/// A made-up machine, so what a test checks doesn't move between key
/// presses: an app with two helpers, an editor, a service under another
/// user, init, two kernel threads, and this test itself.
const Fixture = struct {
    snap: @import("zmon-system").sampler.Snapshot,

    fn init(state: *app_state.State) !*Fixture {
        const f = try std.testing.allocator.create(Fixture);
        f.* = .{ .snap = .init(std.testing.allocator) };
        const a = f.snap.arena.allocator();
        const me = std.os.linux.getuid();
        const self = std.os.linux.getpid();
        const P = core.Proc;
        const procs = try a.dupe(P, &[_]P{
            .{ .pid = 1, .ppid = 0, .name = "systemd", .comm = "systemd", .uid = 0, .start = 1 },
            .{ .pid = 2, .ppid = 0, .name = "kthreadd", .comm = "kthreadd", .kthread = true, .start = 1 },
            .{ .pid = 3, .ppid = 2, .name = "kworker/0:1", .comm = "kworker/0:1", .kthread = true, .start = 2 },
            .{ .pid = 100, .ppid = 1, .name = "browser", .comm = "browser", .exe = "/usr/bin/browser", .program = "browser", .uid = me, .start = 10, .cpu = 30, .memory = 300 << 20, .unit = "app-test.Browser-100.scope" },
            .{ .pid = 101, .ppid = 100, .name = "browser", .comm = "browser", .exe = "/usr/bin/browser", .program = "browser", .uid = me, .start = 11, .cpu = 20, .memory = 200 << 20, .unit = "app-test.Browser-100.scope" },
            .{ .pid = 102, .ppid = 100, .name = "browser", .comm = "browser", .exe = "/usr/bin/browser", .program = "browser", .uid = me, .start = 12, .cpu = 1, .memory = 50 << 20, .unit = "app-test.Browser-100.scope" },
            .{ .pid = 200, .ppid = 1, .name = "editor", .comm = "editor", .exe = "/usr/bin/editor", .program = "editor", .uid = me, .start = 20, .cpu = 5, .memory = 100 << 20, .unit = "app-test.Editor-200.scope" },
            .{ .pid = 500, .ppid = 1, .name = "daemon", .comm = "daemon", .program = "daemon", .uid = 4242, .start = 30, .cpu = 2, .memory = 10 << 20, .unit = "daemon.service" },
            .{ .pid = self, .ppid = 1, .name = "zmon-test", .comm = "test", .uid = me, .start = 40, .cpu = 1, .memory = 20 << 20 },
        });
        f.snap.procs = procs;
        f.snap.cores = try a.dupe(f32, &.{ 10, 20, 30, 40 });
        f.snap.samples = 2;
        f.snap.procs_read = true;
        f.snap.process_count = @intCast(procs.len);
        state.index.add("test.Browser", "[Desktop Entry]\nType=Application\nName=Browser\nExec=browser\n");
        state.index.add("test.Editor", "[Desktop Entry]\nType=Application\nName=Editor\nExec=editor\n");
        state.useSample(&f.snap);
        return f;
    }

    fn deinit(f: *Fixture) void {
        f.snap.deinit();
        std.testing.allocator.destroy(f);
    }
};

test "the fixture groups as the app would: two apps, a service, the kernel" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    const f = try Fixture.init(&state);
    defer f.deinit();
    try std.testing.expectEqual(@as(usize, 2), state.appCount());
    try std.testing.expectEqualStrings("Browser", state.groups[0].name); // busiest app first
    try std.testing.expectEqual(@as(usize, 3), state.groups[0].members.len);
}

test "arrow keys move the selection, Home and End jump, and Delete asks before ending" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    const f = try Fixture.init(&state);
    defer f.deinit();
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try t.clickText("Processes");
    t.settle(0.2);
    const n = state.proc_rows.len;
    try std.testing.expectEqual(f.snap.procs.len - 2, n); // all but the two kernel threads
    _ = t.shortcut(.{ .key = ui.Shortcut.down });
    try std.testing.expectEqual(@as(?usize, 0), state.selectedRow());
    try std.testing.expectEqual(@as(i32, 100), state.selected_proc); // busiest first
    _ = t.shortcut(.{ .key = ui.Shortcut.down });
    try std.testing.expectEqual(@as(i32, 101), state.selected_proc);
    _ = t.shortcut(.{ .key = ui.Shortcut.up });
    try std.testing.expectEqual(@as(i32, 100), state.selected_proc);
    t.key(.end);
    try std.testing.expectEqual(n - 1, state.selectedRow().?);
    t.key(.home);
    try std.testing.expectEqual(@as(?usize, 0), state.selectedRow());
    t.key(.delete); // asks first; the test never confirms, so nothing is signalled
    try std.testing.expect(state.confirm);
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(0.3);
    try std.testing.expect(!state.confirm);
    _ = t.shortcut(.{ .key = ui.Shortcut.escape }); // with no search, Escape goes back to the sidebar
    try std.testing.expectEqual(state.nav_ids.get(.processes), t.ctx.focus);
    try std.testing.expectEqual(@as(i32, 100), state.selected_proc); // and the selection stays
}

test "Right shows an app's processes and Left hides them again" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    const f = try Fixture.init(&state);
    defer f.deinit();
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    _ = t.shortcut(.{ .key = ui.Shortcut.down }); // Browser
    try std.testing.expectEqual(@as(i32, 100), state.selected_app);
    t.key(.right);
    try std.testing.expect(state.expanded.contains(100));
    _ = t.shortcut(.{ .key = ui.Shortcut.down }); // onto its busiest helper
    try std.testing.expectEqual(@as(i32, 101), state.selected_app);
    t.key(.left); // back to the app
    try std.testing.expectEqual(@as(i32, 100), state.selected_app);
    t.key(.left);
    try std.testing.expect(!state.expanded.contains(100));
}

test "End task refuses init, kernel threads, other users' processes and zmon itself" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    const f = try Fixture.init(&state);
    defer f.deinit();
    state.page = .processes;
    state.settings.show_kernel_threads = true;
    state.rebuild();
    for ([_]i32{ 1, 3, 500, std.os.linux.getpid() }) |pid| {
        for (state.toaster.items.items) |e| state.toaster.gpa.free(e.text);
        state.toaster.items.clearRetainingCapacity();
        state.selected_proc = pid;
        state.endTask(false); // refused before any signal is sent
        try std.testing.expect(toasted(&state, "Can't end"));
    }
}

test "sorting by name, user and pid orders the rows, with ties by pid" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    const f = try Fixture.init(&state);
    defer f.deinit();
    state.page = .processes;
    const procs = state.sample.procs;
    state.sortBy(.pid);
    for (state.proc_rows[1..], state.proc_rows[0 .. state.proc_rows.len - 1]) |b, a| try std.testing.expect(procs[a].pid < procs[b].pid);
    state.sortBy(.name);
    // the three "browser"s, by pid
    var seen: [3]i32 = undefined;
    var n: usize = 0;
    for (state.proc_rows) |r| if (std.mem.eql(u8, procs[r].name, "browser")) {
        seen[n] = procs[r].pid;
        n += 1;
    };
    try std.testing.expectEqualSlices(i32, &.{ 100, 101, 102 }, &seen);
    state.sortBy(.user);
    for (state.proc_rows[1..], state.proc_rows[0 .. state.proc_rows.len - 1]) |b, a| {
        const ua = state.users.name(procs[a].uid) orelse "";
        const ub = state.users.name(procs[b].uid) orelse "";
        try std.testing.expect(!std.ascii.lessThanIgnoreCase(ub, ua));
    }
}

test "typing on a list starts a search, and Escape clears it" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try t.clickText("Processes");
    t.settle(0.2);
    const all = state.proc_rows.len;
    t.typeText("s");
    t.settle(0.2);
    try std.testing.expectEqualStrings("s", state.search.text());
    try std.testing.expect(state.proc_rows.len <= all);
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(0.2);
    try std.testing.expectEqualStrings("", state.search.text());
    try std.testing.expectEqual(state.sample.procs.len, state.proc_rows.len); // every process again (the count moves as they come and go)
}

test "Ctrl+number opens pages, Ctrl+comma Settings, and Ctrl+? the shortcuts" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try std.testing.expect(t.shortcut(.{ .key = '2', .cmd = true }));
    try std.testing.expectEqual(app_state.Page.processes, state.page);
    try std.testing.expect(t.shortcut(.{ .key = '4', .cmd = true }));
    try std.testing.expectEqual(app_state.Page.memory, state.page);
    try std.testing.expect(t.shortcut(.{ .key = ',', .cmd = true }));
    try std.testing.expectEqual(app_state.Page.settings, state.page);
    try std.testing.expect(t.shortcut(.{ .key = '?', .cmd = true, .shift = true }));
    t.settle(0.3);
    try std.testing.expect(state.shortcuts_open);
    try std.testing.expect(t.hasText("Keyboard shortcuts"));
    try std.testing.expect(t.hasText("Search apps and processes"));
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(0.4);
    try std.testing.expect(!state.shortcuts_open);
    try std.testing.expect(t.shortcut(.{ .key = 'f', .cmd = true })); // from Settings, search opens Processes
    try std.testing.expectEqual(app_state.Page.processes, state.page);
}

test "Tab reaches the sidebar with a visible focus ring, and Space opens the page" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try std.testing.expect(t.ctx.focus_ring == null); // nothing drawn until a key is pressed
    t.key(.tab); // Apps
    t.key(.tab); // Processes
    t.settle(0.1);
    try std.testing.expect(t.ctx.focus != 0);
    try std.testing.expect(t.ctx.focus_ring != null);
    t.typeText(" ");
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Page.processes, state.page);
}

test "a screen reader is told what the sidebar, headers and rows are" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var els: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &els);
    var apps_tab = false;
    var sorted = false;
    var row = false;
    for (els.items) |e| {
        if (e.role == .tab and std.mem.eql(u8, e.label, "Apps") and e.selected) apps_tab = true;
        if (std.mem.eql(u8, e.label, "Sort by CPU") and std.mem.eql(u8, e.value, "Sorted descending")) sorted = true;
        if (e.role == .row and std.mem.indexOf(u8, e.label, ", CPU ") != null) row = true;
    }
    try std.testing.expect(apps_tab);
    try std.testing.expect(sorted);
    try std.testing.expect(row or state.app_rows.len == 0);
}

test "text size and more contrast apply from Settings" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    state.settings.text_size = .larger;
    state.settings.reduce_motion = true;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try std.testing.expectEqual(@as(f32, 1.3), t.ctx.access.zoom);
    try std.testing.expect(t.ctx.reduced_motion);
    state.settings.reduce_motion = false;
    t.frame();
    try std.testing.expect(!t.ctx.reduced_motion);
}

test "Settings puts the theme gallery after the other settings, with no gap after it" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = true;
    state.chooseTheme(true, "evergarden-fall"); // a theme with a description
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try openSettings(&t, &state);
    const access = t.findText("Accessibility") orelse return error.TextNotFound;
    const card = t.findText("Evergarden Fall") orelse return error.TextNotFound;
    try std.testing.expect(access.y < card.y);
    const desc = t.findText("cozy evergarden theme for vicinae") orelse return error.TextNotFound;
    const next = t.findText("Your themes") orelse return error.TextNotFound;
    try std.testing.expect(next.y - (desc.y + desc.h) < 80);
}

test "Return on the sidebar opens the page and goes into it, and Escape comes back out" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    t.key(.tab); // Apps
    t.key(.tab); // Processes
    t.key(.enter);
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Page.processes, state.page);
    try std.testing.expectEqual(state.list_id, t.ctx.focus); // in the table
    t.key(.escape);
    t.settle(0.1);
    try std.testing.expectEqual(state.nav_ids.get(.processes), t.ctx.focus); // back on the sidebar
    t.setMods(.{ .shift = true });
    t.key(.tab); // up to Apps
    t.setMods(.{});
    t.key(.enter);
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Page.apps, state.page);
    try std.testing.expectEqual(state.list_id, t.ctx.focus);
}

test "Return on Settings goes to its first control, and Escape back to the sidebar" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    t.setMods(.{ .shift = true });
    t.key(.tab); // backwards from the start wraps to the last stop
    t.setMods(.{});
    while (t.ctx.focus != state.nav_ids.get(.settings)) t.key(.tab);
    t.key(.enter);
    t.settle(0.2);
    try std.testing.expectEqual(app_state.Page.settings, state.page);
    try std.testing.expect(t.ctx.focus != state.nav_ids.get(.settings) and t.ctx.focus != 0);
    t.key(.escape);
    t.settle(0.1);
    try std.testing.expectEqual(state.nav_ids.get(.settings), t.ctx.focus);
}

test "the list is one Tab stop, and its keys work once it has the focus" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try t.clickText("Processes");
    t.settle(0.2);
    if (state.proc_rows.len < 2) return error.SkipZigTest;
    var steps: usize = 0;
    while (t.ctx.focus != state.list_id) : (steps += 1) {
        if (steps > 40) return error.ListNeverFocused;
        t.key(.tab);
    }
    t.key(.down);
    try std.testing.expectEqual(@as(?usize, 0), state.selectedRow());
    t.key(.end);
    try std.testing.expectEqual(state.proc_rows.len - 1, state.selectedRow().?);
}

test "Escape retraces the way in: search, then list, then sidebar" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    t.key(.tab); // Apps
    t.key(.tab); // Processes
    const nav = t.ctx.focus;
    try std.testing.expectEqual(state.nav_ids.get(.processes), nav);
    t.key(.enter); // into the list
    t.settle(0.2);
    try std.testing.expectEqual(state.list_id, t.ctx.focus);
    t.typeText("s"); // into the search
    t.settle(0.2);
    try std.testing.expect(t.ctx.focus_is_text);
    try std.testing.expectEqualStrings("s", state.search.text());
    t.key(.escape); // out of the search, which clears
    t.settle(0.1);
    try std.testing.expectEqual(state.list_id, t.ctx.focus);
    try std.testing.expectEqualStrings("", state.search.text());
    t.key(.escape); // out of the list
    t.settle(0.1);
    try std.testing.expectEqual(nav, t.ctx.focus);
    t.key(.escape); // nowhere further to go
    t.settle(0.1);
    try std.testing.expectEqual(nav, t.ctx.focus);
    try std.testing.expectEqual(@as(usize, 0), state.focus_stack.len);
}

test "Escape from a search returns to whatever was focused before it" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    t.key(.tab); // Apps, in the sidebar
    const apps_entry = t.ctx.focus;
    try std.testing.expect(t.shortcut(.{ .key = 'f', .cmd = true }));
    t.settle(0.2);
    try std.testing.expect(t.ctx.focus_is_text);
    t.key(.escape);
    t.settle(0.1);
    try std.testing.expectEqual(apps_entry, t.ctx.focus); // not the list: where it came from
}

test "a click forgets the way back" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    t.key(.tab);
    t.key(.tab);
    t.key(.enter);
    t.settle(0.2);
    try std.testing.expect(state.focus_stack.len > 0);
    try t.clickText("Name");
    t.settle(0.2);
    try std.testing.expectEqual(@as(usize, 0), state.focus_stack.len);
}

/// The label a screen reader gives the focused control.
fn focusedLabel(t: *ui.Tester, arena: std.mem.Allocator) ![]const u8 {
    var els: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena, &els);
    for (els.items) |e| if (e.id == t.ctx.focus) return e.label;
    return "";
}

test "End task's dialog keeps Tab, the arrows and the screen reader to itself, and Cancel returns to the list" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try t.clickText("Processes");
    t.settle(0.2);
    if (state.proc_rows.len < 3) return error.SkipZigTest;
    t.key(.down);
    try std.testing.expectEqual(state.list_id, t.ctx.focus);
    const chosen = state.selected_proc;
    t.key(.delete);
    t.settle(0.3);
    try std.testing.expect(state.confirm);
    try std.testing.expectEqualStrings("End task", try focusedLabel(&t, arena.allocator()));
    // Close, Cancel, Force quit and End task are the only Tab stops, however often Tab is pressed.
    try std.testing.expectEqual(@as(usize, 4), t.ctx.last_focusable_ids.items.len);
    for (0..7) |_| {
        t.key(.tab);
        try std.testing.expect(std.mem.indexOfScalar(u64, t.ctx.last_focusable_ids.items, t.ctx.focus) != null);
    }
    t.key(.down);
    _ = t.shortcut(.{ .key = ui.Shortcut.down });
    try std.testing.expectEqual(chosen, state.selected_proc);
    var els: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &els);
    for (els.items) |e| try std.testing.expect(!std.mem.eql(u8, e.label, "Apps"));
    // Onto Cancel, checked by name before Return, so the test never ends a task.
    while (!std.mem.eql(u8, try focusedLabel(&t, arena.allocator()), "Cancel")) t.key(.tab);
    t.key(.enter);
    t.settle(0.3);
    try std.testing.expect(!state.confirm);
    try std.testing.expectEqual(state.list_id, t.ctx.focus);
}

test "the shortcuts overlay takes the focus and gives it back where it was" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    t.key(.tab);
    const before = t.ctx.focus;
    try std.testing.expect(before != 0);
    try std.testing.expect(t.shortcut(.{ .key = '?', .cmd = true, .shift = true }));
    t.settle(0.3);
    try std.testing.expect(state.shortcuts_open);
    try std.testing.expectEqual(@as(usize, 1), t.ctx.last_focusable_ids.items.len); // its Close button
    const close = t.ctx.focus;
    try std.testing.expect(close != before);
    t.key(.tab);
    try std.testing.expectEqual(close, t.ctx.focus);
    _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    t.settle(0.4);
    try std.testing.expect(!state.shortcuts_open);
    try std.testing.expectEqual(before, t.ctx.focus);
}

fn toasted(state: *app_state.State, part: []const u8) bool {
    for (state.toaster.items.items) |e| if (std.mem.indexOf(u8, e.text, part) != null) return true;
    return false;
}

test "End task acts only on a selection that can be seen" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.page = .processes;
    _ = state.tick(0);
    if (state.proc_rows.len == 0) return error.SkipZigTest;
    state.selected_proc = state.sample.procs[state.proc_rows[0]].pid;
    try std.testing.expect(state.target() != null);
    state.search.set("no process is called this");
    state.rebuild();
    try std.testing.expect(state.target() == null); // hidden by the search
}

test "a process that ignores End task is reported still running, and Force quit stops it" {
    const io = std.testing.io;
    // A child of the test's own that ignores the quit signal: nothing else is signalled.
    var child = std.process.spawn(io, .{
        .argv = &.{ "/bin/sh", "-c", "trap '' TERM; while :; do sleep 1; done" },
        .stdin = .ignore,
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return error.SkipZigTest;
    defer child.kill(io);
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.page = .processes;
    var now: f64 = 0;
    _ = state.tick(now);
    now += 0.3;
    _ = state.tick(now);
    state.selected_proc = child.id.?;
    try std.testing.expect(state.target() != null);
    state.endTask(false);
    try std.testing.expect(toasted(&state, "to quit"));
    for (0..4) |_| {
        now += 1.0;
        _ = state.tick(now);
    }
    try std.testing.expect(toasted(&state, "is still running"));
    state.endTask(true);
    try std.testing.expect(toasted(&state, "Stopped"));
    const term = try child.wait(io);
    try std.testing.expect(term == .signal);
}

test "with the sampler on its own thread, samples arrive and wake the view" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit(); // stops and joins the thread
    state.dark = false;
    state.threaded = true;
    state.page = .processes;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try std.testing.expect(state.worker.running());
    const clock = @import("zmon-system").platform.clock;
    const until = clock.now() + 5;
    while (state.sample.samples < 2 and clock.now() < until) t.pump(0.2);
    try std.testing.expect(state.sample.samples >= 2);
    try std.testing.expect(state.sample.procs_read);
    try std.testing.expect(state.proc_rows.len > 0);
}

test "Ctrl+I shows the selected process's details, its command line included" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try std.testing.expect(t.shortcut(.{ .key = '2', .cmd = true }));
    t.settle(0.4);
    const me = std.os.linux.getpid(); // this test: the one process sure to be ours
    state.selected_proc = me;
    try std.testing.expect(t.shortcut(.{ .key = 'i', .cmd = true }));
    t.settle(0.4);
    try std.testing.expect(state.details_open);
    const d = state.sample.detail orelse return error.NoDetails;
    try std.testing.expectEqual(me, d.pid);
    try std.testing.expect(d.cmdline.len > 0);
    try std.testing.expect(t.hasText("Command line"));
    try std.testing.expect(t.hasText("Copy"));
    try std.testing.expect(t.shortcut(.{ .key = 'i', .cmd = true }));
    t.settle(0.2);
    try std.testing.expect(!t.hasText("Command line"));
}

test "Background opens under the apps with Right, and closes with Left" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    const at = for (state.app_rows, 0..) |r, i| {
        if (r == .background) break i;
    } else return error.SkipZigTest; // nothing in the background here
    const closed = state.app_rows.len;
    t.key(.end); // the heading is the last row while it is closed
    try std.testing.expectEqual(at, state.selectedRow().?);
    try std.testing.expect(state.target() == null); // a heading can't be ended
    t.key(.right);
    try std.testing.expect(state.background_open);
    try std.testing.expect(state.app_rows.len > closed);
    var background: usize = 0;
    for (state.app_rows) |r| switch (r) {
        .group => |g| background += @intFromBool(state.groups[g].kind == .background),
        else => {},
    };
    try std.testing.expect(background > 0);
    t.key(.left);
    try std.testing.expect(!state.background_open);
    try std.testing.expectEqual(closed, state.app_rows.len);
}

test "a held list keeps its order when its sort would change it" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.page = .processes;
    _ = state.tick(0);
    if (state.proc_rows.len < 3) return error.SkipZigTest;
    state.sortBy(.name);
    var before: [3]i32 = undefined;
    for (&before, 0..) |*p, i| p.* = state.sample.procs[state.proc_rows[i]].pid;
    state.hold_order = true; // the pointer is on the list
    state.proc_order = .{ .key = .memory };
    state.rebuild();
    for (before, 0..) |pid, i| try std.testing.expectEqual(pid, state.sample.procs[state.proc_rows[i]].pid);
    state.hold_order = false; // let go: the new order applies
    state.rebuild();
    const procs = state.sample.procs;
    try std.testing.expect(procs[state.proc_rows[0]].memory >= procs[state.proc_rows[1]].memory);
}

test "the lists show CPU as a share of the machine unless asked for one core" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    _ = state.tick(0);
    const cores: f32 = @floatFromInt(@max(1, state.sample.cores.len));
    try std.testing.expectApproxEqAbs(@as(f32, 200) / cores, state.cpuShown(200), 0.001);
    state.settings.cpu_scale = .core;
    try std.testing.expectEqual(@as(f32, 200), state.cpuShown(200));
}

test "a narrow window keeps the sidebar's pages as icons, still named for the keyboard" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try t.init(std.testing.allocator, .init(&state, app_view.view), .{ .width = 880, .height = 560 });
    defer t.deinit();
    t.settle(0.3);
    try std.testing.expect(!t.hasText("Devices")); // no headings, no labels
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var els: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &els);
    var settings = false;
    for (els.items) |e| settings = settings or (e.role == .tab and std.mem.eql(u8, e.label, "Settings"));
    try std.testing.expect(settings);
}

test "searching :port finds the process listening on it" {
    const linux = std.os.linux;
    // A socket of the test's own, listening on a port the kernel picks.
    const fd: i32 = @intCast(linux.socket(linux.AF.INET, linux.SOCK.STREAM, 0));
    defer _ = linux.close(fd);
    var addr: linux.sockaddr.in = .{ .port = 0, .addr = std.mem.nativeToBig(u32, 0x7f000001) };
    try std.testing.expectEqual(@as(usize, 0), linux.bind(fd, @ptrCast(&addr), @sizeOf(linux.sockaddr.in)));
    try std.testing.expectEqual(@as(usize, 0), linux.listen(fd, 1));
    var len: linux.socklen_t = @sizeOf(linux.sockaddr.in);
    _ = linux.getsockname(fd, @ptrCast(&addr), &len);
    const port = std.mem.bigToNative(u16, addr.port);

    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.page = .processes;
    var b: [16]u8 = undefined;
    state.search.set(try std.fmt.bufPrint(&b, ":{d}", .{port}));
    var now: f64 = 0;
    for (0..3) |_| {
        _ = state.tick(now);
        now += 1;
    }
    const me = linux.getpid();
    var found = false;
    for (state.proc_rows) |r| found = found or state.sample.procs[r].pid == me;
    try std.testing.expect(found);
}

test "the details say why a process runs: its parents, its service, and a warning for root" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    const f = try Fixture.init(&state);
    defer f.deinit();
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try t.clickText("Processes");
    state.details_open = true;
    state.selected_proc = 500;
    t.settle(0.3);
    try std.testing.expect(t.hasText("Why it's running"));
    try std.testing.expect(t.hasText("systemd (1) → daemon (500)"));
    try std.testing.expect(t.hasText("The service daemon.service"));
    state.selected_proc = 1;
    t.settle(0.3);
    try std.testing.expect(t.hasText("Runs as root: it can change anything on this machine."));
}

test "closing Background from its heading doesn't pull the rows out from under the list" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    const f = try Fixture.init(&state);
    defer f.deinit();
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try t.clickText("Background");
    t.settle(0.2);
    try std.testing.expect(state.background_open);
    try std.testing.expect(t.hasText("daemon")); // rows after the heading are drawn
    try t.clickText("Background"); // closing: the list shrinks while it is being drawn
    t.settle(0.2);
    try std.testing.expect(!state.background_open);
}

/// Every page, every list key, the details and the searches, on whatever
/// sample the state holds: nothing may crash, however little there is.
fn pressEverything(t: *ui.Tester, state: *app_state.State) !void {
    const pages = [_]app_state.Page{ .apps, .processes, .cpu, .memory, .disk, .network, .battery, .settings, .apps };
    for (pages) |page| {
        state.page = page;
        t.settle(0.1);
        for ([_]@TypeOf(t.ctx.input.key.?){ .down, .down, .up, .end, .home, .right, .right, .left, .left, .enter, .page_down, .page_up, .delete, .escape, .tab, .escape }) |key| t.key(key);
        _ = t.shortcut(.{ .key = 'i', .cmd = true }); // details
        t.settle(0.1);
        state.confirm = false; // never confirm an End task here
        t.setMods(.{ .shift = true });
        t.key(.delete); // Force quit asks first too
        t.setMods(.{});
        state.confirm = false;
        t.typeText("zz");
        t.settle(0.1);
        state.search.set(":65000");
        state.rebuild();
        t.settle(0.1);
        state.search.clear();
        state.rebuild();
        _ = t.shortcut(.{ .key = ui.Shortcut.escape });
    }
}

test "a machine with nothing to show (no processes, cores, disks, network or battery) draws every page" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var snap = @import("zmon-system").sampler.Snapshot.init(std.testing.allocator);
    defer snap.deinit();
    snap.samples = 1;
    snap.procs_read = true;
    state.useSample(&snap);
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try pressEverything(&t, &state);
    state.page = .processes;
    t.settle(0.1);
    try std.testing.expect(t.containsText("can't see the processes")); // and says why
}

test "odd processes (a parent loop, empty names, an unknown user) draw every page" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = true;
    var snap = @import("zmon-system").sampler.Snapshot.init(std.testing.allocator);
    defer snap.deinit();
    const a = snap.arena.allocator();
    snap.procs = try a.dupe(core.Proc, &[_]core.Proc{
        .{ .pid = 7, .ppid = 8, .name = "", .uid = 99999, .start = 1, .state = 'Z', .exe_replaced = true },
        .{ .pid = 8, .ppid = 7, .name = "loop", .uid = 99999, .start = 2, .unit = "app-.scope" },
        .{ .pid = 9, .ppid = 9, .name = "self-parent", .start = 3, .unit = "@.service" },
    });
    snap.samples = 2;
    snap.procs_read = true;
    snap.devices.battery = .{ .present = true, .percent = 0, .charging = true };
    state.useSample(&snap);
    state.details_open = true;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    for ([_]i32{ 7, 8, 9 }) |pid| {
        state.selected_proc = pid;
        state.selected_app = pid;
        try pressEverything(&t, &state);
    }
}

test "Ctrl+Shift+P pauses every figure and resumes them" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    t.advance(1.5);
    try std.testing.expect(t.shortcut(.{ .key = 'p', .cmd = true, .shift = true }));
    try std.testing.expect(state.paused);
    const held = state.sample.samples;
    t.advance(2.5); // a few seconds pass: no sample is taken
    try std.testing.expectEqual(held, state.sample.samples);
    try std.testing.expect(t.containsText("Paused"));
    try std.testing.expect(t.shortcut(.{ .key = 'p', .cmd = true, .shift = true }));
    t.advance(1.5);
    try std.testing.expect(state.sample.samples > held);
}

test "dragging the details pane's edge resizes it, within limits, and a double-click resets it" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    const f = try Fixture.init(&state);
    defer f.deinit();
    state.page = .processes;
    state.details_open = true;
    var t: ui.Tester = undefined;
    try tester(&t, &state); // 1180 wide, the full sidebar 236
    defer t.deinit();
    t.settle(0.2);
    const edge_x: f32 = 1180 - 320 - 4; // the middle of the 7-point edge
    t.drag(edge_x, 400, edge_x - 100, 400); // left: wider
    t.settle(0.1);
    try std.testing.expectApproxEqAbs(@as(f32, 420), @as(f32, @floatFromInt(state.settings.details_width)), 2);
    t.drag(edge_x - 100, 400, 20, 400); // far left: the list keeps 420
    t.settle(0.1);
    try std.testing.expectEqual(@as(u16, 1180 - 236 - 420), state.settings.details_width);
    const at: f32 = 1180 - @as(f32, @floatFromInt(state.settings.details_width)) - 4;
    t.drag(at, 400, 1170, 400); // far right: no narrower than 260
    t.settle(0.1);
    try std.testing.expectEqual(@as(u16, 260), state.settings.details_width);
    t.doubleClick(1180 - 260 - 4, 400);
    t.settle(0.1);
    try std.testing.expectEqual(@as(u16, 320), state.settings.details_width);
}

test "hovering a control with a shortcut shows what it does and its keys" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    const f = try Fixture.init(&state);
    defer f.deinit();
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    try std.testing.expect(!t.hasText("Ctrl")); // no keycaps until something is hovered
    try t.hoverText("Processes"); // the sidebar's entry
    t.advance(0.6);
    try std.testing.expect(t.tooltipRect() != null);
    try std.testing.expect(t.hasText("Ctrl"));
    try std.testing.expect(t.hasText("2"));
    try t.hoverText("Pause"); // a toolbar button
    t.advance(0.6);
    try std.testing.expect(t.hasText("Shift"));
    try std.testing.expect(t.hasText("P"));
}

test "double-clicking a row shows its details, on Apps and Processes" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    const f = try Fixture.init(&state);
    defer f.deinit();
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    const browser = t.findText("Browser") orelse return error.TextNotFound;
    t.doubleClick(browser.x + 4, browser.y + browser.h / 2);
    t.settle(0.2);
    try std.testing.expect(state.details_open);
    try std.testing.expectEqual(@as(i32, 100), state.selected_app); // that row's
    try std.testing.expect(!state.expanded.contains(100)); // the arrow opens its processes, not this
    state.details_open = false;
    try t.clickText("Processes");
    t.settle(0.2);
    const daemon = t.findText("daemon") orelse return error.TextNotFound;
    t.doubleClick(daemon.x + 4, daemon.y + daemon.h / 2);
    t.settle(0.2);
    try std.testing.expect(state.details_open);
    try std.testing.expectEqual(@as(i32, 500), state.selected_proc);
}

test "the details pane's close button closes it" {
    var state: app_state.State = .init(std.testing.allocator, std.testing.io, null);
    defer state.deinit();
    state.dark = false;
    const f = try Fixture.init(&state);
    defer f.deinit();
    state.page = .processes;
    state.details_open = true;
    var t: ui.Tester = undefined;
    try tester(&t, &state);
    defer t.deinit();
    t.settle(0.2);
    // Nothing selected: the pane's title row still has its close button.
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var els: std.ArrayList(ui.access.Element) = .empty;
    try ui.access.tree(&t.ctx, arena.allocator(), &els);
    const close = for (els.items) |e| {
        if (std.mem.eql(u8, e.label, "Close details")) break e;
    } else return error.NoCloseButton;
    const r = t.ctx.rects.get(close.id) orelse return error.NoRect;
    t.click(r.x + r.w / 2, r.y + r.h / 2);
    t.settle(0.2);
    try std.testing.expect(!state.details_open);
}
