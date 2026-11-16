//! Settings: appearance and the theme gallery, graphs, processes, a person's
//! own themes, and about. Every change applies at once and is saved.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const core = @import("zmon-core");
const system = @import("zmon-system");
const app = @import("../../app/state.zig");
const theme = @import("../../ui/theme.zig");
const controls = @import("../../ui/controls.zig");
const row = @import("row.zig");
const gallery = @import("gallery.zig");

const State = app.State;

pub fn page(c: *ui.Context, s: *State, k: theme.Colors) void {
    const scroll = ui.div(c).column().wFull().grow().h(0).scrollY();
    defer scroll.end();
    const col = ui.div(c).column().wFull().maxW(900).px(28).pt(24).pb(32);
    defer col.end();
    ui.text(c, "Settings", .{ .size = 22, .weight = .bold, .color = k.text });
    appearance(c, s, k);
    graphs(c, s, k);
    processes(c, s, k);
    accessibility(c, s, k);
    yourThemes(c, s, k);
    about(c, s, k);
    {
        const r = ui.div(c).row().wFull().pt(20);
        defer r.end();
        if (controls.button(c, k, "Reset to defaults", .{})) s.resetSettings();
    }
}

fn appearance(c: *ui.Context, s: *State, k: theme.Colors) void {
    row.heading(c, k, "Appearance");
    {
        const g = row.group(c, k, "appearance");
        defer g.end();
        const r = row.begin(c, k, "mode", "Light or dark", "Follow your desktop's light or dark setting, or always use one.", true);
        defer r.end();
        var i: usize = @backingInt(s.settings.appearance);
        if (controls.segmented(c, k, "appearance", &.{ "Match system", "Light", "Dark" }, &i)) {
            s.settings.appearance = @fromBackingInt(@intCast(i));
            s.gallery_dark = null;
            s.save();
        }
    }
    // Which kind of theme the gallery shows: the one Appearance uses, or under
    // Match system, the one picked here (opening on the one in effect).
    const showing_dark = switch (s.settings.appearance) {
        .light => false,
        .dark => true,
        .system => s.gallery_dark orelse k.dark,
    };
    const head = ui.div(c).row().wFull().px(4).pt(18).pb(8).itemsCenter().gap(12);
    {
        defer head.end();
        ui.text(c, if (showing_dark) "Dark theme" else "Light theme", .{ .size = 12.5, .weight = .semibold, .color = k.secondary });
        ui.spacer(c);
        if (s.settings.appearance == .system) {
            var tab: usize = if (showing_dark) 0 else 1;
            if (controls.segmented(c, k, "kind", &.{ "When it's dark", "When it's light" }, &tab)) s.gallery_dark = tab == 0;
        }
    }
    gallery.view(c, s, k, showing_dark);
    gallery.details(c, k, s.theme(showing_dark));
    if (s.themeMissing(showing_dark)) {
        const id = if (showing_dark) s.settings.dark_theme.slice() else s.settings.light_theme.slice();
        ui.text(c, c.print("Using {s}: the theme \"{s}\" wasn't found.", .{ s.theme(showing_dark).name, id }), .{ .size = 12, .color = k.danger, .wrap = true });
    }
}

fn graphs(c: *ui.Context, s: *State, k: theme.Colors) void {
    row.heading(c, k, "Graphs");
    const g = row.group(c, k, "graphs");
    defer g.end();
    if (row.switchRow(c, k, "colored", "Coloured graphs", "Each device's graph in its own colour from the theme. Off, every graph uses the text colour.", true, &s.settings.colored_graphs)) s.save();
    {
        const r = row.begin(c, k, "span", "Graphs show the last", "", false);
        defer r.end();
        var i: usize = if (s.settings.span == .minute) 0 else 1;
        if (controls.segmented(c, k, "span-choice", &.{ "1 minute", "5 minutes" }, &i)) {
            s.settings.span = if (i == 0) .minute else .five_minutes;
            s.save();
        }
    }
}

