//! What the machine readers need from the OS: quiet file reads.
const builtin = @import("builtin");

pub const files = switch (builtin.os.tag) {
    .linux => @import("linux/files.zig"),
    else => @import("dummy/files.zig"),
};

test {
    _ = files;
}
