//! zmon's motion, one vocabulary for anything that moves: a few named
//! transitions and two ways to use them. `value` eases a number (a width, an
//! offset) toward its target; `reveal` says how far a panel is open, so it
//! can slide in and out and stop being drawn once shut.
//!
//! Each moving thing is named by a key unique in the window ("sidebar",
//! "details"), not by where it is drawn, so it keeps its place when the
//! layout around it changes. A target that changes midway is taken from
//! where the value is, keeping its speed. Under Reduce motion every value is
//! its target at once. A frame is drawn only while something moves.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const m = ui.motion;

pub const Transition = m.Transition;

/// A panel opening or closing (the sidebar, the details pane): a critically
/// damped spring, settled in about a third of a second, with no bounce.
pub const panel: Transition = .{ .spring = .{ .stiffness = 400, .damping = 40 } };
/// Something small changing (a fade, a highlight).
pub const quick: Transition = .{ .tween = .{ .duration = 0.15, .ease = .ease_out } };

/// `key`'s value this frame, moving toward `target` by `tr`. The first time
/// it is asked for it is `target`, so nothing moves when the window opens.
pub fn value(c: *ui.Context, key: []const u8, target: f32, tr: Transition) f32 {
    const got = c.motion_store.get(c.gpa, idOf(key), c.frame) orelse return target;
    const ch = &got.state.ch[0];
    if (got.fresh) ch.* = .at(target);
    ch.retarget(target, if (c.reduced_motion or c.reduce_motion) .instant else tr, 0, c.time);
    ch.sample(c.time);
    if (ch.moving) c.animationFrame();
    return @floatCast(ch.value);
}

/// How far the panel `key` is open, from 0 to 1, heading for `open`; null
/// once it is shut and still, when it isn't drawn at all. Ask every frame,
/// open or not, or a panel shut while unasked would slide shut later.
pub fn reveal(c: *ui.Context, key: []const u8, open: bool) ?f32 {
    const p = std.math.clamp(value(c, key, if (open) 1 else 0, panel), 0, 1);
    if (!open and p < 0.002) return null;
    return p;
}

/// The step a stepped motion is at, one every `every` seconds by the view's
/// clock, asking for a frame at the next step while it is asked for: a few
/// frames a second, not one every refresh. Under Reduce motion it stays at 0
/// and asks for none.
pub fn step(c: *ui.Context, every: f64) u64 {
    if (c.reduced_motion or c.reduce_motion) return 0;
    const at = @max(0, c.time) / every;
    const n: u64 = @intFromFloat(@floor(at));
    c.frameIn(@floatCast((@as(f64, @floatFromInt(n + 1)) - at) * every));
    return n;
}

/// `key` placed at `target` at once, as when the thing it moves has gone.
pub fn jump(c: *ui.Context, key: []const u8, target: f32) void {
    const got = c.motion_store.get(c.gpa, idOf(key), c.frame) orelse return;
    got.state.ch[0] = .at(target);
}

fn idOf(key: []const u8) u64 {
    return std.hash.Wyhash.hash(0x7a6d6f6e_6d6f7469, key);
}

/// How far between `from` and `to` a value is, 0 to 1: a panel's width
/// read back as how open it is.
pub fn progress(v: f32, from: f32, to: f32) f32 {
    if (from == to) return 1;
    return std.math.clamp((v - from) / (to - from), 0, 1);
}

test "progress reads a value back as a fraction of its way" {
    try std.testing.expectEqual(@as(f32, 0), progress(76, 76, 236));
    try std.testing.expectEqual(@as(f32, 1), progress(236, 76, 236));
    try std.testing.expectEqual(@as(f32, 0.5), progress(156, 76, 236));
    try std.testing.expectEqual(@as(f32, 1), progress(300, 76, 236));
}
