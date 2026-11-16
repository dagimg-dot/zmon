//! zmon-core: plain data shared by the machine readers and the UI. It makes no
//! OS calls and knows nothing of nanoui.
pub const types = @import("types.zig");
pub const ring = @import("ring.zig");
pub const fmt = @import("fmt.zig");
pub const text = @import("text.zig");
pub const search = @import("search.zig");
pub const focus = @import("focus.zig");
pub const settings = @import("settings.zig");
pub const themes = @import("theme/root.zig");

pub const Proc = types.Proc;
pub const Memory = types.Memory;
pub const Ring = ring.Ring;
pub const history_len = ring.history_len;

test {
    _ = types;
    _ = ring;
    _ = fmt;
    _ = text;
    _ = search;
    _ = focus;
    _ = settings;
    _ = themes;
}
