//! zmon-system: reads the machine. It depends on zmon-core and the OS, never on
//! nanoui.
pub const platform = @import("platform/root.zig");
pub const apps = @import("apps/root.zig");
pub const sampler = @import("sampler/root.zig");

test {
    _ = platform;
    _ = apps;
    _ = sampler;
}
