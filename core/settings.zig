//! What a person can change in Settings, read from and written to a small
//! TOML file. Unknown keys are ignored and a bad value keeps its default, so
//! an old or hand-edited file never stops zmon from starting.
const std = @import("std");
const toml = @import("theme/toml.zig");

pub const Appearance = enum { system, light, dark };

/// How much history the graphs show.
pub const Span = enum(u16) {
    minute = 60,
    five_minutes = 300,

    pub fn seconds(s: Span) usize {
        return @backingInt(s);
    }
};

/// A theme's id (its file name without .toml), kept inline so settings own no memory.
pub const ThemeId = struct {
    buf: [64]u8 = undefined,
    len: u8 = 0,

    pub fn init(id: []const u8) ThemeId {
        var t: ThemeId = .{};
        t.set(id);
        return t;
    }

    pub fn set(t: *ThemeId, id: []const u8) void {
        const n: u8 = @intCast(@min(id.len, t.buf.len));
        @memcpy(t.buf[0..n], id[0..n]);
        t.len = n;
    }

    pub fn slice(t: *const ThemeId) []const u8 {
        return t.buf[0..t.len];
    }
};

pub const Settings = struct {
    appearance: Appearance = .system,
    dark_theme: ThemeId = .init("graphite-dark"),
    light_theme: ThemeId = .init("graphite-light"),
    colored_graphs: bool = true,
    span: Span = .minute,
    show_kernel_threads: bool = true,
    confirm_end_task: bool = true,

    /// Settings from a file's text. Anything missing or unreadable keeps its default.
    pub fn parse(scratch: std.mem.Allocator, text: []const u8) Settings {
        var s: Settings = .{};
        var problem: toml.Problem = .{};
        const entries = toml.parse(scratch, text, &problem) catch return s;
        if (toml.getString(entries, "appearance.mode")) |v| s.appearance = std.meta.stringToEnum(Appearance, v) orelse s.appearance;
        if (toml.getString(entries, "appearance.dark_theme")) |v| if (validId(v)) s.dark_theme.set(v);
        if (toml.getString(entries, "appearance.light_theme")) |v| if (validId(v)) s.light_theme.set(v);
        s.colored_graphs = boolean(entries, "graphs.colored") orelse s.colored_graphs;
        if (number(entries, "graphs.history")) |n| s.span = std.enums.fromInt(Span, n) orelse s.span;
        s.show_kernel_threads = boolean(entries, "processes.kernel_threads") orelse s.show_kernel_threads;
        s.confirm_end_task = boolean(entries, "processes.confirm_end_task") orelse s.confirm_end_task;
        return s;
    }

    /// The settings as a file zmon can read back.
    pub fn write(s: *const Settings, out: *std.Io.Writer) std.Io.Writer.Error!void {
        try out.print(
            \\# zmon settings, written by zmon. Edit while zmon is closed; comments and unknown keys are not kept.
            \\
            \\[appearance]
            \\mode = "{t}"
            \\dark_theme = "{s}"
            \\light_theme = "{s}"
            \\
            \\[graphs]
            \\colored = {}
            \\history = {d}
            \\
            \\[processes]
            \\kernel_threads = {}
            \\confirm_end_task = {}
            \\
        , .{
            s.appearance,
            s.dark_theme.slice(),
            s.light_theme.slice(),
            s.colored_graphs,
            s.span.seconds(),
            s.show_kernel_threads,
            s.confirm_end_task,
        });
    }
};

/// A theme id is a file name: letters, digits, - and _.
pub fn validId(id: []const u8) bool {
    if (id.len == 0 or id.len > 64) return false;
    for (id) |ch| if (!(std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_')) return false;
    return true;
}

fn boolean(entries: []const toml.Entry, path: []const u8) ?bool {
    const v = toml.get(entries, path) orelse return null;
    return switch (v) {
        .boolean => |b| b,
        else => null,
    };
}

fn number(entries: []const toml.Entry, path: []const u8) ?u16 {
    const v = toml.get(entries, path) orelse return null;
    return switch (v) {
        .number => |n| if (n >= 0 and n <= 65535) @intFromFloat(n) else null,
        else => null,
    };
}

test "settings round-trip through their file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var s: Settings = .{
        .appearance = .dark,
        .dark_theme = .init("catppuccin-mocha"),
        .light_theme = .init("gruvbox-light"),
        .colored_graphs = false,
        .span = .five_minutes,
        .show_kernel_threads = false,
        .confirm_end_task = false,
    };
    var buf: [1024]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try s.write(&w);
    const back = Settings.parse(arena.allocator(), w.buffered());
    try std.testing.expectEqual(Appearance.dark, back.appearance);
    try std.testing.expectEqualStrings("catppuccin-mocha", back.dark_theme.slice());
    try std.testing.expectEqualStrings("gruvbox-light", back.light_theme.slice());
    try std.testing.expect(!back.colored_graphs);
    try std.testing.expectEqual(Span.five_minutes, back.span);
    try std.testing.expect(!back.show_kernel_threads and !back.confirm_end_task);
    s = back;
}

test "a broken or strange file keeps the defaults it can't read" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const defaults: Settings = .{};
    const broken = Settings.parse(arena.allocator(), "[appearance\nmode = \"dark\"\n");
    try std.testing.expectEqual(defaults.appearance, broken.appearance);
    const odd = Settings.parse(arena.allocator(),
        \\[appearance]
        \\mode = "sepia"
        \\dark_theme = "../../etc/passwd"
        \\[graphs]
        \\history = 7
        \\colored = "yes"
        \\[future]
        \\thing = 1
    );
    try std.testing.expectEqual(Appearance.system, odd.appearance);
    try std.testing.expectEqualStrings("graphite-dark", odd.dark_theme.slice());
    try std.testing.expectEqual(Span.minute, odd.span);
    try std.testing.expect(odd.colored_graphs);
}
