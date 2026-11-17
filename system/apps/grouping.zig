//! Turns a flat list of processes into the groups a person thinks in: an app
//! (Firefox and every helper it started), background services, and the
//! kernel's own threads.
//!
//! One rule decides, with no app named in it: a process that a launcher entry
//! names, when its parent isn't that same app, starts an app of its own, and
//! everything it starts belongs to it, wherever it runs. So an app opened
//! from a launcher that gives it no unit of its own (vicinae, rofi, a file
//! manager, a script) is that app, not its launcher's; one started from a
//! terminal is its own app, while the terminal keeps its shells and tools;
//! and a browser's helpers, which run the browser's own program, stay with it.
//!
//! What no app has started goes by its systemd unit: an app's scope whose
//! processes no entry names (a Flatpak's bwrap, an Electron wrapper script)
//! is found by the id in the scope's name; a service or a container makes a
//! background group named after it. Processes in a unit that holds a whole
//! session (a login session, the user's service manager) or in none fall back
//! to the process tree, where session scaffolding (init, the compositor, the
//! display manager) never swallows what it launched.
const std = @import("std");
const core = @import("zmon-core");
const Proc = core.Proc;

pub const Kind = enum { app, background, kernel };

pub const Group = struct {
    kind: Kind,
    /// The process the group hangs from; the kernel group has none (0).
    root: i32,
    name: []const u8,
    icon: []const u8 = "",
    /// Indexes into the sample's processes, the root first.
    members: []const u32,
    cpu: f32 = 0,
    memory: u64 = 0,
    threads: u32 = 0,
    disk_bps: f32 = 0,
};

/// Processes that start others without being what a person runs, by the
/// kernel's 15-character name.
fn scaffolding(p: *const Proc) bool {
    if (p.pid <= 2) return true;
    const names = [_][]const u8{
        "systemd",     "init",            "niri",            "sway",            "Hyprland", "river",    "labwc",
        "gnome-shell", "plasmashell",     "kwin_wayland",    "kwin_x11",        "Xorg",     "Xwayland", "sddm",
        "sddm-helper", "gdm",             "gdm-session-wor", "gdm-wayland-ses", "lightdm",  "login",    "dbus-daemon",
        "dbus-broker", "dbus-broker-lau", "sshd",            "cron",            "crond",    "agetty",   "greetd",
        "ly",
    };
    for (names) |n| if (std.mem.eql(u8, p.comm, n)) return true;
    return false;
}

/// What a unit says about the processes in it.
pub const Unit = union(enum) {
    /// No unit, or one that holds a whole session: group by the process tree.
    none,
    /// An app the desktop started, by its id ("com.anthropic.Claude"): look
    /// it up among the launcher entries.
    app: []const u8,
    /// A service or other scope, by its name ("docker", "pipewire").
    service: []const u8,
};

/// Reads a unit's name the way systemd's desktop conventions write it:
/// "app-<launcher>-<id>-<random>.scope", "app-<launcher>-<id>@<random>.service",
/// and D-Bus activation's "dbus-:1.1-<id>@0.service".
pub fn classify(unit: []const u8) Unit {
    const stem = std.mem.cutSuffix(u8, unit, ".scope") orelse std.mem.cutSuffix(u8, unit, ".service") orelse return .none;
    if (std.mem.eql(u8, unit, "init.scope") or std.mem.startsWith(u8, unit, "session-") or std.mem.startsWith(u8, unit, "user@")) return .none;
    if (std.mem.cutPrefix(u8, stem, "app-")) |rest| return .{ .app = appId(rest) };
    if (std.mem.cutPrefix(u8, stem, "dbus-")) |rest| {
        // "dbus-:1.1-org.telegram.desktop@0": the bus name, then the id.
        if (std.mem.indexOfScalar(u8, rest, '-')) |dash| return .{ .app = appId(rest[dash + 1 ..]) };
    }
    var name = if (std.mem.indexOfScalar(u8, stem, '@')) |at| stem[0..at] else stem;
    // "tmux-spawn-<uuid>": one unit per run, all one kind of thing.
    if (name.len > 37 and name[name.len - 37] == '-' and isUuid(name[name.len - 36 ..])) name = name[0 .. name.len - 37];
    return if (name.len > 0) .{ .service = name } else .none;
}

