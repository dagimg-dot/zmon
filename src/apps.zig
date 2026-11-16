//! Turns a flat list of processes into the groups a person thinks in: an app
//! (Firefox and every helper it started), background services, and the
//! kernel's own threads.
//!
//! Without asking a compositor which processes own windows, an "app" is a
//! process that a launcher entry (.desktop file) names; what it starts is
//! grouped under it. Session scaffolding (init, the compositor, the display
//! manager) never swallows the apps it launched, so each app stays its own
//! group.
const std = @import("std");
const sampler = @import("sampler.zig");
const procfs = @import("procfs.zig");
const Proc = sampler.Proc;

pub const Entry = struct {
    name: []const u8,
    icon: []const u8 = "",
    /// The name of the program the entry runs (the first word of Exec).
    program: []const u8 = "",
    wm_class: []const u8 = "",
    id: []const u8 = "",
    /// NoDisplay: it runs a program but isn't something a person launches.
    hidden: bool = false,
};

/// The launcher entries installed on this machine.
pub const Index = struct {
    arena: std.heap.ArenaAllocator,
    entries: std.ArrayList(Entry) = .empty,
    by_key: std.StringHashMapUnmanaged(u32) = .empty,

    pub fn init(gpa: std.mem.Allocator) Index {
        return .{ .arena = .init(gpa) };
    }

    pub fn deinit(ix: *Index) void {
        ix.arena.deinit();
    }

    /// Reads every .desktop file under the standard application directories.
    pub fn load(ix: *Index, io: std.Io, home: []const u8) void {
        const a = ix.arena.allocator();
        const dirs = [_][]const u8{
            "/usr/share/applications",
            "/usr/local/share/applications",
            "/var/lib/flatpak/exports/share/applications",
        };
        for (dirs) |d| ix.loadDir(io, d);
        if (home.len > 0) {
            for ([_][]const u8{ ".local/share/applications", ".local/share/flatpak/exports/share/applications" }) |rel| {
                const path = std.fs.path.join(a, &.{ home, rel }) catch continue;
                ix.loadDir(io, path);
            }
        }
    }

    fn loadDir(ix: *Index, io: std.Io, path: []const u8) void {
        var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return;
        defer dir.close(io);
        var it = dir.iterate();
        var buf: [32768]u8 = undefined;
        while (it.next(io) catch null) |e| {
            if (!std.mem.endsWith(u8, e.name, ".desktop")) continue;
            const text = procfs.read(io, dir, e.name, &buf) catch continue;
            ix.add(e.name[0 .. e.name.len - ".desktop".len], text);
        }
    }

    /// Adds the entry in `text` (the contents of a .desktop file called `id`).
    pub fn add(ix: *Index, id: []const u8, text: []const u8) void {
        const e = parseDesktop(ix.arena.allocator(), id, text) orelse return;
        const at: u32 = @intCast(ix.entries.items.len);
        ix.entries.append(ix.arena.allocator(), e) catch return;
        const a = ix.arena.allocator();
        for ([_][]const u8{ e.program, e.wm_class, e.id }) |key| {
            if (key.len == 0) continue;
            const lower = std.ascii.allocLowerString(a, key) catch continue;
            // The first entry to claim a name keeps it.
            const slot = ix.by_key.getOrPut(a, lower) catch continue;
            if (!slot.found_existing) slot.value_ptr.* = at;
        }
    }

    pub fn lookup(ix: *const Index, key: []const u8) ?*const Entry {
        var buf: [128]u8 = undefined;
        if (key.len == 0 or key.len > buf.len) return null;
        const lower = std.ascii.lowerString(&buf, key);
        const at = ix.by_key.get(lower) orelse return null;
        return &ix.entries.items[at];
    }
};

/// A launcher entry: a name to show and the program it runs.
pub fn parseDesktop(a: std.mem.Allocator, id: []const u8, text: []const u8) ?Entry {
    var in_entry = false;
    var name: []const u8 = "";
    var icon: []const u8 = "";
    var exec: []const u8 = "";
    var wm: []const u8 = "";
    var hidden = false;
    var is_app = true;
    var lines = std.mem.tokenizeAny(u8, text, "\r\n");
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t");
        if (line.len == 0 or line[0] == '#') continue;
        if (line[0] == '[') {
            if (in_entry) break; // only the main group
            in_entry = std.mem.eql(u8, line, "[Desktop Entry]");
            continue;
        }
        if (!in_entry) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = line[0..eq];
        const value = line[eq + 1 ..];
        if (std.mem.eql(u8, key, "Name")) name = value //
        else if (std.mem.eql(u8, key, "Exec")) exec = value //
        else if (std.mem.eql(u8, key, "Icon")) icon = value //
        else if (std.mem.eql(u8, key, "StartupWMClass")) wm = value //
        else if (std.mem.eql(u8, key, "NoDisplay")) hidden = std.mem.eql(u8, value, "true") //
        else if (std.mem.eql(u8, key, "Type")) is_app = std.mem.eql(u8, value, "Application");
    }
    if (!is_app or name.len == 0) return null;
    return .{
        .name = a.dupe(u8, name) catch return null,
        .icon = a.dupe(u8, icon) catch "",
        .program = a.dupe(u8, execProgram(exec)) catch "",
        .wm_class = a.dupe(u8, wm) catch "",
        .id = a.dupe(u8, id) catch "",
        .hidden = hidden,
    };
}

