//! zmon's one typeface: Lexend, a variable font (weights 100 to 900) shipped
//! inside the binary, so it looks the same on every machine. The theme names
//! it, so every widget draws in it. Glyphs it lacks, such as Ethiopic or CJK,
//! fall through to the system's fonts.
//!
//! The file is the Latin subset of @fontsource-variable/lexend 5.3.0 (SIL Open
//! Font License, in `assets/fonts/OFL-Lexend.txt`), unpacked from WOFF2 with
//! `woff2_decompress` because nanoui reads TrueType.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

/// The family name inside the font file.
pub const family = "Lexend";

const lexend = @embedFile("assets/fonts/Lexend-latin.ttf");

/// Makes `family` available to every window. Call it before the first window opens.
pub fn register() bool {
    return ui.registerFont(lexend);
}

test "Lexend registers" {
    try std.testing.expect(register());
}