fn isUuid(s: []const u8) bool {
    if (s.len != 36) return false;
    for (s, 0..) |ch, i| {
        if (i == 8 or i == 13 or i == 18 or i == 23) {
            if (ch != '-') return false;
        } else if (!std.ascii.isHex(ch)) return false;
    }
    return true;
}

/// The id in an app unit's name, once its launcher and random suffix are off.
fn appId(rest: []const u8) []const u8 {
    var s = rest;
    if (std.mem.indexOfScalar(u8, s, '@')) |at| s = s[0..at];
    // A trailing "-<number>" (or hex) makes the name unique; it isn't the id.
    if (std.mem.lastIndexOfScalar(u8, s, '-')) |dash| {
        const tail = s[dash + 1 ..];
        if (tail.len > 0 and allHex(tail)) s = s[0..dash];
    }
    // "niri-ghostty": a launcher's name before the id. Ids with dots
    // ("com.anthropic.Claude") never start with one; ids escape their own
    // dashes, so a dash left here separates the launcher.
    if (std.mem.indexOfScalar(u8, s, '-')) |dash| {
        if (std.mem.indexOfScalar(u8, s[0..dash], '.') == null) s = s[dash + 1 ..];
    }
    return s;
}

fn allHex(s: []const u8) bool {
    for (s) |ch| if (!std.ascii.isHex(ch)) return false;
    return true;
}

/// A service's name as a person reads it: a container's scope by its kind
/// and short id, any other by its name.
fn serviceName(a: std.mem.Allocator, name: []const u8) []const u8 {
    for ([_][2][]const u8{ .{ "docker-", "Docker container" }, .{ "libpod-", "Podman container" } }) |kind| {
        if (std.mem.cutPrefix(u8, name, kind[0])) |id| if (id.len >= 12 and allHex(id)) {
            return std.fmt.allocPrint(a, "{s} {s}", .{ kind[1], id[0..12] }) catch name;
        };
    }
    return name;
}

