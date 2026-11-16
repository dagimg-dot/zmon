//! zmon's state and its view: a sidebar of pages beside the page itself.
//! The view is a function of this state, drawn again on every input; the
//! sampler runs from the view's clock, once a second.
const std = @import("std");
const linux = std.os.linux;
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const core = @import("zmon-core");
const sampler = @import("sampler.zig");
const system = @import("zmon-system");
const apps = system.apps;
const theme = @import("theme.zig");
const processes = @import("processes_view.zig");
const performance = @import("performance_view.zig");

pub const Page = enum { processes, performance };
pub const Sort = enum { name, cpu, memory, disk };
pub const Resource = enum { cpu, memory, disk, network };

/// What one line of the process list shows.
pub const Row = union(enum) {
    section: struct { title: []const u8, count: usize },
    group: u32,
    proc: u32,
};

pub const State = struct {
    gpa: std.mem.Allocator,
    sampler: sampler.Sampler,
    index: apps.Index,
    icons: apps.Icons,
    /// Groups and rows of the current sample; replaced with every sample.
    built: std.heap.ArenaAllocator,
    groups: []apps.Group = &.{},
    rows: []Row = &.{},

    page: Page = .processes,
    sort: Sort = .cpu,
    ascending: bool = false,
    resource: Resource = .cpu,
    /// The pid of the selected group's root or process (0: none).
    selected: i32 = 0,
    expanded: std.AutoHashMapUnmanaged(i32, void) = .empty,
    confirm: bool = false,
    toaster: kit.Toaster,
    next_sample: f64 = 0,
    /// Overrides the system's light or dark setting (tests, screenshots).
    dark: ?bool = null,

    pub fn init(gpa: std.mem.Allocator, io: std.Io) State {
        var s: State = .{
            .gpa = gpa,
            .sampler = .init(gpa, io),
            .index = .init(gpa),
            .icons = .init(gpa, io),
            .built = .init(gpa),
            .toaster = .{ .gpa = gpa },
        };
        apps.loadEntries(&s.index, io);
        return s;
    }

    pub fn deinit(s: *State) void {
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

    fn busier(procs: []const sampler.Proc, x: u32, y: u32) bool {
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
    /// processes, never init, the kernel's threads or zmon itself.
    pub fn endTask(s: *State, force: bool) void {
        var sent: usize = 0;
        var refused: usize = 0;
        const me = linux.getuid();
        const self = linux.getpid();
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
            if (linux.errno(linux.kill(p.pid, if (force) .KILL else .TERM)) == .SUCCESS) sent += 1;
        }
        if (sent > 0) {
            s.toaster.push(.{ .title = if (force) "Killed" else "Asked to quit", .message = "" });
        } else if (refused > 0) {
            s.toaster.push(.{ .title = "Can't end that", .message = "Only your own processes can be ended here." });
        }
    }

    pub fn view(s: *State, c: *ui.Context) void {
        const dark = s.dark orelse nanoui.isDark();
        // The window takes its font from the theme the view *chose*, not from `c.theme`.
        const chosen = theme.theme(dark);
        c.theme = chosen;
        c.theme_chosen = chosen;
        const k = theme.colors(dark);
        c.frameIn(s.tick(c.time));

        const root = ui.div(c).row().sizeFull().bg(k.page);
        defer root.end();
        sidebar(c, s, k);
        _ = c.leaf(.{ .width = .{ .px = 1 }, .height = .fill, .background = k.separator }, .none, null);
        {
            const main = ui.div(c).column().grow().w(0).hFull().clip();
            defer main.end();
            switch (s.page) {
                .processes => processes.page(c, s, k),
                .performance => performance.page(c, s, k),
            }
        }
        processes.confirmDialog(c, s, k);
        s.toaster.view(c);
    }
};

fn sidebar(c: *ui.Context, s: *State, k: theme.Colors) void {
    const side = ui.div(c).column().w(188).hFull().bg(k.panel).p(10).gap(2);
    defer side.end();
    {
        const head = ui.div(c).row().h(44).px(8).itemsCenter().gap(8);
        defer head.end();
        ui.text(c, "zmon", .{ .size = 17, .weight = .bold, .color = k.text });
    }
    const items = [_]struct { page: Page, label: []const u8, icon: []const u8 }{
        .{ .page = .processes, .label = "Processes", .icon = "list.bullet" },
        .{ .page = .performance, .label = "Performance", .icon = "waveform.path.ecg" },
    };
    for (items) |it| {
        ui.key(c, it.label);
        const on = s.page == it.page;
        const row = ui.div(c).row().wFull().h(34).px(10).itemsCenter().gap(10).rounded(8).control();
        defer row.end();
        if (on) _ = row.bg(k.selected) else _ = row.hover(k.hover);
        if (row.clicked()) s.page = it.page;
        const ink = if (on) k.selected_text else k.text;
        ui.icon(c, it.icon, .{ .size = 14, .frame = 18, .color = ink });
        ui.text(c, it.label, .{ .size = 13.5, .weight = if (on) .semibold else .regular, .color = ink });
    }
    ui.spacer(c);
    var b1: [24]u8 = undefined;
    var b2: [24]u8 = undefined;
    ui.text(c, c.print("{s} CPU   {s} RAM", .{
        core.fmt.percent(&b1, s.sampler.cpu_pct),
        core.fmt.percent(&b2, if (s.sampler.memory.total > 0) @as(f32, @floatFromInt(s.sampler.memory.used())) * 100 / @as(f32, @floatFromInt(s.sampler.memory.total)) else 0),
    }), .{ .size = 11.5, .color = k.tertiary });
}
