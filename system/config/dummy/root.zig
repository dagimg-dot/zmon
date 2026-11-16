//! For systems without XDG folders: nothing is saved and no themes are added.
const std = @import("std");
const core = @import("zmon-core");
const config = @import("../root.zig");

pub fn location(a: std.mem.Allocator) ?config.Location {
    _ = a;
    return null;
}

pub fn loadSettings(io: std.Io, scratch: std.mem.Allocator, at: config.Location) core.settings.Settings {
    _ = .{ io, scratch, at };
    return .{};
}

pub fn saveSettings(io: std.Io, at: config.Location, s: *const core.settings.Settings) !void {
    _ = .{ io, at, s };
}

pub fn makeThemesFolder(io: std.Io, at: config.Location) bool {
    _ = .{ io, at };
    return false;
}

pub fn userThemes(io: std.Io, a: std.mem.Allocator, at: config.Location) []config.UserTheme {
    _ = .{ io, a, at };
    return &.{};
}