/// Builds the groups for one sample: apps first (busiest first), then
/// background processes, then the kernel's threads. Everything is allocated
/// from `a`.
/// `windows`: which process owns which window, when the compositor says.
pub fn build(a: std.mem.Allocator, procs: []const Proc, index: anytype, windows: []const core.Window) ![]Group {
    var at = std.AutoHashMapUnmanaged(i32, u32).empty;
    try at.ensureTotalCapacity(a, @intCast(procs.len));
    for (procs, 0..) |p, i| at.putAssumeCapacity(p.pid, @intCast(i));

    const none = std.math.maxInt(u32);
    // The launcher entry each process is, by its executable, its command
    // line's program or its name (null: none a person launches).
    const Entry = @TypeOf(index.lookup("").?);
    const entry_of = try a.alloc(?Entry, procs.len);
    for (procs, 0..) |*p, i| entry_of[i] = if (p.kthread) null else visibleEntry(index, p);
    // A process whose program names no app may own a window that does: an
    // Electron or Java app started through a script runs as "electron", its
    // window says "equibop". The window's app id is the entry's file name or
    // its window class.
    for (windows) |w| {
        const i = at.get(w.pid) orelse continue;
        if (entry_of[i] != null) continue;
        const id = w.app_id.slice();
        const e = index.lookupId(id) orelse index.lookup(id) orelse continue;
        if (!e.hidden and !e.terminal) entry_of[i] = e;
    }
    // An app's root names an entry its parent doesn't; each process belongs
    // to the nearest root among itself and its ancestors.
    const app_of = try a.alloc(u32, procs.len);
    for (procs, 0..) |_, i| {
        var cur: u32 = @intCast(i);
        var hops: u32 = 0;
        app_of[i] = while (hops < 64) : (hops += 1) {
            if (procs[cur].kthread) break none;
            const parent = at.get(procs[cur].ppid);
            if (entry_of[cur]) |e| {
                const same = if (parent) |pi| entry_of[pi] == e else false;
                if (!same) break cur;
            }
            cur = parent orelse break none;
        } else none;
    }

    // A unit the compositor or init runs in holds the whole session, not one
    // app: what it started is grouped by the process tree instead.
    var broad = std.StringHashMapUnmanaged(void).empty;
    for (procs) |*p| if (scaffolding(p) and p.unit.len > 0) try broad.put(a, p.unit, {});

    // A process in an app's or a service's unit belongs to its unit's group,
    // keyed by the first of its processes met. Units of one kind with
    // different runs ("tmux-spawn-<uuid>") share a group.
    const group_of = try a.alloc(u32, procs.len);
    const by_unit_mode = try a.alloc(bool, procs.len);
    var by_unit = std.StringHashMapUnmanaged(u32).empty;
    // An app's scope belongs to that app: a process in it that the app's
    // tree doesn't reach (it detached) joins the app rather than make a
    // second group under the same name.
    for (procs, 0..) |p, i| {
        if (app_of[i] != i) continue;
        switch (classify(p.unit)) {
            .app => if (!broad.contains(p.unit)) {
                const slot = try by_unit.getOrPut(a, p.unit);
                if (!slot.found_existing) slot.value_ptr.* = @intCast(i);
            },
            else => {},
        }
    }
    for (procs, 0..) |p, i| {
        by_unit_mode[i] = false;
        group_of[i] = none;
        if (app_of[i] != none) {
            // An app's, whatever unit it runs in.
            group_of[i] = app_of[i];
            by_unit_mode[i] = true;
            continue;
        }
        if (p.kthread or broad.contains(p.unit)) continue;
        const key = switch (classify(p.unit)) {
            .none => continue,
            .app => p.unit,
            .service => |name| name,
        };
        const slot = try by_unit.getOrPut(a, key);
        if (!slot.found_existing) slot.value_ptr.* = @intCast(i);
        group_of[i] = slot.value_ptr.*;
        by_unit_mode[i] = true;
    }
    // The rest by the process tree: the highest ancestor not behind
    // scaffolding, or the app or service an ancestor belongs to by its unit
    // (a browser's helpers started before it was moved into its own scope).
    for (procs, 0..) |p, i| {
        if (p.kthread or by_unit_mode[i]) continue;
        var cur: u32 = @intCast(i);
        var hops: u32 = 0;
        group_of[i] = while (hops < 64) : (hops += 1) {
            const parent = at.get(procs[cur].ppid) orelse break cur;
            if (procs[parent].kthread or scaffolding(&procs[parent])) break cur;
            if (by_unit_mode[parent]) break group_of[parent];
            cur = parent;
        } else cur;
    }

    var by_key = std.AutoArrayHashMapUnmanaged(u32, std.ArrayList(u32)).empty;
    var kernel: std.ArrayList(u32) = .empty;
    for (procs, 0..) |_, i| {
        if (group_of[i] == none) {
            try kernel.append(a, @intCast(i));
            continue;
        }
        const slot = try by_key.getOrPut(a, group_of[i]);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.append(a, @intCast(i));
    }

    var groups: std.ArrayList(Group) = .empty;
    var it = by_key.iterator();
    while (it.next()) |kv| {
        const members = kv.value_ptr.items;
        // The root leads: the process whose parent is outside the group,
        // the earliest started if there are several.
        var lead: usize = 0;
        for (members, 0..) |m, pos| {
            const outside = if (at.get(procs[m].ppid)) |pi| std.mem.indexOfScalar(u32, members, pi) == null else true;
            const lead_outside = if (at.get(procs[members[lead]].ppid)) |pi| std.mem.indexOfScalar(u32, members, pi) == null else true;
            if ((outside and !lead_outside) or (outside == lead_outside and procs[m].start < procs[members[lead]].start)) lead = pos;
        }
        std.mem.swap(u32, &members[0], &members[lead]);
        const root = &procs[members[0]];
        const unit = classify(root.unit);
        // A scope's name carries the app's desktop file id, by the systemd
        // convention: only an entry's own file name answers to it.
        const by_id = switch (unit) {
            .app => |id| index.lookupId(id),
            else => null,
        };
        // An app's root names its own entry; a unit's group, the id in the
        // unit's name; a service, none (it is named after its unit).
        const own = if (app_of[members[0]] == members[0]) entry_of[members[0]] else null;
        const entry = own orelse by_id orelse if (unit == .service) null else index.lookup(std.fs.path.basename(root.exe)) orelse index.lookup(root.name);
        const is_app = if (entry) |e| !e.hidden else false;
        var g: Group = .{
            .kind = if (is_app) .app else .background,
            .root = root.pid,
            .name = if (is_app) entry.?.name else switch (unit) {
                .service => |name| serviceName(a, name),
                else => root.name,
            },
            .icon = if (entry) |e| e.icon else "",
            .members = members,
        };
        totals(&g, procs);
        try groups.append(a, g);
    }
    if (kernel.items.len > 0) {
        var g: Group = .{ .kind = .kernel, .root = 0, .name = "Kernel threads", .members = kernel.items };
        totals(&g, procs);
        try groups.append(a, g);
    }
    std.mem.sort(Group, groups.items, {}, order);
    return groups.items;
}

