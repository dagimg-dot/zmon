//! zmon-system: reads the machine. It depends on zmon-core and the OS, never on
//! nanoui.
pub const platform = @import("platform/root.zig");
pub const apps = @import("apps/root.zig");

test {
    _ = platform;
    _ = apps;
}
