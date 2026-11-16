//! The themes zmon ships: its own Graphite pair first, then the ones ported
//! from vicinae, families together (see THEMES.md).
const std = @import("std");
const theme = @import("theme.zig");
const color = @import("color.zig");

pub const File = struct { id: []const u8, text: []const u8 };

pub const files = [_]File{
    .{ .id = "graphite-dark", .text = @embedFile("themes/graphite-dark.toml") },
    .{ .id = "graphite-light", .text = @embedFile("themes/graphite-light.toml") },
    .{ .id = "ayu-dark", .text = @embedFile("themes/ayu-dark.toml") },
    .{ .id = "ayu-mirage", .text = @embedFile("themes/ayu-mirage.toml") },
    .{ .id = "catppuccin-frappe", .text = @embedFile("themes/catppuccin-frappe.toml") },
    .{ .id = "catppuccin-latte", .text = @embedFile("themes/catppuccin-latte.toml") },
    .{ .id = "catppuccin-macchiato", .text = @embedFile("themes/catppuccin-macchiato.toml") },
    .{ .id = "catppuccin-mocha", .text = @embedFile("themes/catppuccin-mocha.toml") },
    .{ .id = "dracula", .text = @embedFile("themes/dracula.toml") },
    .{ .id = "elementary-dark", .text = @embedFile("themes/elementary-dark.toml") },
    .{ .id = "elementary-light", .text = @embedFile("themes/elementary-light.toml") },
    .{ .id = "evergarden-fall", .text = @embedFile("themes/evergarden-fall.toml") },
    .{ .id = "evergarden-spring", .text = @embedFile("themes/evergarden-spring.toml") },
    .{ .id = "evergarden-summer", .text = @embedFile("themes/evergarden-summer.toml") },
    .{ .id = "evergarden-winter", .text = @embedFile("themes/evergarden-winter.toml") },
    .{ .id = "gruvbox-dark", .text = @embedFile("themes/gruvbox-dark.toml") },
    .{ .id = "gruvbox-light", .text = @embedFile("themes/gruvbox-light.toml") },
    .{ .id = "kanagawa", .text = @embedFile("themes/kanagawa.toml") },
    .{ .id = "libadwaita-dark", .text = @embedFile("themes/libadwaita-dark.toml") },
    .{ .id = "libadwaita-light", .text = @embedFile("themes/libadwaita-light.toml") },
    .{ .id = "nord", .text = @embedFile("themes/nord.toml") },
    .{ .id = "nord-light", .text = @embedFile("themes/nord-light.toml") },
    .{ .id = "one-dark", .text = @embedFile("themes/one-dark.toml") },
    .{ .id = "rose-pine", .text = @embedFile("themes/rose-pine.toml") },
    .{ .id = "rose-pine-dawn", .text = @embedFile("themes/rose-pine-dawn.toml") },
    .{ .id = "rose-pine-moon", .text = @embedFile("themes/rose-pine-moon.toml") },
    .{ .id = "solarized-dark", .text = @embedFile("themes/solarized-dark.toml") },
    .{ .id = "solarized-light", .text = @embedFile("themes/solarized-light.toml") },
    .{ .id = "solarized-osaka", .text = @embedFile("themes/solarized-osaka.toml") },
    .{ .id = "tokyo-night", .text = @embedFile("themes/tokyo-night.toml") },
    .{ .id = "tokyo-night-storm", .text = @embedFile("themes/tokyo-night-storm.toml") },
    .{ .id = "vesper", .text = @embedFile("themes/vesper.toml") },
    .{ .id = "zenwritten-dark", .text = @embedFile("themes/zenwritten-dark.toml") },
    .{ .id = "zenwritten-light", .text = @embedFile("themes/zenwritten-light.toml") },
};

/// Adds every built-in theme to `lib`.
pub fn addAll(lib: *theme.Library) void {
    for (files) |f| lib.add(f.id, f.text);
}

test "every built-in theme reads cleanly and its text can be read on its background" {
    var lib = theme.Library.init(std.testing.allocator);
    defer lib.deinit();
    addAll(&lib);
    lib.resolveAll();
    try std.testing.expectEqual(@as(usize, 0), lib.problems.items.len);
    try std.testing.expectEqual(files.len, lib.themes.items.len);
    var failed: usize = 0;
    for (lib.themes.items) |*t| {
        const bg = t.color(.background);
        const checks = [_]struct { what: []const u8, ratio: f32, min: f32 }{
            .{ .what = "text", .ratio = color.Rgba.contrast(t.color(.foreground), bg), .min = 4.0 },
            .{ .what = "muted text", .ratio = color.Rgba.contrast(t.color(.muted), bg), .min = 2.4 },
            .{ .what = "text on accent", .ratio = color.Rgba.contrast(t.color(.accent_fg), t.color(.accent)), .min = 3.0 },
            .{ .what = "selected text", .ratio = color.Rgba.contrast(t.color(.selection_fg).over(t.color(.selection_bg)), t.color(.selection_bg).over(bg)), .min = 3.0 },
        };
        if (t.unreadable > 0) {
            std.debug.print("{s}: {d} colours unreadable\n", .{ t.id, t.unreadable });
            failed += 1;
        }
        for (checks) |ch| if (ch.ratio < ch.min) {
            std.debug.print("{s}: {s} {d:.2} < {d:.1}\n", .{ t.id, ch.what, ch.ratio, ch.min });
            failed += 1;
        };
    }
    try std.testing.expectEqual(@as(usize, 0), failed);
}

test "there are dark and light themes, and Evergarden Summer counts as light" {
    var lib = theme.Library.init(std.testing.allocator);
    defer lib.deinit();
    addAll(&lib);
    lib.resolveAll();
    var dark: usize = 0;
    for (lib.themes.items) |t| {
        if (t.dark) dark += 1;
    }
    try std.testing.expect(dark >= 20 and lib.themes.items.len - dark >= 10);
    try std.testing.expect(!lib.find("evergarden-summer").?.dark);
}

test "the embedded list is exactly the files in core/theme/themes" {
    const io = std.testing.io;
    var dir = std.Io.Dir.cwd().openDir(io, "core/theme/themes", .{ .iterate = true }) catch return error.SkipZigTest;
    defer dir.close(io);
    var it = dir.iterate();
    var n: usize = 0;
    while (try it.next(io)) |e| {
        const id = std.mem.cutSuffix(u8, e.name, ".toml") orelse continue;
        n += 1;
        for (files) |f| {
            if (std.mem.eql(u8, f.id, id)) break;
        } else {
            std.debug.print("{s}.toml is not in builtin.files\n", .{id});
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(files.len, n);
}