/// The launcher entry a process is: one a person launches (not hidden),
/// with a window of its own (not run in a terminal), matched by the program
/// it runs, which the entry's Exec names. Its window class doesn't count: a
/// class names windows, and another program may share the word.
fn visibleEntry(index: anytype, p: *const Proc) @TypeOf(index.lookup("")) {
    const tries = [_][]const u8{ std.fs.path.basename(p.exe), p.program, p.name };
    for (tries) |key| {
        if (key.len == 0) continue;
        if (index.lookupProgram(key)) |e| if (!e.hidden and !e.terminal) return e;
    }
    return null;
}

fn totals(g: *Group, procs: []const Proc) void {
    for (g.members) |i| {
        g.cpu += procs[i].cpu;
        g.memory += procs[i].memory;
        g.threads += procs[i].threads;
        g.disk_bps += procs[i].disk_bps;
    }
}

fn order(_: void, x: Group, y: Group) bool {
    if (x.kind != y.kind) return @backingInt(x.kind) < @backingInt(y.kind);
    if (x.cpu != y.cpu) return x.cpu > y.cpu;
    return x.memory > y.memory;
}

const Index = @import("root.zig").Index;

fn fake(pid: i32, ppid: i32, name: []const u8, exe: []const u8) Proc {
    return .{ .pid = pid, .ppid = ppid, .name = name, .comm = name[0..@min(name.len, 15)], .exe = exe };
}

test "scaffolding is recognised by the kernel's short name, even when the full name is known" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const procs = [_]Proc{
        fake(1, 0, "systemd", "/usr/lib/systemd/systemd"),
        fake(50, 1, "dbus-broker-launch", "/usr/bin/dbus-broker-launch"),
        fake(60, 50, "dbus-broker", "/usr/bin/dbus-broker"),
    };
    const groups = try build(arena.allocator(), &procs, &ix, &.{});
    var broker: ?Group = null;
    for (groups) |g| if (g.root == 60) {
        broker = g;
    };
    try std.testing.expect(broker != null); // dbus-broker leads a group of its own
    try std.testing.expectEqual(@as(usize, 1), broker.?.members.len);
}

