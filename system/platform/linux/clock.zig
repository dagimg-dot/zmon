//! The machine's monotonic clock, which never jumps when the date is set.
const std = @import("std");
const linux = std.os.linux;

/// Seconds since an arbitrary start, never going backwards.
pub fn now() f64 {
    var ts: linux.timespec = undefined;
    if (linux.errno(linux.clock_gettime(.MONOTONIC, &ts)) != .SUCCESS) return 0;
    return @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1e9;
}
