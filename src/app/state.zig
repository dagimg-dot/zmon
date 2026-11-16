//! zmon's state: what is selected, how the list is sorted, and the sample the
//! pages show. The sampler runs from the view's clock, once a second.
const std = @import("std");
const linux = std.os.linux;
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const core = @import("zmon-core");
const system = @import("zmon-system");
const apps = system.apps;

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
    resource: Resource = .cpu,
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
};