test "an app keeps its helpers; scaffolding does not swallow its apps" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("browser", "[Desktop Entry]\nType=Application\nName=Web Browser\nExec=browser %u\n");
    ix.add("term", "[Desktop Entry]\nType=Application\nName=Terminal\nExec=term\n");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var procs = [_]Proc{
        fake(1, 0, "systemd", "/usr/lib/systemd/systemd"),
        fake(2, 0, "kthreadd", ""),
        fake(3, 2, "rcu_gp", ""),
        fake(10, 1, "niri", "/usr/bin/niri"),
        fake(20, 10, "browser", "/usr/bin/browser"),
        fake(21, 20, "browser", "/usr/bin/browser"),
        fake(22, 21, "browser-helper", "/usr/bin/browser"),
        fake(30, 10, "term", "/usr/bin/term"),
        fake(31, 30, "bash", "/usr/bin/bash"),
        fake(40, 1, "pipewire", "/usr/bin/pipewire"),
    };
    procs[2].kthread = true;
    procs[1].kthread = true;
    procs[4].cpu = 30;
    procs[5].cpu = 20;
    procs[7].cpu = 1;
    const groups = try build(arena.allocator(), &procs, &ix, &.{});

    var browser: ?Group = null;
    var terminal: ?Group = null;
    var kernel: ?Group = null;
    var background: usize = 0;
    for (groups) |g| {
        if (std.mem.eql(u8, g.name, "Web Browser")) browser = g;
        if (std.mem.eql(u8, g.name, "Terminal")) terminal = g;
        if (g.kind == .kernel) kernel = g;
        if (g.kind == .background) background += 1;
    }
    try std.testing.expectEqual(@as(usize, 3), browser.?.members.len); // the three browser processes
    try std.testing.expectEqual(@as(i32, 20), procs[browser.?.members[0]].pid); // the root leads
    try std.testing.expectEqual(@as(f32, 50), browser.?.cpu);
    try std.testing.expectEqual(@as(usize, 2), terminal.?.members.len); // term and its shell
    try std.testing.expectEqual(@as(usize, 2), kernel.?.members.len);
    try std.testing.expect(background >= 2); // systemd, niri, pipewire are groups of their own
    // apps sort before background processes, the busiest first
    try std.testing.expectEqualStrings("Web Browser", groups[0].name);
    try std.testing.expectEqualStrings("Terminal", groups[1].name);
    try std.testing.expect(groups[groups.len - 1].kind == .kernel);
}

test "entries that are not meant to be launched make background groups, not apps" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("portal", "[Desktop Entry]\nType=Application\nName=Portal\nExec=portal-bin\nNoDisplay=true\n");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const procs = [_]Proc{ fake(1, 0, "systemd", ""), fake(5, 1, "portal-bin", "/usr/lib/portal-bin") };
    const groups = try build(arena.allocator(), &procs, &ix, &.{});
    for (groups) |g| try std.testing.expect(g.kind != .app);
}

test "a process the kernel starts leads its own group, not the kernel thread's" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var procs = [_]Proc{
        fake(1, 0, "systemd", "/usr/lib/systemd/systemd"),
        fake(2, 0, "kthreadd", ""),
        fake(30, 2, "kworker/u16:2", ""),
        fake(31, 30, "modprobe", "/usr/bin/modprobe"),
    };
    procs[1].kthread = true;
    procs[2].kthread = true;
    const groups = try build(arena.allocator(), &procs, &ix, &.{});
    for (groups) |g| {
        if (g.kind == .kernel) continue;
        try std.testing.expect(std.mem.indexOfScalar(u32, g.members, @intCast(for (procs, 0..) |p, i| {
            if (p.pid == g.root) break i;
        } else 0)) != null); // every group's root is one of its members
        try std.testing.expect(!std.mem.startsWith(u8, g.name, "kworker"));
    }
}

test "a unit's name says whether it holds an app, a service or a whole session" {
    const T = struct {
        fn app(unit: []const u8) []const u8 {
            return switch (classify(unit)) {
                .app => |id| id,
                else => "-",
            };
        }
        fn service(unit: []const u8) []const u8 {
            return switch (classify(unit)) {
                .service => |n| n,
                else => "-",
            };
        }
    };
    try std.testing.expectEqualStrings("com.anthropic.Claude", T.app("app-com.anthropic.Claude-1926.scope"));
    try std.testing.expectEqualStrings("ghostty", T.app("app-niri-ghostty-2505106.scope"));
    try std.testing.expectEqualStrings("org.gnome.Nautilus", T.app("app-gnome-org.gnome.Nautilus-4242.scope"));
    try std.testing.expectEqualStrings("org.mozilla.firefox", T.app("app-flatpak-org.mozilla.firefox-12345.scope"));
    try std.testing.expectEqualStrings("org.gnome.Calculator", T.app("app-gnome-org.gnome.Calculator@3f2a9c.service"));
    try std.testing.expectEqualStrings("org.telegram.desktop", T.app("dbus-:1.1-org.telegram.desktop@0.service"));
    try std.testing.expectEqualStrings("docker", T.service("docker.service"));
    try std.testing.expectEqualStrings("getty", T.service("getty@tty1.service"));
    try std.testing.expectEqualStrings("tmux-spawn", T.service("tmux-spawn-4772f86e-775f-4b0d-8753-b89049bc7b3d.scope"));
    try std.testing.expect(classify("session-2.scope") == .none);
    try std.testing.expect(classify("user@1001.service") == .none);
    try std.testing.expect(classify("init.scope") == .none);
    try std.testing.expect(classify("") == .none);
}