fn processes(c: *ui.Context, s: *State, k: theme.Colors) void {
    row.heading(c, k, "Apps and processes");
    const g = row.group(c, k, "processes");
    defer g.end();
    if (row.switchRow(c, k, "kernel", "Show the system's own tasks", "The kernel's threads, listed in Processes.", true, &s.settings.show_kernel_threads)) {
        s.save();
        s.rebuild();
    }
    if (row.switchRow(c, k, "confirm", "Ask before ending a task", "End task asks first, so an app with unsaved work isn't closed by a stray click.", false, &s.settings.confirm_end_task)) s.save();
}

fn accessibility(c: *ui.Context, s: *State, k: theme.Colors) void {
    row.heading(c, k, "Accessibility");
    const g = row.group(c, k, "accessibility");
    defer g.end();
    {
        const r = row.begin(c, k, "text-size", "Text size", "Makes every word in zmon larger.", true);
        defer r.end();
        var i: usize = @backingInt(s.settings.text_size);
        if (controls.segmented(c, k, "text-size-choice", &.{ "Default", "Large", "Larger" }, &i)) {
            s.settings.text_size = @fromBackingInt(@intCast(i));
            s.save();
        }
    }
    if (row.switchRow(c, k, "contrast", "More contrast", "Quieter text and lines are drawn stronger, in every theme.", false, &s.settings.more_contrast)) s.save();
    if (row.switchRow(c, k, "motion", "Reduce motion", "Buttons, dialogs and messages appear without moving.", false, &s.settings.reduce_motion)) s.save();
    {
        const r = row.begin(c, k, "keys", "Keyboard shortcuts", "Every page, list and action has one. Ctrl+? shows them anywhere.", false);
        defer r.end();
        if (controls.button(c, k, "Show", .{})) s.shortcuts_open = true;
    }
}

fn yourThemes(c: *ui.Context, s: *State, k: theme.Colors) void {
    row.heading(c, k, "Your themes");
    const g = row.group(c, k, "your-themes");
    defer g.end();
    {
        const where = if (s.config) |at| at.themes else "";
        const help = if (where.len > 0)
            c.print("Put theme files (.toml, in vicinae's format) in {s}. They appear when Settings opens.", .{where})
        else
            "Themes can't be added on this system.";
        const r = row.begin(c, k, "add", "Add your own themes", help, true);
        defer r.end();
        if (s.config) |at| {
            if (controls.button(c, k, "Open folder", .{ .icon = "folder" })) {
                if (!system.config.makeThemesFolder(s.io, at) or !nanoui.shell.openPath(at.themes))
                    s.toaster.push(.{ .title = "Couldn't open the theme folder", .message = "" });
            }
        }
    }
    for (s.themes.problems.items) |p| {
        const r = row.begin(c, k, p.id, c.print("{s}.toml couldn't be read", .{p.id}), c.print("Line {d}: expected {s}.", .{ p.line, p.message }), false);
        defer r.end();
        ui.icon(c, "info.circle", .{ .size = 14, .frame = 18, .color = k.danger });
    }
}

fn about(c: *ui.Context, s: *State, k: theme.Colors) void {
    row.heading(c, k, "About");
    const g = row.group(c, k, "about");
    defer g.end();
    const rows = [_]struct { key: []const u8, label: []const u8, value: []const u8 }{
        .{ .key = "version", .label = "zmon", .value = "Version 0.0.1" },
        .{ .key = "machine", .label = "This machine", .value = if (s.sampler.machine().len > 0) s.sampler.machine() else "Unknown" },
        .{ .key = "typeface", .label = "Typeface", .value = "Lexend" },
        .{ .key = "themes", .label = "Themes", .value = c.print("{d}: Graphite by zmon, the rest ported from vicinae (GPL-3.0), palettes by their authors", .{s.themes.themes.items.len}) },
    };
    for (rows, 0..) |it, i| {
        const r = row.begin(c, k, it.key, it.label, "", i == 0);
        defer r.end();
        const v = ui.div(c).row().maxW(420).justifyEnd();
        defer v.end();
        ui.text(c, it.value, .{ .size = 12.5, .color = k.secondary, .wrap = true });
    }
}
