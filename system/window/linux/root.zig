//! The Wayland compositors that say which process owns a window: niri, sway
//! and Hyprland, each over its own socket, found from its environment. Each
//! asks once with a short timeout, so a stuck compositor can't hold the
//! sampler. GNOME and KDE don't offer this without an extension: there, the
//! list is empty and zmon goes by the processes alone.
const std = @import("std");
const core = @import("zmon-core");
const env = @import("../../platform/root.zig").env;
const ipc = @import("ipc.zig");
pub const niri = @import("niri.zig");
pub const sway = @import("sway.zig");
pub const hyprland = @import("hyprland.zig");

pub fn list(io: std.Io, out: []core.Window) usize {
    _ = io;
    var buf: [256 * 1024]u8 = undefined;
    var fba: std.heap.FixedBufferAllocator = .init(&buf);
    const a = fba.allocator();
    if (env.get("NIRI_SOCKET")) |path| {
        const reply = ipc.ask(a, path, "\"Windows\"\n", .line) orelse return 0;
        return niri.parse(a, reply, out);
    }
    if (env.get("SWAYSOCK")) |path| {
        const reply = ipc.ask(a, path, &sway.get_tree, .i3) orelse return 0;
        return sway.parse(a, reply, out);
    }
    if (env.get("HYPRLAND_INSTANCE_SIGNATURE")) |sig| {
        var path: [256]u8 = undefined;
        const runtime = env.get("XDG_RUNTIME_DIR") orelse return 0;
        const p = std.fmt.bufPrint(&path, "{s}/hypr/{s}/.socket.sock", .{ runtime, sig }) catch return 0;
        const reply = ipc.ask(a, p, "j/clients", .until_closed) orelse return 0;
        return hyprland.parse(a, reply, out);
    }
    return 0;
}

test {
    _ = ipc;
    _ = niri;
    _ = sway;
    _ = hyprland;
}

test "on this machine, asking the compositor never fails loudly" {
    var out: [64]core.Window = undefined;
    _ = list(std.testing.io, &out);
}
