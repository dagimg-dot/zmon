//! zmon's state: what is selected, how the list is sorted, the sample the
//! pages show, the settings and the themes. The sampler runs from the view's
//! clock, once a second.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const core = @import("zmon-core");
const system = @import("zmon-system");
const apps = system.apps;

/// The page shown: the process list, or one device's page.
pub const Page = enum { processes, cpu, memory, disk, network, settings };
pub const Sort = enum { name, cpu, memory, disk };

/// What one line of the process list shows.
pub const Row = union(enum) {
    section: struct { title: []const u8, count: usize },
    group: u32,
    proc: u32,
};

pub const State = struct {
    gpa: std.mem.Allocator,
    sampler: system.sampler.Sampler,
    index: apps.Index,
    icons: apps.Icons,
    /// Groups and rows of the current sample; replaced with every sample.
    built: std.heap.ArenaAllocator,
    groups: []apps.Group = &.{},
    rows: []Row = &.{},

    page: Page = .processes,
    sort: Sort = .cpu,
    ascending: bool = false,
    /// The pid of the selected group's root or process (0: none).
    selected: i32 = 0,
    expanded: std.AutoHashMapUnmanaged(i32, void) = .empty,
    /// A group opened or closed while the list was being drawn: the rows are
    /// rebuilt only after the list is done with them.
    pending_toggle: ?i32 = null,
    confirm: bool = false,
    toaster: kit.Toaster,
    next_sample: f64 = 0,
    /// Overrides the system's light or dark setting (tests, screenshots).
    dark: ?bool = null,

    io: std.Io,
    settings: core.settings.Settings = .{},
    themes: core.themes.Library,
    /// Where settings are saved and themes added; null in tests, which then
    /// neither read nor write anything.
    config: ?system.config.Location = null,
    config_arena: std.heap.ArenaAllocator,
    /// Themes are read again when Settings opens, at the start of the next frame.
    reload_themes: bool = false,
    /// Which kind of theme the gallery shows when zmon follows the system (null: the one in effect).
    gallery_dark: ?bool = null,
    /// A failed save is said once, not on every change.
    save_failed: bool = false,

    pub fn init(gpa: std.mem.Allocator, io: std.Io, config: ?system.config.Location) State {
        var s: State = .{
            .gpa = gpa,
            .io = io,
            .sampler = .init(gpa, io),
            .index = .init(gpa),
            .icons = .init(gpa, io),
            .built = .init(gpa),
            .toaster = .{ .gpa = gpa },
            .themes = .init(gpa),
            .config_arena = .init(gpa),
        };
        apps.loadEntries(&s.index, io);
        if (config) |at| {
            const a = s.config_arena.allocator();
            s.config = .{ .dir = a.dupe(u8, at.dir) catch "", .themes = a.dupe(u8, at.themes) catch "" };
            s.settings = system.config.loadSettings(io, a, at);
        }
        s.loadThemes(&s.themes);
        return s;
    }

    /// The built-in themes, then a person's own from their theme folder.
    fn loadThemes(s: *State, lib: *core.themes.Library) void {
        core.themes.builtin.addAll(lib);
        if (s.config) |at| {
            for (system.config.userThemes(s.io, lib.arena.allocator(), at)) |t| lib.add(t.id, t.text);
        }
        lib.resolveAll();
    }

    /// Reads the theme files again. Called at the start of a frame, so nothing
    /// drawn still points into the old themes.
    pub fn reloadThemes(s: *State) void {
        var fresh: core.themes.Library = .init(s.gpa);
        s.loadThemes(&fresh);
        s.themes.deinit();
        s.themes = fresh;
    }

    /// Whether zmon shows its dark theme now.
    pub fn isDark(s: *const State, system_dark: bool) bool {
        if (s.dark) |d| return d;
        return switch (s.settings.appearance) {
            .system => system_dark,
            .light => false,
            .dark => true,
        };
    }

    /// The theme chosen for dark or light, or Graphite when that theme is gone.
    pub fn theme(s: *const State, dark: bool) *const core.themes.Theme {
        const id = if (dark) s.settings.dark_theme.slice() else s.settings.light_theme.slice();
        return s.themes.find(id) orelse s.themes.find(if (dark) "graphite-dark" else "graphite-light") orelse &s.themes.themes.items[0];
    }

    /// Whether the chosen theme for dark or light is missing (and Graphite stands in).
    pub fn themeMissing(s: *const State, dark: bool) bool {
        const id = if (dark) s.settings.dark_theme.slice() else s.settings.light_theme.slice();
        return s.themes.find(id) == null;
    }

    pub fn chooseTheme(s: *State, dark: bool, id: []const u8) void {
        if (dark) s.settings.dark_theme.set(id) else s.settings.light_theme.set(id);
        s.save();
    }

    /// Writes the settings, if there is somewhere to write them.
    pub fn save(s: *State) void {
        const at = s.config orelse return;
        system.config.saveSettings(s.io, at, &s.settings) catch {
            if (!s.save_failed) s.toaster.push(.{ .title = "Couldn't save your settings", .message = "They apply until zmon closes." });
            s.save_failed = true;
            return;
        };
        s.save_failed = false;
    }

    pub fn resetSettings(s: *State) void {
        s.settings = .{};
        s.save();
        s.rebuild();
    }

    pub fn deinit(s: *State) void {
        s.themes.deinit();
        s.config_arena.deinit();
        s.toaster.deinit();
        s.expanded.deinit(s.gpa);
        s.built.deinit();
        s.icons.deinit();
        s.index.deinit();
        s.sampler.deinit();
    }

    /// Samples when it is time; returns the seconds until the next.
    pub fn tick(s: *State, now: f64) f32 {
        if (s.sampler.samples == 0 or now >= s.next_sample) {
            s.sampler.collect(now);
            s.rebuild();
            // Rates need two samples: the second comes quickly so the first screen isn't all zeros.
            s.next_sample = now + (if (s.sampler.samples <= 1) @as(f64, 0.3) else 1.0);
        }
        return @floatCast(@max(0.05, s.next_sample - now));
    }

    /// Regroups the sample and lays out the process list.
    pub fn rebuild(s: *State) void {
        _ = s.built.reset(.retain_capacity);
        const a = s.built.allocator();
        s.groups = apps.group(a, s.sampler.procs, &s.index) catch &.{};
        std.mem.sort(apps.Group, s.groups, SortCtx{ .s = s }, SortCtx.less);
        s.rows = layout(s, a) catch &.{};
    }

    const SortCtx = struct {
        s: *const State,
        fn key(c: SortCtx, g: apps.Group) f64 {
            return switch (c.s.sort) {
                .name => 0,
                .cpu => g.cpu,
                .memory => @floatFromInt(g.memory),
                .disk => g.disk_bps,
            };
        }
        fn less(c: SortCtx, x: apps.Group, y: apps.Group) bool {
            if (x.kind != y.kind) return @backingInt(x.kind) < @backingInt(y.kind);
            if (c.s.sort == .name) {
                const lt = std.ascii.lessThanIgnoreCase(x.name, y.name);
                return if (c.s.ascending) lt else !lt and !std.ascii.eqlIgnoreCase(x.name, y.name);
            }
            const kx = c.key(x);
            const ky = c.key(y);
            if (kx == ky) return x.memory > y.memory;
            return if (c.s.ascending) kx < ky else kx > ky;
        }
    };

    fn layout(s: *State, a: std.mem.Allocator) ![]Row {
        var rows: std.ArrayList(Row) = .empty;
        const titles = [_][]const u8{ "Apps", "Background processes", "Kernel" };
        var kind: ?apps.Kind = null;
        for (s.groups, 0..) |g, gi| {
            if (g.kind == .kernel and !s.settings.show_kernel_threads) continue;
            if (kind == null or kind.? != g.kind) {
                kind = g.kind;
                var count: usize = 0;
                for (s.groups) |o| if (o.kind == g.kind) {
                    count += 1;
                };
                try rows.append(a, .{ .section = .{ .title = titles[@backingInt(g.kind)], .count = count } });
            }
            try rows.append(a, .{ .group = @intCast(gi) });
            if (g.members.len > 1 and s.expanded.contains(g.root)) {
                const kids = try a.dupe(u32, g.members[1..]);
                std.mem.sort(u32, kids, s.sampler.procs, busier);
                for (kids) |m| try rows.append(a, .{ .proc = m });
            }
        }
        return rows.items;
    }

    fn busier(procs: []const core.Proc, x: u32, y: u32) bool {
        if (procs[x].cpu != procs[y].cpu) return procs[x].cpu > procs[y].cpu;
        return procs[x].memory > procs[y].memory;
    }

    pub fn sortBy(s: *State, key: Sort) void {
        if (s.sort == key) {
            s.ascending = !s.ascending;
        } else {
            s.sort = key;
            s.ascending = key == .name;
        }
        s.rebuild();
    }

    pub fn toggle(s: *State, root: i32) void {
        if (s.expanded.remove(root)) {} else s.expanded.put(s.gpa, root, {}) catch {};
        s.rebuild();
    }

    /// The group whose root is `pid`, if the selection is one.
    pub fn selectedGroup(s: *const State) ?*const apps.Group {
        for (s.groups) |*g| if (g.root == s.selected and g.kind != .kernel) return g;
        return null;
    }

    /// What ending the selection would end: its name and how many processes.
    pub fn target(s: *const State) ?struct { name: []const u8, count: usize } {
        if (s.selected == 0) return null;
        if (s.selectedGroup()) |g| return .{ .name = g.name, .count = g.members.len };
        if (s.sampler.find(s.selected)) |p| return .{ .name = p.name, .count = 1 };
        return null;
    }

    /// Asks the selection to quit (SIGTERM), or kills it. Only the user's own
    /// processes, never init, the kernel's threads or zmon itself, and only the
    /// very processes that were sampled (a pid can be reused within a second).
    pub fn endTask(s: *State, force: bool) void {
        var sent: usize = 0;
        var refused: usize = 0;
        const control = system.sampler.control;
        const me = control.currentUid();
        const self = control.selfPid();
        const procs = s.sampler.procs;
        var one = [_]u32{0};
        const members: []const u32 = if (s.selectedGroup()) |g| g.members else blk: {
            for (procs, 0..) |p, i| if (p.pid == s.selected) {
                one[0] = @intCast(i);
                break :blk &one;
            };
            break :blk &.{};
        };
        for (members) |i| {
            const p = procs[i];
            if (p.pid <= 1 or p.pid == self or p.kthread or p.uid != me) {
                refused += 1;
                continue;
            }
            if (control.signal(s.sampler.io, p.pid, p.start, if (force) .kill else .quit)) sent += 1;
        }
        if (sent > 0) {
            s.toaster.push(.{ .title = if (force) "Killed" else "Asked to quit", .message = "" });
        } else if (refused > 0) {
            s.toaster.push(.{ .title = "Can't end that", .message = "Only your own processes can be ended here." });
        }
    }
};
