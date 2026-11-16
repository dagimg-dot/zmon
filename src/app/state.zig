//! zmon's state: what is selected, how the list is sorted, the sample the
//! pages show, the settings and the themes. Samples come from the sampler's
//! own thread (system/sampler/worker.zig) as snapshots; the state only reads
//! them. Without the thread (tests), `tick` takes them itself, once a second.
const std = @import("std");
const nanoui = @import("nanoui");
const ui = nanoui.ui;
const kit = nanoui.kit;
const core = @import("zmon-core");
const system = @import("zmon-system");
const apps = system.apps;

/// The page shown: the apps, every process, one device's page, or Settings.
pub const Page = enum { apps, processes, cpu, memory, disk, network, settings };
pub const Sort = enum { name, user, pid, cpu, memory, disk };

/// How a list is sorted.
pub const Order = struct {
    key: Sort = .cpu,
    ascending: bool = false,
};

/// What one line of the Apps list shows: an app, or one of its processes.
pub const Row = union(enum) {
    group: u32,
    proc: u32,
};

const none: u32 = std.math.maxInt(u32);

/// Samples to wait before saying a process that was asked to quit didn't.
const quit_wait = 3;

/// What was asked to quit: up to 64 of its processes, by pid and start time.
const QuitWatch = struct {
    due: u64,
    name: [64]u8 = undefined,
    name_len: u8 = 0,
    procs: [64]struct { pid: i32, start: u64 } = undefined,
    len: u8 = 0,
};