/// The program an Exec line runs: past `env` and VAR=value words, without
/// quotes or directories ("env FOO=1 /opt/x/bin/tool %U" is "tool").
pub fn execProgram(exec: []const u8) []const u8 {
    var it = std.mem.tokenizeScalar(u8, exec, ' ');
    while (it.next()) |word| {
        const w = std.mem.trim(u8, word, "\"'");
        if (std.mem.eql(u8, w, "env")) continue;
        if (std.mem.indexOfScalar(u8, w, '=') != null and w[0] != '/') continue;
        return std.fs.path.basename(w);
    }
    return "";
}

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

/// Processes that start others without being what a person runs.
fn scaffolding(p: *const Proc) bool {
    if (p.pid <= 2) return true;
    const names = [_][]const u8{
        "systemd",     "init",            "niri",            "sway",            "Hyprland", "river",    "labwc",
        "gnome-shell", "plasmashell",     "kwin_wayland",    "kwin_x11",        "Xorg",     "Xwayland", "sddm",
        "sddm-helper", "gdm",             "gdm-session-wor", "gdm-wayland-ses", "lightdm",  "login",    "dbus-daemon",
        "dbus-broker", "dbus-broker-lau", "sshd",            "cron",            "crond",    "agetty",   "greetd",
        "ly",
    };
    for (names) |n| if (std.mem.eql(u8, p.name, n)) return true;
    return false;
}

/// Builds the groups for one sample: apps first (busiest first), then
/// background processes, then the kernel's threads. Everything is allocated
/// from `a`.
pub fn build(a: std.mem.Allocator, procs: []const Proc, index: *const Index) ![]Group {
    var at = std.AutoHashMapUnmanaged(i32, u32).empty;
    try at.ensureTotalCapacity(a, @intCast(procs.len));
    for (procs, 0..) |p, i| at.putAssumeCapacity(p.pid, @intCast(i));

    // Each process belongs to the group of its highest ancestor that is not
    // behind scaffolding.
    const root_of = try a.alloc(u32, procs.len);
    for (procs, 0..) |p, i| {
        var cur: u32 = @intCast(i);
        var hops: u32 = 0;
        while (hops < 64) : (hops += 1) {
            const parent = at.get(procs[cur].ppid) orelse break;
            if (scaffolding(&procs[parent])) break;
            cur = parent;
        }
        root_of[i] = if (p.kthread) std.math.maxInt(u32) else cur;
    }

    var by_root = std.AutoArrayHashMapUnmanaged(u32, std.ArrayList(u32)).empty;
    var kernel: std.ArrayList(u32) = .empty;
    for (procs, 0..) |_, i| {
        if (root_of[i] == std.math.maxInt(u32)) {
            try kernel.append(a, @intCast(i));
            continue;
        }
        const slot = try by_root.getOrPut(a, root_of[i]);
        if (!slot.found_existing) slot.value_ptr.* = .empty;
        try slot.value_ptr.append(a, @intCast(i));
    }

    var groups: std.ArrayList(Group) = .empty;
    var it = by_root.iterator();
    while (it.next()) |kv| {
        const root = &procs[kv.key_ptr.*];
        // The root leads its group.
        const members = kv.value_ptr.items;
        if (std.mem.indexOfScalar(u32, members, kv.key_ptr.*)) |pos| std.mem.swap(u32, &members[0], &members[pos]);
        const entry = index.lookup(std.fs.path.basename(root.exe)) orelse index.lookup(root.name);
        var g: Group = .{
            .kind = if (entry != null and !entry.?.hidden) .app else .background,
            .root = root.pid,
            .name = if (entry) |e| e.name else root.name,
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

fn fake(pid: i32, ppid: i32, name: []const u8, exe: []const u8) Proc {
    return .{ .pid = pid, .ppid = ppid, .name = name, .exe = exe };
}

test "Exec lines name the program that runs" {
    try std.testing.expectEqualStrings("firefox", execProgram("firefox %u"));
    try std.testing.expectEqualStrings("tool", execProgram("env FOO=1 /opt/x/bin/tool %U"));
    try std.testing.expectEqualStrings("code", execProgram("\"/usr/bin/code\" --unity-launch %F"));
    try std.testing.expectEqualStrings("", execProgram(""));
}

test "a launcher entry is read from its main group only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text =
        \\[Desktop Entry]
        \\Type=Application
        \\Name=Web Browser
        \\Exec=/usr/lib/browser/browser-bin %u
        \\Icon=browser
        \\StartupWMClass=Browser
        \\
        \\[Desktop Action new-window]
        \\Name=New Window
        \\Exec=browser --new-window
    ;
    const e = parseDesktop(arena.allocator(), "browser", text).?;
    try std.testing.expectEqualStrings("Web Browser", e.name);
    try std.testing.expectEqualStrings("browser-bin", e.program);
    try std.testing.expectEqualStrings("browser", e.icon);
    try std.testing.expectEqualStrings("Browser", e.wm_class);
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
    const groups = try build(arena.allocator(), &procs, &ix);

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
    const groups = try build(arena.allocator(), &procs, &ix);
    for (groups) |g| try std.testing.expect(g.kind != .app);
}
