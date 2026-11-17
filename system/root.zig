//! zmon-system: reads the machine. It depends on zmon-core and the OS, never on
//! nanoui.
pub const platform = @import("platform/root.zig");
pub const apps = @import("apps/root.zig");
pub const sampler = @import("sampler/root.zig");
pub const config = @import("config/root.zig");
pub const desktop = @import("desktop/root.zig");
pub const users = @import("users/root.zig");
pub const window = @import("window/root.zig");

test {
    _ = platform;
    _ = apps;
    _ = sampler;
    _ = config;
    _ = desktop;
    _ = users;
    _ = window;
}