test "processes are grouped by their unit, whatever started them" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("com.example.Editor", "[Desktop Entry]\nType=Application\nName=Editor\nExec=/opt/editor/run.sh\nIcon=editor\n");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var procs = [_]Proc{
        fake(1, 0, "systemd", "/usr/lib/systemd/systemd"),
        fake(900, 1, "systemd", "/usr/lib/systemd/systemd"),
        // An app behind a wrapper (bwrap, a script): no name matches, the unit does.
        fake(1000, 900, "bwrap", "/usr/bin/bwrap"),
        fake(1001, 1000, "electron", "/opt/editor/electron"),
        fake(1002, 1001, "MainThread", ""),
        fake(2000, 1, "dockerd", "/usr/bin/dockerd"),
        fake(2001, 2000, "containerd", "/usr/bin/containerd"),
        fake(3000, 1, "node", ""),
    };
    for (procs[2..5]) |*p| p.unit = "app-flatpak-com.example.Editor-1000.scope";
    for (procs[5..7]) |*p| p.unit = "docker.service";
    procs[1].unit = "user@1000.service";
    procs[7].unit = "docker-0123456789abcdef0123456789abcdef.scope";
    for (&procs, 0..) |*p, i| p.start = i;
    const groups = try build(arena.allocator(), &procs, &ix, &.{});
    var editor: ?Group = null;
    var docker: ?Group = null;
    var container: ?Group = null;
    for (groups) |g| {
        if (std.mem.eql(u8, g.name, "Editor")) editor = g;
        if (std.mem.eql(u8, g.name, "docker")) docker = g;
        if (std.mem.startsWith(u8, g.name, "Docker container 0123456789ab")) container = g;
    }
    try std.testing.expectEqual(Kind.app, editor.?.kind);
    try std.testing.expectEqual(@as(usize, 3), editor.?.members.len);
    try std.testing.expectEqual(@as(i32, 1000), editor.?.root); // the first in the scope leads
    try std.testing.expectEqualStrings("editor", editor.?.icon);
    try std.testing.expectEqual(Kind.background, docker.?.kind);
    try std.testing.expectEqual(@as(usize, 2), docker.?.members.len);
    try std.testing.expect(container != null);
}

test "helpers left in the compositor's unit join the app their parent is in" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("browser", "[Desktop Entry]\nType=Application\nName=Browser\nExec=browser %u\n");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var procs = [_]Proc{
        fake(1, 0, "systemd", "/usr/lib/systemd/systemd"),
        fake(10, 1, "niri", "/usr/bin/niri"),
        fake(20, 10, "browser", "/usr/bin/browser"),
        fake(21, 20, "browser", "/usr/bin/browser"),
        fake(22, 21, "browser", "/usr/bin/browser"),
        fake(30, 10, "swaybg", "/usr/bin/swaybg"),
        fake(40, 1, "tmux", "/usr/bin/tmux"),
        fake(41, 40, "zsh", "/usr/bin/zsh"),
        fake(42, 40, "zsh", "/usr/bin/zsh"),
    };
    procs[1].unit = "niri.service";
    procs[2].unit = "app-org.chromium.Chromium-20.scope"; // moved into a scope after starting helpers
    procs[3].unit = "niri.service";
    procs[4].unit = "niri.service";
    procs[5].unit = "niri.service";
    procs[7].unit = "tmux-spawn-4772f86e-775f-4b0d-8753-b89049bc7b3d.scope";
    procs[8].unit = "tmux-spawn-565179ff-e1ff-4229-a7d4-239bb8cfe67f.scope";
    const groups = try build(arena.allocator(), &procs, &ix, &.{});
    for (groups) |g| {
        if (std.mem.eql(u8, g.name, "Browser")) try std.testing.expectEqual(@as(usize, 3), g.members.len);
        if (std.mem.eql(u8, g.name, "tmux-spawn")) try std.testing.expectEqual(@as(usize, 2), g.members.len);
        if (std.mem.eql(u8, g.name, "swaybg")) try std.testing.expectEqual(@as(usize, 1), g.members.len);
    }
}

