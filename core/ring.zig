//! A fixed-size history, newest last: what the charts draw.
const std = @import("std");

/// An hour at one sample a second: what the longest graph shows. Kept in
/// memory only (14 KB a series).
pub const history_len = 3600;

/// A fixed-size history, newest last.
pub fn Ring(comptime T: type) type {
    return struct {
        const Self = @This();
        items: [history_len]T = @splat(0),
        len: usize = 0,
        next: usize = 0,

        pub fn push(r: *Self, v: T) void {
            r.items[r.next] = v;
            r.next = (r.next + 1) % history_len;
            if (r.len < history_len) r.len += 1;
        }

        /// The `i`-th oldest value; 0 is the oldest still kept.
        pub fn at(r: *const Self, i: usize) T {
            const start = (r.next + history_len - r.len) % history_len;
            return r.items[(start + i) % history_len];
        }

        pub fn max(r: *const Self) T {
            return r.maxOfNewest(r.len);
        }

        /// The largest of the `n` newest values.
        pub fn maxOfNewest(r: *const Self, n: usize) T {
            var m: T = 0;
            for (r.len -| n..r.len) |i| m = @max(m, r.at(i));
            return m;
        }
    };
}

test "ring keeps the newest values in order" {
    var r: Ring(f32) = .{};
    for (0..history_len + 5) |i| r.push(@floatFromInt(i));
    try std.testing.expectEqual(@as(usize, history_len), r.len);
    try std.testing.expectEqual(@as(f32, 5), r.at(0));
    try std.testing.expectEqual(@as(f32, history_len + 4), r.at(history_len - 1));
}
