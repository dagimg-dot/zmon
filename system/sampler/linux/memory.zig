//! Memory and swap, from /proc/meminfo.
const std = @import("std");
const core = @import("zmon-core");
const files = @import("../../platform/root.zig").files;
const Memory = core.Memory;

pub fn read(io: std.Io) Memory {
    var buf: [4096]u8 = undefined;
    const text = files.read(io, .cwd(), "/proc/meminfo", &buf) catch return .{};
    return parseMeminfo(text);
}

fn kb(text: []const u8, key: []const u8) u64 {
    return core.text.field(text, key) * 1024;
}

pub fn parseMeminfo(text: []const u8) Memory {
    return .{
        .total = kb(text, "MemTotal:"),
        .available = kb(text, "MemAvailable:"),
        .cached = kb(text, "Cached:"),
        .shmem = kb(text, "Shmem:"),
        .swap_total = kb(text, "SwapTotal:"),
        .swap_free = kb(text, "SwapFree:"),
    };
}

test "meminfo is read in bytes" {
    const m = parseMeminfo("MemTotal:  1000 kB\nMemAvailable:  400 kB\nCached: 100 kB\nSwapTotal: 50 kB\nSwapFree: 20 kB\n");
    try std.testing.expectEqual(@as(u64, 1000 * 1024), m.total);
    try std.testing.expectEqual(@as(u64, 600 * 1024), m.used());
    try std.testing.expectEqual(@as(u64, 30 * 1024), m.swapUsed());
}