test "an app started by a launcher, a terminal or a script is its own app, not theirs" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("launcher", "[Desktop Entry]\nType=Application\nName=Launcher\nExec=launcher-server\n");
    ix.add("com.example.Notes", "[Desktop Entry]\nType=Application\nName=Notes\nExec=notes\n");
    ix.add("term", "[Desktop Entry]\nType=Application\nName=Terminal\nExec=term\n");
    ix.add("browser", "[Desktop Entry]\nType=Application\nName=Browser\nExec=browser %u\n");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var procs = [_]Proc{
        fake(1, 0, "systemd", "/usr/lib/systemd/systemd"),
        fake(900, 1, "systemd", "/usr/lib/systemd/systemd"),
        // A launcher run as a service, with a helper of its own and an app it opened.
        fake(1000, 900, "launcher-server", "/usr/bin/launcher-server"),
        fake(1001, 1000, "launcher-index", "/usr/libexec/launcher-index"),
        fake(1002, 1000, "notes", "/usr/bin/notes"),
        fake(1003, 1002, "notes", "/usr/bin/notes"), // its own helper
        // A terminal in its own scope: a shell and an editor stay with it, a GUI app doesn't.
        fake(2000, 900, "term", "/usr/bin/term"),
        fake(2001, 2000, "zsh", "/usr/bin/zsh"),
        fake(2002, 2001, "vim", "/usr/bin/vim"),
        fake(2003, 2001, "browser", "/usr/bin/browser"),
        fake(2004, 2003, "browser", "/usr/bin/browser"),
        // Another user's app: no executable to read, only its command line's program.
        fake(3000, 900, "MainThread", ""),
    };
    for (procs[2..6]) |*p| p.unit = "launcher.service";
    for (procs[6..11]) |*p| p.unit = "app-term-2000.scope";
    procs[11].program = "notes";
    procs[11].unit = "app-flatpak-com.example.Notes-3000.scope";
    for (&procs, 0..) |*p, i| p.start = i;
    const groups = try build(arena.allocator(), &procs, &ix, &.{});
    const Want = struct { name: []const u8, root: i32, count: usize };
    const want = [_]Want{
        .{ .name = "Launcher", .root = 1000, .count = 2 }, // itself and its index, not Notes
        .{ .name = "Notes", .root = 1002, .count = 2 },
        .{ .name = "Terminal", .root = 2000, .count = 3 }, // term, zsh, vim
        .{ .name = "Browser", .root = 2003, .count = 2 }, // started from the shell: its own app
        .{ .name = "Notes", .root = 3000, .count = 1 }, // another user's, by its program
    };
    for (want) |w| {
        const g = for (groups) |g| {
            if (g.root == w.root) break g;
        } else return error.GroupMissing;
        try std.testing.expectEqualStrings(w.name, g.name);
        try std.testing.expectEqual(Kind.app, g.kind);
        try std.testing.expectEqual(w.count, g.members.len);
    }
}

