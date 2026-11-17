//! Which process owns which window, from the compositor. A window's app id
//! is what the desktop calls the app, so it names a process whose program
//! says nothing: an Electron or Java app started through a script runs as
//! "electron" or "java", while its window says "equibop".
const std = @import("std");
const builtin = @import("builtin");
const core = @import("zmon-core");

const backend = switch (builtin.os.tag) {
    .linux => @import("linux/root.zig"),
    else => @import("dummy/root.zig"),
};

pub const Window = core.Window;

/// The windows the running compositor shows, into `out`; how many. None
/// when it is one zmon can't ask (or no compositor at all).
pub const list = backend.list;

test "the window backends compile on every OS" {
    std.testing.refAllDecls(backend);
}
