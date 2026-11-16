//! zmon's one typeface: Hanken Grotesk, a variable font (weights 100 to 900)
//! shipped inside the binary, so it looks the same on every machine. The theme
//! names it, so every widget draws in it. Glyphs it lacks, such as Ethiopic or
//! CJK, fall through to the system's fonts.
//!
//! The file is the Latin subset used by anquar (SIL Open Font License, in
//! `fonts/OFL-HankenGrotesk.txt`), unpacked from WOFF2 with `woff2_decompress`
//! because nanoui reads TrueType.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;

/// The family name inside the font file.
pub const family = "Hanken Grotesk";

const hanken = @embedFile("fonts/HankenGrotesk-latin.ttf");

/// Makes `family` available to every window. Call it before the first window opens.
pub fn register() bool {
    return ui.registerFont(hanken);
}

test "Hanken Grotesk registers" {
    try std.testing.expect(register());
}
