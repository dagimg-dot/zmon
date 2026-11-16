//! zmon-core: plain data shared by the machine readers and the UI. It makes no
//! OS calls and knows nothing of nanoui.
pub const types = @import("types.zig");
pub const ring = @import("ring.zig");
pub const fmt = @import("fmt.zig");
pub const text = @import("text.zig");

pub const Proc = types.Proc;
pub const Memory = types.Memory;
pub const Ring = ring.Ring;
pub const history_len = ring.history_len;

test {
    _ = types;
    _ = ring;
    _ = fmt;
    _ = text;
}
