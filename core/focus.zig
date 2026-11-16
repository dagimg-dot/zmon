//! Where the keyboard's focus came from. Each step into something (a page
//! from the sidebar, the search from the list) remembers the control it left,
//! and Escape goes back one step, as in a two-pane app. Ids are opaque: the
//! UI's boxes, which can vanish when a page changes, so going back skips any
//! that are no longer drawn.
const std = @import("std");

pub const Stack = struct {
    items: [capacity]u64 = undefined,
    len: usize = 0,

    /// Deeper than any path through zmon; past it the oldest step is dropped.
    pub const capacity = 16;

    /// Remembers `from` before the focus moves into something. Nothing (0)
    /// isn't remembered, and nor is the step already on top, so pressing the
    /// same way in twice needs one Escape out.
    pub fn push(s: *Stack, from: u64) void {
        if (from == 0) return;
        if (s.len > 0 and s.items[s.len - 1] == from) return;
        if (s.len == capacity) {
            std.mem.copyForwards(u64, s.items[0 .. capacity - 1], s.items[1..capacity]);
            s.len -= 1;
        }
        s.items[s.len] = from;
        s.len += 1;
    }

    /// The most recent step that is still drawn (in `alive`) and isn't where
    /// the focus already is, taking it and any it skipped off the stack.
    /// Null when there is none: the caller falls back to its own default.
    pub fn pop(s: *Stack, alive: []const u64, current: u64) ?u64 {
        while (s.len > 0) {
            s.len -= 1;
            const id = s.items[s.len];
            if (id != current and std.mem.indexOfScalar(u64, alive, id) != null) return id;
        }
        return null;
    }

    pub fn clear(s: *Stack) void {
        s.len = 0;
    }

    pub fn slice(s: *const Stack) []const u64 {
        return s.items[0..s.len];
    }
};

test "going back returns the steps in reverse" {
    var s: Stack = .{};
    const alive = [_]u64{ 1, 2, 3 };
    s.push(1);
    s.push(2);
    s.push(3);
    try std.testing.expectEqual(@as(?u64, 3), s.pop(&alive, 0));
    try std.testing.expectEqual(@as(?u64, 2), s.pop(&alive, 0));
    try std.testing.expectEqual(@as(?u64, 1), s.pop(&alive, 0));
    try std.testing.expectEqual(@as(?u64, null), s.pop(&alive, 0));
}

test "nothing and a repeated step are not remembered" {
    var s: Stack = .{};
    s.push(0);
    try std.testing.expectEqual(@as(usize, 0), s.len);
    s.push(7);
    s.push(7);
    try std.testing.expectEqualSlices(u64, &.{7}, s.slice());
}

test "a step whose control is gone is skipped, and so is the one focused now" {
    var s: Stack = .{};
    s.push(1);
    s.push(2); // its page closed
    s.push(3); // focused already
    const alive = [_]u64{ 1, 3 };
    try std.testing.expectEqual(@as(?u64, 1), s.pop(&alive, 3));
    try std.testing.expectEqual(@as(usize, 0), s.len);
}

test "only gone steps leave nothing to go back to" {
    var s: Stack = .{};
    s.push(4);
    s.push(5);
    try std.testing.expectEqual(@as(?u64, null), s.pop(&.{}, 0));
    try std.testing.expectEqual(@as(usize, 0), s.len);
}

test "a full stack drops its oldest step" {
    var s: Stack = .{};
    for (1..Stack.capacity + 3) |i| s.push(i);
    try std.testing.expectEqual(@as(usize, Stack.capacity), s.len);
    try std.testing.expectEqual(@as(u64, 3), s.slice()[0]); // 1 and 2 dropped
    try std.testing.expectEqual(@as(u64, Stack.capacity + 2), s.slice()[Stack.capacity - 1]);
}

test "clearing forgets every step" {
    var s: Stack = .{};
    s.push(1);
    s.push(2);
    s.clear();
    try std.testing.expectEqual(@as(?u64, null), s.pop(&.{ 1, 2 }, 0));
}