test "a terminal program is never an app of its own, and a window class doesn't name a process" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("term", "[Desktop Entry]\nType=Application\nName=Terminal\nExec=term\n");
    ix.add("nvim", "[Desktop Entry]\nType=Application\nName=Neovim\nExec=nvim %F\nTerminal=true\n");
    ix.add("com.example.Chat", "[Desktop Entry]\nType=Application\nName=Chat\nExec=chat-desktop\nStartupWMClass=chat\n");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var procs = [_]Proc{
        fake(1, 0, "systemd", "/usr/lib/systemd/systemd"),
        fake(10, 1, "term", "/usr/bin/term"),
        fake(11, 10, "zsh", "/usr/bin/zsh"),
        fake(12, 11, "nvim", "/usr/bin/nvim"), // Terminal=true: stays with the terminal
        fake(13, 11, "chat", "/home/u/.local/bin/chat"), // a CLI that shares the chat app's window class
    };
    for (&procs, 0..) |*p, i| p.start = i;
    const groups = try build(arena.allocator(), &procs, &ix, &.{});
    for (groups) |g| {
        try std.testing.expect(!std.mem.eql(u8, g.name, "Neovim"));
        try std.testing.expect(!std.mem.eql(u8, g.name, "Chat"));
        if (std.mem.eql(u8, g.name, "Terminal")) try std.testing.expectEqual(@as(usize, 4), g.members.len);
    }
}

test "a process that left its app's tree but stayed in its scope joins the app" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("com.example.Chat", "[Desktop Entry]\nType=Application\nName=Chat\nExec=chat-desktop\n");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var procs = [_]Proc{
        fake(1, 0, "systemd", "/usr/lib/systemd/systemd"),
        fake(100, 1, "chat-desktop", "/usr/bin/chat-desktop"),
        fake(200, 1, "adb", "/usr/bin/adb"), // a daemon it started, which detached
    };
    procs[1].unit = "app-com.example.Chat-100.scope";
    procs[2].unit = "app-com.example.Chat-100.scope";
    for (&procs, 0..) |*p, i| p.start = i;
    const groups = try build(arena.allocator(), &procs, &ix, &.{});
    var chats: usize = 0;
    for (groups) |g| if (std.mem.eql(u8, g.name, "Chat")) {
        chats += 1;
        try std.testing.expectEqual(@as(usize, 2), g.members.len);
    };
    try std.testing.expectEqual(@as(usize, 1), chats);
}

test "a scope's id names an app only when it is a launcher entry's file name" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("viewer", "[Desktop Entry]\nType=Application\nName=Viewer\nExec=/bin/sh -c viewer\n");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var procs = [_]Proc{
        fake(1, 0, "systemd", "/usr/lib/systemd/systemd"),
        // A script a compositor ran through sh: its scope says "sh", which is no app.
        fake(500, 1, "bash", "/usr/bin/bash"),
    };
    procs[1].unit = "app-niri-sh-500.scope";
    const groups = try build(arena.allocator(), &procs, &ix, &.{});
    for (groups) |g| try std.testing.expect(g.kind != .app);
}

test "a process its program doesn't name is the app its window names" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("equibop", "[Desktop Entry]\nType=Application\nName=Equibop\nExec=equibop %U\nStartupWMClass=equibop\n");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var procs = [_]Proc{
        fake(1, 0, "systemd", "/usr/lib/systemd/systemd"),
        fake(900, 1, "launcher", "/usr/bin/launcher"),
        // The script exec'd Electron: nothing in the process says "equibop".
        fake(1000, 900, "electron", "/usr/lib/electron40/electron"),
        fake(1001, 1000, "electron", "/usr/lib/electron40/electron"),
        fake(1002, 1001, "electron", "/usr/lib/electron40/electron"),
    };
    procs[1].unit = "launcher.service";
    procs[2].unit = "app-org.chromium.Chromium-1000.scope";
    procs[3].unit = "launcher.service";
    procs[4].unit = "launcher.service";
    for (&procs, 0..) |*p, i| p.start = i;
    const windows = [_]core.Window{.{ .pid = 1000, .app_id = .init("equibop") }};
    const groups = try build(arena.allocator(), &procs, &ix, &windows);
    const g = for (groups) |g| {
        if (g.root == 1000) break g;
    } else return error.GroupMissing;
    try std.testing.expectEqual(Kind.app, g.kind);
    try std.testing.expectEqualStrings("Equibop", g.name);
    try std.testing.expectEqual(@as(usize, 3), g.members.len); // its helpers in the launcher's unit too
}
