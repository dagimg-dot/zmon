//! The window's view: a sidebar of pages beside the page itself. The view is a
//! function of the state, drawn again on every input.
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const state = @import("state.zig");
const theme = @import("../ui/theme.zig");
const processes = @import("../pages/processes/root.zig");
const performance = @import("../pages/performance/root.zig");

const State = state.State;
const Page = state.Page;

pub fn view(s: *State, c: *ui.Context) void {
    const dark = s.dark orelse nanoui.isDark();
    // The window takes its font from the theme the view *chose*, not from `c.theme`.
    const chosen = theme.theme(dark);
    c.theme = chosen;
    c.theme_chosen = chosen;
    const k = theme.colors(dark);
    c.frameIn(s.tick(c.time));

    const root = ui.div(c).row().sizeFull().bg(k.page);
    defer root.end();
    sidebar(c, s, k);
    _ = c.leaf(.{ .width = .{ .px = 1 }, .height = .fill, .background = k.separator }, .none, null);
    {
        const main = ui.div(c).column().grow().w(0).hFull().clip();
        defer main.end();
        switch (s.page) {
            .processes => processes.page(c, s, k),
            .performance => performance.page(c, s, k),
        }
    }
    processes.confirmDialog(c, s);
    s.toaster.view(c);
}

fn sidebar(c: *ui.Context, s: *State, k: theme.Colors) void {
    const side = ui.div(c).column().w(188).hFull().bg(k.panel).p(10).gap(2);
    defer side.end();
    {
        const head = ui.div(c).row().h(44).px(8).itemsCenter().gap(8);
        defer head.end();
        ui.text(c, "zmon", .{ .size = 17, .weight = .bold, .color = k.text });
    }
    const items = [_]struct { page: Page, label: []const u8, icon: []const u8 }{
        .{ .page = .processes, .label = "Processes", .icon = "list.bullet" },
        .{ .page = .performance, .label = "Performance", .icon = "waveform.path.ecg" },
    };
    for (items) |it| {
        ui.key(c, it.label);
        const on = s.page == it.page;
        const row = ui.div(c).row().wFull().h(34).px(10).itemsCenter().gap(10).rounded(8).control();
        defer row.end();
        if (on) _ = row.bg(k.selected) else _ = row.hover(k.hover);
        if (row.clicked()) s.page = it.page;
        const ink = if (on) k.selected_text else k.text;
        ui.icon(c, it.icon, .{ .size = 14, .frame = 18, .color = ink });
        ui.text(c, it.label, .{ .size = 13.5, .weight = if (on) .semibold else .regular, .color = ink });
    }
    ui.spacer(c);
    var b1: [24]u8 = undefined;
    var b2: [24]u8 = undefined;
    ui.text(c, c.print("{s} CPU   {s} RAM", .{
        core.fmt.percent(&b1, s.sampler.cpu_pct),
        core.fmt.percent(&b2, if (s.sampler.memory.total > 0) @as(f32, @floatFromInt(s.sampler.memory.used())) * 100 / @as(f32, @floatFromInt(s.sampler.memory.total)) else 0),
    }), .{ .size = 11.5, .color = k.tertiary });
}
