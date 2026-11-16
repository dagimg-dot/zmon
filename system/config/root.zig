//! Where zmon keeps its settings and finds the themes a person adds, and the
//! reading and writing of both.
const std = @import("std");
const builtin = @import("builtin");
const core = @import("zmon-core");

const platform = switch (builtin.os.tag) {
    .linux => @import("linux/root.zig"),
    else => @import("dummy/root.zig"),
};

/// The two folders zmon uses: one for its settings file, one for theme files.
pub const Location = struct {
    dir: []const u8,
    themes: []const u8,
};

/// A theme file a person added: its id (the file name without .toml) and its text.
pub const UserTheme = struct {
    id: []const u8,
    text: []const u8,
};

/// The standard folders (XDG config and data), or null where there are none.
pub fn location(a: std.mem.Allocator) ?Location {
    return platform.location(a);
}

/// The saved settings, or the defaults when there are none.
pub fn loadSettings(io: std.Io, scratch: std.mem.Allocator, at: Location) core.settings.Settings {
    return platform.loadSettings(io, scratch, at);
}

/// Saves the settings, replacing the file in one step so a crash never leaves half of it.
pub fn saveSettings(io: std.Io, at: Location, s: *const core.settings.Settings) !void {
    return platform.saveSettings(io, at, s);
}

/// Makes sure the theme folder exists, so it can be opened; false when it can't be made.
pub fn makeThemesFolder(io: std.Io, at: Location) bool {
    return platform.makeThemesFolder(io, at);
}

/// Every theme file in the user's theme folder, read into `a`.
pub fn userThemes(io: std.Io, a: std.mem.Allocator, at: Location) []UserTheme {
    return platform.userThemes(io, a, at);
}

test "the config backend compiles on every OS" {
    std.testing.refAllDecls(platform);
    std.testing.refAllDecls(@This());
}
