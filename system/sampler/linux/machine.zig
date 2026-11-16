//! What the machine is called: the device tree's model on Macs and other ARM
//! machines ("Apple MacBook Pro (14-inch, M1 Pro, 2021)"), the processor's model
//! name elsewhere.
const std = @import("std");
const files = @import("../../platform/root.zig").files;

/// Writes the machine's name into `out` and returns it; "" when nothing says.
pub fn name(io: std.Io, out: []u8) []const u8 {
    var buf: [16384]u8 = undefined;
    if (files.read(io, .cwd(), "/proc/device-tree/model", &buf)) |text| {
        const found = fromDeviceTree(text);
        if (found.len > 0) return copy(out, found);
    } else |_| {}
    // Only the first processor's block matters, so a cut-off read is fine.
    if (files.read(io, .cwd(), "/proc/cpuinfo", &buf)) |text| return copy(out, fromCpuinfo(text)) else |_| {}
    return "";
}

/// The device tree writes the model as a C string.
pub fn fromDeviceTree(text: []const u8) []const u8 {
    return std.mem.trim(u8, std.mem.sliceTo(text, 0), " \t\n");
}

/// The value of the first "model name" line.
pub fn fromCpuinfo(text: []const u8) []const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "model name")) continue;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return "";
        return std.mem.trim(u8, line[colon + 1 ..], " \t");
    }
    return "";
}

fn copy(out: []u8, text: []const u8) []const u8 {
    const n = @min(out.len, text.len);
    @memcpy(out[0..n], text[0..n]);
    return out[0..n];
}

test "the device tree's model loses its terminating zero" {
    try std.testing.expectEqualStrings("Apple MacBook Pro (14-inch, M1 Pro, 2021)", fromDeviceTree("Apple MacBook Pro (14-inch, M1 Pro, 2021)\x00"));
}

test "cpuinfo gives the first processor's model name" {
    const text = "processor\t: 0\nvendor_id\t: GenuineIntel\nmodel name\t: 12th Gen Intel(R) Core(TM) i7-12700H\nflags\t\t: fpu\n\nprocessor\t: 1\nmodel name\t: other\n";
    try std.testing.expectEqualStrings("12th Gen Intel(R) Core(TM) i7-12700H", fromCpuinfo(text));
    try std.testing.expectEqualStrings("", fromCpuinfo("processor\t: 0\nCPU part\t: 0x024\n"));
}

test "a long name is cut to the space given" {
    var out: [5]u8 = undefined;
    try std.testing.expectEqualStrings("Apple", copy(&out, "Apple MacBook"));
}