pub const State = struct {
    gpa: std.mem.Allocator,
    /// Account names, for the User column.
    users: system.users.Users,
    /// The details pane is open beside the list.
    details_open: bool = false,
    /// Samples the machine, on its own thread once `startSampling` runs.
    worker: *system.sampler.Worker,
    /// The sample the pages show: the worker's, read-only, until the next one.
    sample: *const system.sampler.Snapshot,
    /// Sample on the worker's thread (the app); tests leave it off and sample in `tick`.
    threaded: bool = false,
    /// What was last asked of the worker, to wake it only when that changes.
    asked: system.sampler.Want = .{},
    index: apps.Index,
    icons: apps.Icons,
    /// Groups and lists of the current sample; replaced with every sample.
    built: std.heap.ArenaAllocator,
    groups: []apps.Group = &.{},
    /// The Apps list: each app, then its processes when it is open.
    app_rows: []Row = &.{},
    /// The Processes list: indexes into the sample's processes, filtered by
    /// the search and sorted.
    proc_rows: []u32 = &.{},
    /// For each process in the sample, the index of its group (`none` if it has none).
    owner: []u32 = &.{},

    page: Page = .apps,
    app_order: Order = .{},
    proc_order: Order = .{},
    /// The pid of the selected app's root or one of its processes (0: none).
    selected_app: i32 = 0,
    /// The pid selected in Processes (0: none).
    selected_proc: i32 = 0,
    /// What Apps and Processes are filtered by: part of a name, or a pid.
    search: ui.TextBuffer = .{},
    /// The row the keyboard moved the selection to, scrolled into view by the next list drawn.
    reveal: ?usize = null,
    /// The keyboard shortcuts overlay is open.
    shortcuts_open: bool = false,
    /// The last input was a key, so focus is drawn (a click hides it again).
    keyboard: bool = false,
    /// Each page's entry in the sidebar, where Escape takes the focus back to.
    nav_ids: std.EnumArray(Page, u64) = .initFill(0),
    /// A page was opened from the keyboard: the focus goes into it once it is drawn.
    focus_content: bool = false,
    /// Where the keyboard's focus came from, for Escape to go back (app/focus.zig).
    focus_stack: core.focus.Stack = .{},
    /// The box of the list on the page shown, the Tab stop that owns the list's keys.
    list_id: u64 = 0,
    /// The focused box when the last frame ended.
    last_focus: u64 = 0,
    /// What was asked to quit, checked a few samples later.
    quit_watch: ?QuitWatch = null,
    toast_buf: [160]u8 = undefined,
    /// Settings turned reduced motion on, over whatever the system said.
    motion_forced: bool = false,
    expanded: std.AutoHashMapUnmanaged(i32, void) = .empty,
    /// A group opened or closed while the list was being drawn: the rows are
    /// rebuilt only after the list is done with them.
    pending_toggle: ?i32 = null,
    confirm: bool = false,
    /// A dialog was open when the last frame ended, so its closing can be seen.
    dialog_was_open: bool = false,
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
        const worker = system.sampler.Worker.create(gpa, io) catch @panic("out of memory");
        var s: State = .{
            .gpa = gpa,
            .io = io,
            .worker = undefined,
            .users = .init(gpa, io),
            .sample = undefined,
            .index = .init(gpa),
            .icons = .init(gpa, io),
            .built = .init(gpa),
            .toaster = .{ .gpa = gpa },
            .themes = .init(gpa),
            .config_arena = .init(gpa),
        };
        s.worker = worker;
        s.sample = worker.current();
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
        s.search.deinit();
        s.expanded.deinit(s.gpa);
        s.built.deinit();
        s.icons.deinit();
        s.index.deinit();
        s.worker.destroy();
        s.users.deinit();
    }

    /// Samples on the worker's own thread from now on; `waker` asks the
    /// window for a frame when a sample is ready.
    pub fn startSampling(s: *State, waker: ?system.sampler.Waker) void {
        s.worker.start(waker) catch {}; // without a thread, `tick` samples
    }

    /// Tells the worker what to read, takes a new sample if one came (or,
    /// without the thread, takes one when it is time), and returns how soon
    /// the view should look again.
    pub fn tick(s: *State, now: f64) f32 {
        // The process list is read only while something shows or watches it.
        var want: system.sampler.Want = .{
            .procs = s.onList() or s.confirm or s.quit_watch != null,
            .kernel_threads = s.settings.show_kernel_threads,
        };
        if (s.detailTarget()) |d| {
            want.detail_pid = d.pid;
            want.detail_start = d.start;
        }
        // Opening a list, or selecting another process with the details
        // open, reads at once rather than at the next second.
        const stale = want.procs and !s.sample.procs_read;
        const changed = want.procs != s.asked.procs or want.kernel_threads != s.asked.kernel_threads;
        const new_detail = want.detail_pid != s.asked.detail_pid or want.detail_start != s.asked.detail_start;
        s.worker.ask(want, (stale and changed) or (new_detail and want.detail_pid != 0));
        s.asked = want;
        var wait: f64 = 1.0; // a sample wakes the view itself; this is a fallback
        if (!s.worker.running()) {
            const detail_due = want.detail_pid != 0 and new_detail;
            if (s.sample.samples == 0 or now >= s.next_sample or stale or detail_due) {
                s.worker.step(); // `now` only schedules: rates use the machine's clock
                // On the second, not a second after each late frame; soon when the
                // sample has nothing to measure rates against; after a stall, from now.
                const period: f64 = if (s.worker.ratesPending()) 0.3 else 1.0;
                s.next_sample = if (s.next_sample > 0 and now - s.next_sample < period) s.next_sample + period else now + period;
            }
            wait = s.next_sample - now;
        }
        if (s.worker.take()) |snap| {
            s.sample = snap;
            s.rebuild();
            s.checkQuit();
        }
        return @floatCast(@max(0.05, wait));
    }

    /// Regroups the sample and lays out both lists.
    pub fn rebuild(s: *State) void {
        _ = s.built.reset(.retain_capacity);
        const a = s.built.allocator();
        const procs = s.sample.procs;
        s.groups = apps.group(a, procs, &s.index) catch &.{};
        std.mem.sort(apps.Group, s.groups, GroupOrder{ .o = s.app_order }, GroupOrder.less);
        s.owner = a.alloc(u32, procs.len) catch &.{};
        if (s.owner.len == procs.len) {
            @memset(s.owner, none);
            for (s.groups, 0..) |g, gi| for (g.members) |m| {
                s.owner[m] = @intCast(gi);
            };
        }
        s.app_rows = appRows(s, a) catch &.{};
        s.proc_rows = procRows(s, a) catch &.{};
    }

    /// The group a process belongs to, if any.
    pub fn ownerOf(s: *const State, proc: u32) ?*const apps.Group {
        if (proc >= s.owner.len or s.owner[proc] == none) return null;
        return &s.groups[s.owner[proc]];
    }

    /// How many apps are open.
    pub fn appCount(s: *const State) usize {
        var n: usize = 0;
        for (s.groups) |g| n += @intFromBool(g.kind == .app);
        return n;
    }

    const GroupOrder = struct {
        o: Order,
        fn key(c: GroupOrder, g: apps.Group) f64 {
            return switch (c.o.key) {
                .name, .user => 0,
                .pid => @floatFromInt(g.root),
                .cpu => g.cpu,
                .memory => @floatFromInt(g.memory),
                .disk => g.disk_bps,
            };
        }
        fn less(c: GroupOrder, x: apps.Group, y: apps.Group) bool {
            if (x.kind != y.kind) return @backingInt(x.kind) < @backingInt(y.kind);
            if (c.o.key == .name) {
                const lt = std.ascii.lessThanIgnoreCase(x.name, y.name);
                return if (c.o.ascending) lt else !lt and !std.ascii.eqlIgnoreCase(x.name, y.name);
            }
            const kx = c.key(x);
            const ky = c.key(y);
            if (kx == ky) return x.memory > y.memory;
            return if (c.o.ascending) kx < ky else kx > ky;
        }
    };

    const ProcOrder = struct {
        o: Order,
        procs: []const core.Proc,
        users: *const system.users.Users,
        fn key(c: ProcOrder, p: core.Proc) f64 {
            return switch (c.o.key) {
                .name, .user => 0,
                .pid => @floatFromInt(p.pid),
                .cpu => p.cpu,
                .memory => @floatFromInt(p.memory),
                .disk => p.disk_bps,
            };
        }
        fn less(c: ProcOrder, xi: u32, yi: u32) bool {
            const x = c.procs[xi];
            const y = c.procs[yi];
            if (c.o.key == .name or c.o.key == .user) {
                const nx = if (c.o.key == .name) x.name else c.users.name(x.uid) orelse "";
                const ny = if (c.o.key == .name) y.name else c.users.name(y.uid) orelse "";
                if (!std.ascii.eqlIgnoreCase(nx, ny)) {
                    const lt = std.ascii.lessThanIgnoreCase(nx, ny);
                    return if (c.o.ascending) lt else !lt;
                }
                return x.pid < y.pid;
            }
            const kx = c.key(x);
            const ky = c.key(y);
            if (kx == ky) return if (x.memory != y.memory) x.memory > y.memory else x.pid < y.pid;
            return if (c.o.ascending) kx < ky else kx > ky;
        }
    };

    /// Whether an app matches the search: its name, or any of its processes.
    fn appMatches(s: *const State, g: apps.Group) bool {
        const query = std.mem.trim(u8, s.search.text(), " ");
        if (query.len == 0 or core.search.containsIgnoreCase(g.name, query)) return true;
        for (g.members) |m| if (core.search.matches(s.sample.procs[m], query)) return true;
        return false;
    }

    fn appRows(s: *State, a: std.mem.Allocator) ![]Row {
        var rows: std.ArrayList(Row) = .empty;
        for (s.groups, 0..) |g, gi| {
            if (g.kind != .app or !s.appMatches(g)) continue;
            try rows.append(a, .{ .group = @intCast(gi) });
            if (g.members.len > 1 and s.expanded.contains(g.root)) {
                const kids = try a.dupe(u32, g.members[1..]);
                std.mem.sort(u32, kids, s.sample.procs, busier);
                for (kids) |m| try rows.append(a, .{ .proc = m });
            }
        }
        return rows.items;
    }

    fn procRows(s: *State, a: std.mem.Allocator) ![]u32 {
        const procs = s.sample.procs;
        var rows: std.ArrayList(u32) = .empty;
        for (procs, 0..) |p, i| {
            if (p.kthread and !s.settings.show_kernel_threads) continue;
            if (!core.search.matches(p, s.search.text())) continue;
            try rows.append(a, @intCast(i));
        }
        std.mem.sort(u32, rows.items, ProcOrder{ .o = s.proc_order, .procs = procs, .users = &s.users }, ProcOrder.less);
        return rows.items;
    }

    fn busier(procs: []const core.Proc, x: u32, y: u32) bool {
        if (procs[x].cpu != procs[y].cpu) return procs[x].cpu > procs[y].cpu;
        return procs[x].memory > procs[y].memory;
    }

    /// Sorts the list on the page shown by `key`, or reverses it when it already is.
    pub fn sortBy(s: *State, key: Sort) void {
        const o = if (s.page == .processes) &s.proc_order else &s.app_order;
        if (o.key == key) {
            o.ascending = !o.ascending;
        } else {
            o.* = .{ .key = key, .ascending = key == .name or key == .user or key == .pid };
        }
        s.rebuild();
    }

    pub fn toggle(s: *State, root: i32) void {
        if (s.expanded.remove(root)) {} else s.expanded.put(s.gpa, root, {}) catch {};
        s.rebuild();
    }

    /// Opens a page from its sidebar entry `from`. From the keyboard, the
    /// focus follows into the page, as in a two-pane app, and Escape comes
    /// back to the entry.
    pub fn openFromSidebar(s: *State, page: Page, from: u64) void {
        s.open(page);
        if (!s.keyboard) return;
        s.focus_stack.push(from);
        s.focus_content = true;
    }

    /// Opens a page. Settings reads the theme folder again as it opens.
    pub fn open(s: *State, page: Page) void {
        if (page == .settings and s.page != .settings) s.reload_themes = true;
        s.page = page;
    }

    /// A dialog is open over the page: End task's or the shortcuts.
    pub fn dialogOpen(s: *const State) bool {
        return s.confirm or s.shortcuts_open;
    }

    /// Whether the page shown is one of the two lists.
    pub fn onList(s: *const State) bool {
        return s.page == .apps or s.page == .processes;
    }

    /// The row of the selection in the list shown, if it is in the list.
    pub fn selectedRow(s: *const State) ?usize {
        switch (s.page) {
            .apps => for (s.app_rows, 0..) |r, i| {
                const pid = switch (r) {
                    .group => |g| s.groups[g].root,
                    .proc => |p| s.sample.procs[p].pid,
                };
                if (pid == s.selected_app) return i;
            },
            .processes => for (s.proc_rows, 0..) |p, i| {
                if (s.sample.procs[p].pid == s.selected_proc) return i;
            },
            else => {},
        }
        return null;
    }

    fn rowCount(s: *const State) usize {
        return switch (s.page) {
            .apps => s.app_rows.len,
            .processes => s.proc_rows.len,
            else => 0,
        };
    }

    fn selectRow(s: *State, i: usize) void {
        switch (s.page) {
            .apps => s.selected_app = switch (s.app_rows[i]) {
                .group => |g| s.groups[g].root,
                .proc => |p| s.sample.procs[p].pid,
            },
            .processes => s.selected_proc = s.sample.procs[s.proc_rows[i]].pid,
            else => return,
        }
        s.reveal = i;
    }

    /// Moves the selection `by` rows, stopping at the ends. With nothing
    /// selected, down starts at the top and up at the bottom.
    pub fn moveSelection(s: *State, by: isize) void {
        const n = s.rowCount();
        if (n == 0) return;
        const last: isize = @intCast(n - 1);
        const at: isize = if (s.selectedRow()) |i| @as(isize, @intCast(i)) + by else if (by > 0) 0 else last;
        s.selectRow(@intCast(std.math.clamp(at, 0, last)));
    }

    /// Selects the first or the last row.
    pub fn selectEnd(s: *State, last: bool) void {
        const n = s.rowCount();
        if (n > 0) s.selectRow(if (last) n - 1 else 0);
    }

    /// Opens or closes the selected app in Apps. Closing from one of its
    /// processes selects the app instead, as a tree view does.
    pub fn openSelected(s: *State, want_open: bool) void {
        if (s.page != .apps) return;
        const i = s.selectedRow() orelse return;
        switch (s.app_rows[i]) {
            .group => |gi| {
                const g = s.groups[gi];
                if (g.members.len > 1 and s.expanded.contains(g.root) != want_open) s.toggle(g.root);
            },
            .proc => |p| if (!want_open) {
                if (s.ownerOf(p)) |g| {
                    s.selected_app = g.root;
                    s.reveal = s.selectedRow();
                }
            },
        }
    }

    /// Opens the selected app if it is closed and closes it if it is open.
    pub fn toggleSelected(s: *State) void {
        if (s.page != .apps) return;
        const i = s.selectedRow() orelse return;
        switch (s.app_rows[i]) {
            .group => |gi| if (s.groups[gi].members.len > 1) s.toggle(s.groups[gi].root),
            .proc => {},
        }
    }

    /// Asks before ending the selection when Settings says to (the dialog
    /// offers both End task and Force quit), else ends it, by force if asked.
    pub fn askEndTask(s: *State, force: bool) void {
        if (s.target() == null) return;
        if (s.settings.confirm_end_task) s.confirm = true else s.endTask(force);
    }

    /// The process the details pane describes: the selection on a list page,
    /// an app by the process it hangs from.
    pub fn detailTarget(s: *const State) ?struct { pid: i32, start: u64 } {
        if (!s.details_open or !s.onList()) return null;
        const pid = s.selected();
        const p = s.sample.find(pid) orelse return null;
        return .{ .pid = pid, .start = p.start };
    }

    /// The name of the account `uid`, or its number when it has none.
    pub fn userName(s: *const State, buf: []u8, uid: u32) []const u8 {
        return s.users.name(uid) orelse std.fmt.bufPrint(buf, "{d}", .{uid}) catch "";
    }

    /// The pid selected on the page shown.
    fn selected(s: *const State) i32 {
        return if (s.page == .processes) s.selected_proc else s.selected_app;
    }

    /// The app selected in Apps, when the selection is an app and not one of its processes.
    pub fn selectedGroup(s: *const State) ?*const apps.Group {
        if (s.page == .processes or s.selected_app == 0) return null;
        for (s.groups) |*g| if (g.root == s.selected_app and g.kind == .app) return g;
        return null;
    }

    /// What ending the selection would end: its name and how many processes.
    pub fn target(s: *const State) ?struct { name: []const u8, count: usize } {
        const pid = s.selected();
        if (pid == 0) return null;
        // Only what can be seen: not a row a search or a closed app hides.
        if (s.selectedRow() == null) return null;
        if (s.selectedGroup()) |g| return .{ .name = g.name, .count = g.members.len };
        if (s.sample.find(pid)) |p| return .{ .name = p.name, .count = 1 };
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
        const procs = s.sample.procs;
        var one = [_]u32{0};
        const members: []const u32 = if (s.selectedGroup()) |g| g.members else blk: {
            const pid = s.selected();
            for (procs, 0..) |p, i| if (p.pid == pid) {
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
            if (control.signal(s.io, p.pid, p.start, if (force) .kill else .quit)) sent += 1;
        }
        const name = if (s.target()) |x| x.name else "it";
        if (sent > 0) {
            if (force) {
                s.toaster.push(.{ .title = s.toastText("Stopped {s}", .{name}), .message = "Force quit ends a process at once." });
            } else {
                s.toaster.push(.{ .title = s.toastText("Asked {s} to quit", .{name}), .message = "" });
                s.watchQuit(name, members);
            }
        } else if (refused > 0) {
            s.toaster.push(.{ .title = s.toastText("Can't end {s}", .{name}), .message = "Only your own processes can be ended here." });
        } else {
            s.toaster.push(.{ .title = s.toastText("Couldn't end {s}", .{name}), .message = "It may have ended already." });
        }
    }

    /// A toast's text, formatted into a buffer of the state's (the toaster copies it).
    fn toastText(s: *State, comptime f: []const u8, args: anytype) []const u8 {
        return std.fmt.bufPrint(&s.toast_buf, f, args) catch f;
    }

    /// Remembers what was asked to quit, to say so if it is still running a
    /// few samples later, when Force quit is what's needed.
    fn watchQuit(s: *State, name: []const u8, members: []const u32) void {
        var w: QuitWatch = .{ .due = s.sample.samples + quit_wait };
        w.name_len = @intCast(@min(name.len, w.name.len));
        @memcpy(w.name[0..w.name_len], name[0..w.name_len]);
        for (members) |i| {
            if (w.len == w.procs.len) break;
            const p = s.sample.procs[i];
            w.procs[w.len] = .{ .pid = p.pid, .start = p.start };
            w.len += 1;
        }
        s.quit_watch = w;
    }

    /// After a quit was asked: still running a few seconds on, say so.
    fn checkQuit(s: *State) void {
        const w = s.quit_watch orelse return;
        if (s.sample.samples < w.due) return;
        s.quit_watch = null;
        var alive: usize = 0;
        for (w.procs[0..w.len]) |q| {
            for (s.sample.procs) |p| if (p.pid == q.pid and p.start == q.start) {
                alive += 1;
                break;
            };
        }
        if (alive == 0) return;
        s.toaster.push(.{
            .title = s.toastText("{s} is still running", .{w.name[0..w.name_len]}),
            .message = "It didn't quit. Shift+Delete or Force quit stops it, losing unsaved work.",
            .duration = 8,
        });
    }
};
