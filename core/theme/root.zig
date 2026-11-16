//! Themes: their colours, the files they are written in, and the ones zmon ships.
pub const color = @import("color.zig");
pub const toml = @import("toml.zig");
pub const theme = @import("theme.zig");

pub const Rgba = color.Rgba;
pub const Token = theme.Token;
pub const Palette = theme.Palette;
pub const Theme = theme.Theme;
pub const Library = theme.Library;

test {
    _ = color;
    _ = toml;
    _ = theme;
}
