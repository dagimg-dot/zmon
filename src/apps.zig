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
const desktop = @import("desktop.zig");
const xdg = @import("xdg.zig");
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

    /// Reads every .desktop file in the standard application directories. A
    /// name an earlier (more specific) directory already claimed is kept.
    pub fn load(ix: *Index, io: std.Io) void {
        const dirs = xdg.applicationDirs(ix.arena.allocator()) catch return;
        for (dirs) |d| ix.loadDir(io, d);
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
        const parsed = desktop.DesktopEntry.parse(text);
        if (!parsed.is_app or parsed.name.len == 0) return;
        const aa = ix.arena.allocator();
        const e: Entry = .{
            .name = aa.dupe(u8, parsed.name) catch return,
            .icon = aa.dupe(u8, parsed.icon) catch "",
            .program = aa.dupe(u8, desktop.extractExecBinary(parsed.exec) orelse "") catch "",
            .wm_class = aa.dupe(u8, parsed.wm_class) catch "",
            .id = aa.dupe(u8, id) catch "",
            .hidden = parsed.no_display,
        };
        // A web app launcher (`brave --app-id=...`) runs the browser, which is not it:
        // it must not claim the browser's program name.
        const web_app = std.mem.indexOf(u8, parsed.exec, "--app-id=") != null or std.mem.indexOf(u8, parsed.exec, " --app=") != null;
        const at: u32 = @intCast(ix.entries.items.len);
        ix.entries.append(ix.arena.allocator(), e) catch return;
        const a = ix.arena.allocator();
        for ([_][]const u8{ if (web_app) "" else e.program, e.wm_class, e.id }) |key| {
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

test "a launcher entry is read from its main group only" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("browser", "[Desktop Entry]\nType=Application\nName=Web Browser\nExec=/usr/lib/browser/browser-bin %u\nIcon=browser\nStartupWMClass=Browser\n\n[Desktop Action new-window]\nName=New Window\nExec=browser --new-window\n");
    const e = ix.lookup("browser-bin").?;
    try std.testing.expectEqualStrings("Web Browser", e.name);
    try std.testing.expectEqualStrings("browser", e.icon);
    try std.testing.expectEqualStrings("Browser", e.wm_class);
    try std.testing.expect(ix.lookup("browser") == e); // the launcher's file name finds it too
    try std.testing.expect(ix.lookup("BROWSER-BIN") == e);
}

test "a web app launcher does not take the browser's name" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("brave-abc-Default", "[Desktop Entry]\nType=Application\nName=Google Keep\nExec=brave --profile-directory=Default --app-id=abc\nStartupWMClass=crx_abc\n");
    ix.add("brave-browser", "[Desktop Entry]\nType=Application\nName=Brave\nExec=brave %U\n");
    try std.testing.expectEqualStrings("Brave", ix.lookup("brave").?.name);
    try std.testing.expectEqualStrings("Google Keep", ix.lookup("crx_abc").?.name);
}

test "the first entry to claim a name keeps it, so the user's own wins" {
    var ix = Index.init(std.testing.allocator);
    defer ix.deinit();
    ix.add("tool", "[Desktop Entry]\nType=Application\nName=Mine\nExec=tool\n");
    ix.add("tool", "[Desktop Entry]\nType=Application\nName=System\nExec=tool\n");
    try std.testing.expectEqualStrings("Mine", ix.lookup("tool").?.name);
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
