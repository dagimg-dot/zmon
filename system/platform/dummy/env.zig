//! For systems without XDG directories.
pub fn get(name: [:0]const u8) ?[]const u8 {
    _ = name;
    return null;
}

pub fn home() []const u8 {
    return ".";
}
