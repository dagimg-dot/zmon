//! Launcher entries and icons from the freedesktop directories.
pub const index = @import("index.zig");
pub const loader = @import("loader.zig");
pub const icons = @import("icons.zig");

pub const Entry = index.Entry;
pub const Index = index.Index;
pub const loadEntries = loader.loadEntries;
pub const Icons = icons.Cache;
pub const Icon = icons.Icon;
pub const IconKind = icons.Kind;

test {
    _ = index;
    _ = loader;
    _ = icons;
    _ = @import("desktop_entry.zig");
    _ = @import("paths.zig");
}
